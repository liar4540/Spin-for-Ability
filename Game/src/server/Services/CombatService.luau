--!strict
-- CombatService: battlegrounds combat. The ONE damage path for M1s and abilities.
-- Vault: 12 Combat System. Build order done: 1 (states), 2 (M1 string), 3 (ApplyHit).
-- Not yet: block/guard meter, real ragdoll physics, air combo, dash, ragdoll cancel.
--
-- Abilities must call CombatService.ApplyHit; never TakeDamage / stun / ragdoll directly.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Knockback = require(Shared:WaitForChild("Knockback"))
local Combat = require(Shared:WaitForChild("Config"):WaitForChild("Combat"))

local Services = script.Parent
local StateService = require(Services:WaitForChild("StateService"))
local HitboxService = require(Services:WaitForChild("HitboxService"))
local RemoteGuard = require(Services:WaitForChild("RemoteGuard"))

-- Training dummies (tag "TrainingDummy", made in Studio) heal back to full this long after a hit.
local DUMMY_HEAL_SECONDS = 2

export type Hit = {
	damage: number,
	stun: number?, -- seconds of hitstun
	ragdoll: number?, -- seconds of ragdoll (placeholder: state + knockback; physics ragdoll comes later)
	launch: Vector3?, -- velocity relative to the attacker's facing (-Z = forward, +Y = up)
	guardBreak: boolean?, -- ignores block (block not built yet)
	abilityId: string, -- "M1_1".."M1_4" for M1s
}

local CombatService = {}

local hitEffect: RemoteEvent
local knockbackRemote: RemoteEvent

-- Per-attacker M1 string.
type Chain = { index: number, lastAt: number, nextAllowedAt: number }
local chains: { [Player]: Chain } = {}

local FINISHER_BY_INPUT: { [string]: string } = { None = "Knockback", Space = "Uppercut", S = "GroundSmash" }

local function rootOf(model: Model?): BasePart?
	return model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function push(model: Model, root: BasePart, velocity: Vector3)
	local victim = Players:GetPlayerFromCharacter(model)
	if victim then
		-- A player's character is moved by their own client (it owns the physics).
		knockbackRemote:FireClient(victim, velocity)
	else
		Knockback.Apply(root, velocity)
	end
end

-- Old damage path, kept so existing abilities keep working. Prefer ApplyHit.
-- knockback is a world-space velocity (studs/second); zero vector = none.
function CombatService.DealDamage(_attacker: Player, target: Humanoid, amount: number, knockback: Vector3, abilityId: string)
	if target.Health <= 0 then
		return
	end
	target:TakeDamage(amount)
	local model = target.Parent
	local root = model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (model and model:IsA("Model") and root) then
		return
	end
	if knockback.Magnitude > 0 then
		push(model, root, knockback)
	end
	hitEffect:FireAllClients(model, abilityId, root.Position)
end

-- The ONE damage path. Returns true if the hit landed.
function CombatService.ApplyHit(attacker: Player, target: Model, hit: Hit): boolean
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	local root = rootOf(target)
	if not humanoid or not root or humanoid.Health <= 0 then
		return false
	end
	if StateService.HasIFrames(target) then
		return false
	end
	-- TODO (build step 5): block check — front cone + guard meter, unless hit.guardBreak.

	local scale = StateService.RegisterComboHit(target)
	humanoid:TakeDamage(hit.damage * scale)

	if hit.ragdoll and hit.ragdoll > 0 then
		StateService.Set(target, "Ragdolled", hit.ragdoll)
	elseif hit.stun and hit.stun > 0 and not StateService.IsStunImmune(target) then
		StateService.Set(target, "Stunned", hit.stun)
	end

	if hit.launch and hit.launch.Magnitude > 0 then
		local attackerRoot = rootOf(attacker.Character)
		local facing = if attackerRoot then attackerRoot.CFrame else root.CFrame
		local flatLook = Vector3.new(facing.LookVector.X, 0, facing.LookVector.Z)
		local basis = if flatLook.Magnitude > 0.01 then CFrame.lookAt(Vector3.zero, flatLook) else CFrame.identity
		push(target, root, basis:VectorToWorldSpace(hit.launch))
	end

	if not string.find(hit.abilityId, "^M1_") then
		StateService.MarkAbilityUsed(target, hit.abilityId)
	end

	hitEffect:FireAllClients(target, hit.abilityId, root.Position)
	return true
end

-- Can this ability be used on this target right now (combo-extension rules)?
function CombatService.CanAbilityHit(target: Model, abilityId: string): boolean
	return not StateService.AbilityUsedInCombo(target, abilityId)
end

-- ===== M1 string =====

local function onM1(player: Player, aim: Vector3, finisherInput: string)
	local character = player.Character
	local root = rootOf(character)
	print("[M1 server] got from", player.Name, "state:", character and StateService.GetState(character)) -- DEBUG
	if not character or not root or not StateService.Can(character, "M1") then
		print("[M1 server] blocked: can't M1 in this state") -- DEBUG
		return
	end

	local cfg = Combat.M1
	local t = workspace:GetServerTimeNow()
	local chain = chains[player]
	if not chain then
		chain = { index = 0, lastAt = 0, nextAllowedAt = 0 }
		chains[player] = chain
	end
	if t < chain.nextAllowedAt then
		return
	end
	if t - chain.lastAt > cfg.ChainResetSeconds or chain.index >= cfg.ChainLength then
		chain.index = 0
	end
	chain.index += 1
	chain.lastAt = t
	chain.nextAllowedAt = t + cfg.MinInterval

	local index = chain.index
	local isFinisher = index == cfg.ChainLength
	if isFinisher then
		StateService.Set(character, "EndLag", cfg.EndLagSeconds) -- abilities + dash still allowed
	else
		StateService.Set(character, "Attacking", cfg.ChainResetSeconds)
	end

	task.delay(cfg.Hitbox.HitFrame, function()
		-- Got hit during wind-up (trade lost) → swing cancelled.
		local state = StateService.GetState(character)
		if state ~= "Attacking" and state ~= "EndLag" then
			return
		end
		local currentRoot = rootOf(character)
		if not currentRoot then
			return
		end
		local targets = HitboxService.InFront(character, currentRoot, aim, cfg.Hitbox.Offset + cfg.Hitbox.Size.Z / 2, cfg.Hitbox.Size.X, 4)
		-- Closest valid target only.
		local best: Model? = nil
		local bestDist = math.huge
		for _, h in targets do
			local m = h.Parent
			local r = if m and m:IsA("Model") then rootOf(m) else nil
			if m and m:IsA("Model") and r then
				local d = (r.Position - currentRoot.Position).Magnitude
				if d < bestDist then
					best, bestDist = m, d
				end
			end
		end

		print("[M1 server] hit", index, "targets in box:", #targets, "best:", best and best.Name) -- DEBUG
		if not best then
			chain.nextAllowedAt += cfg.WhiffRecovery -- whiff punish
			return
		end

		if isFinisher then
			local f = Combat.Finishers[FINISHER_BY_INPUT[finisherInput] or "Knockback"]
			CombatService.ApplyHit(player, best, {
				damage = f.Damage,
				ragdoll = f.Ragdoll,
				stun = if f.Ragdoll > 0 then nil else 0.8, -- Uppercut: air hitstun until the air combo exists
				launch = f.Launch,
				abilityId = "M1_4",
			})
		else
			local landed = CombatService.ApplyHit(player, best, {
				damage = cfg.Damage[index],
				stun = cfg.Hitstun,
				abilityId = `M1_{index}`,
			})
			if landed and character.Parent then
				-- Small step forward so the string doesn't drift out of range.
				push(character, currentRoot, currentRoot.CFrame.LookVector * (cfg.ForwardStep / 0.18))
			end
		end
	end)
end

-- Called once at startup, before any Start(). Create state, read config. Don't yield.
function CombatService.Init()
	hitEffect = Remotes.Event("HitEffect")
	knockbackRemote = Remotes.Event("Knockback")
end

local function setUpDummy(model: Instance)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	-- Tagged dummies kept in storage (outside Workspace) aren't in the world yet.
	if not humanoid or not model:IsA("Model") or not model:IsDescendantOf(workspace) then
		return
	end
	humanoid.BreakJointsOnDeath = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		-- The server moves dummies (knockback), so the server must own their physics.
		root:SetNetworkOwner(nil)
	end
	local lastHit = 0
	humanoid.HealthChanged:Connect(function(health)
		if health >= humanoid.MaxHealth then
			return
		end
		local hitAt = os.clock()
		lastHit = hitAt
		if health <= 0 then
			humanoid.Health = 1 -- dummies never die
		end
		task.delay(DUMMY_HEAL_SECONDS, function()
			if lastHit == hitAt then
				humanoid.Health = humanoid.MaxHealth
			end
		end)
	end)
end

-- Called once after every Init(). Connect events, start loops.
function CombatService.Start()
	for _, model in CollectionService:GetTagged("TrainingDummy") do
		setUpDummy(model)
	end
	CollectionService:GetInstanceAddedSignal("TrainingDummy"):Connect(setUpDummy)

	local FINISHER_INPUTS = { None = true, Space = true, S = true }
	RemoteGuard.Event("M1Attack", { PerSecond = 5, Burst = 5 }, function(aim, finisherInput)
		return typeof(aim) == "Vector3"
			and RemoteGuard.IsFiniteNumber(aim.X)
			and RemoteGuard.IsFiniteNumber(aim.Y)
			and RemoteGuard.IsFiniteNumber(aim.Z)
			and RemoteGuard.IsOneOf(finisherInput, FINISHER_INPUTS)
	end, onM1)

	Players.PlayerRemoving:Connect(function(player)
		chains[player] = nil
	end)
end

return CombatService

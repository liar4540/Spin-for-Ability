--!strict
-- CombatService: battlegrounds combat. The ONE damage path for M1s and abilities.
-- Vault: 12 Combat System. Build order done: 1 (states), 2 (M1 string), 3 (ApplyHit), finishers (Knockback / Ground Smash / Downslam in the air).
-- Not yet: block/guard meter, real ragdoll physics, dash, ragdoll cancel.
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
	launchSeconds: number?, -- how long the launch pushes (default 0.18)
	hang: number?, -- seconds the target hangs in the air afterwards (air combo), falling at Air.FallSpeed
	guardBreak: boolean?, -- ignores block (block not built yet)
	abilityId: string, -- "M1_1".."M1_4", "M1_Air1".., "M1_Downslam" for M1s
}

local CombatService = {}

local hitEffect: RemoteEvent
local knockbackRemote: RemoteEvent

-- Per-attacker M1 string.
type Chain = { index: number, lastAt: number, nextAllowedAt: number }
local chains: { [Player]: Chain } = {}

local FINISHER_BY_INPUT: { [string]: string } = { None = "Knockback", Air = "Downslam", S = "GroundSmash" }

local function rootOf(model: Model?): BasePart?
	return model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Moves a character where its physics is owned. seconds/hangSeconds are optional (see Knockback.Apply).
local function push(model: Model, root: BasePart, velocity: Vector3, seconds: number?, hangSeconds: number?)
	local victim = Players:GetPlayerFromCharacter(model)
	if victim then
		-- A player's character is moved by their own client (it owns the physics).
		knockbackRemote:FireClient(victim, velocity, seconds, hangSeconds)
	else
		local hover = if hangSeconds then { Seconds = hangSeconds, FallSpeed = Combat.HangFallSpeed } else nil
		Knockback.Apply(root, velocity, seconds, hover)
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

	-- Reaction animation every client plays on the target (ReactionController): "Stun" = dazed + a flinch
	-- per hit, "Air" = launched (face up, limbs dangling), "Down" = lying on the ground.
	local reaction: string? = nil
	if hit.ragdoll and hit.ragdoll > 0 then
		StateService.Set(target, "Ragdolled", hit.ragdoll)
		reaction = "Down"
	elseif hit.stun and hit.stun > 0 and not StateService.IsStunImmune(target) then
		StateService.Set(target, "Stunned", hit.stun)
		reaction = if hit.hang or (hit.launch and hit.launch.Y > 0) then "Air" else "Stun"
	end
	if reaction then
		target:SetAttribute("Reaction", reaction)
		-- Counter, so every hit fires the attribute signal even when the reaction is the same.
		target:SetAttribute("ReactionHit", ((target:GetAttribute("ReactionHit") :: number?) or 0) + 1)
	end

	if hit.launch and hit.launch.Magnitude > 0 then
		local attackerRoot = rootOf(attacker.Character)
		local facing = if attackerRoot then attackerRoot.CFrame else root.CFrame
		local flatLook = Vector3.new(facing.LookVector.X, 0, facing.LookVector.Z)
		local basis = if flatLook.Magnitude > 0.01 then CFrame.lookAt(Vector3.zero, flatLook) else CFrame.identity
		push(target, root, basis:VectorToWorldSpace(hit.launch), hit.launchSeconds, hit.hang)
	elseif hit.hang then
		push(target, root, Vector3.zero, 0, hit.hang) -- keep it hanging where it is
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
-- Hits 1–3, then hit 4 = finisher: in the air (jumped) → Downslam, S held → Ground Smash,
-- otherwise Knockback. So the Downslam is M1 ×3, jump, M1.

type Box = { Size: Vector3, Offset: number, Down: number? }

-- The closest living fighter in the box in front of the attacker, or nil (whiff).
local function closestTarget(character: Model, root: BasePart, aim: Vector3, box: Box): Model?
	local targets =
		HitboxService.InFront(character, root, aim, box.Offset + box.Size.Z / 2, box.Size.X, 4, box.Size.Y, box.Down)
	local best: Model? = nil
	local bestDist = math.huge
	for _, h in targets do
		local m = h.Parent
		local r = if m and m:IsA("Model") then rootOf(m) else nil
		if m and m:IsA("Model") and r then
			local d = (r.Position - root.Position).Magnitude
			if d < bestDist then
				best, bestDist = m, d
			end
		end
	end
	return best
end

-- Is the attacker really in the air? Height of the root above the ground under it (fighters ignored,
-- so a dummy underneath doesn't count as ground) vs. its normal standing height.
local function isAirborne(character: Model, root: BasePart): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.CollisionGroup = "Fighters"
	local result = workspace:Raycast(root.Position, Vector3.new(0, -50, 0), params)
	local height = if result then root.Position.Y - result.Position.Y else math.huge
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local standing = (if humanoid then humanoid.HipHeight else 2) + root.Size.Y / 2
	return height >= standing + Combat.Downslam.MinHeight
end

local function newChain(): Chain
	return { index = 0, lastAt = 0, nextAllowedAt = 0 }
end

local function onM1(player: Player, aim: Vector3, finisherInput: string)
	local character = player.Character
	if not character or not rootOf(character) or not StateService.Can(character, "M1") then
		return
	end
	local cfg = Combat.M1
	local t = workspace:GetServerTimeNow()
	local chain = chains[player]
	if not chain then
		chain = newChain()
		chains[player] = chain
	end
	if t < chain.nextAllowedAt then
		return
	end
	local dropped = t - chain.lastAt > cfg.ChainResetSeconds
	if dropped and chain.index > 0 and chain.index < cfg.ChainLength and t - chain.lastAt < cfg.RestartDelay then
		return -- string dropped before hit 4: wait before starting again (stops M1, pause, M1 stun-locks)
	end
	if dropped or chain.index >= cfg.ChainLength then
		chain.index = 0
	end
	chain.index += 1
	chain.lastAt = t
	chain.nextAllowedAt = t + cfg.MinInterval

	local index = chain.index
	local isFinisher = index == cfg.ChainLength
	local finisher = if isFinisher then (FINISHER_BY_INPUT[finisherInput] or "Knockback") else nil
	if isFinisher then
		StateService.Set(character, "EndLag", cfg.EndLagSeconds) -- abilities + dash still allowed
	else
		StateService.Set(character, "Attacking", cfg.ChainResetSeconds)
	end
	local hitFrame = if finisher == "Downslam" then Combat.Downslam.HitFrame else cfg.Hitbox.HitFrame

	task.delay(hitFrame, function()
		-- Got hit during wind-up (trade lost) → swing cancelled.
		local state = StateService.GetState(character)
		if state ~= "Attacking" and state ~= "EndLag" then
			return
		end
		local root = rootOf(character)
		if not root then
			return
		end

		if finisher == "Downslam" and not isAirborne(character, root) then
			finisher = "Knockback" -- the client said "in the air", but the server sees it standing
		end
		local box: Box = if finisher == "Downslam" then Combat.Downslam.Hitbox else cfg.Hitbox
		local target = closestTarget(character, root, aim, box)

		if finisher == "Downslam" then
			-- Drop back to the ground after the hammer, hit or miss.
			local d = Combat.Downslam
			StateService.Set(character, "EndLag", d.EndLag)
			push(character, root, Vector3.new(0, -d.DropVelocity, 0), d.DropSeconds)
		end
		if not target then
			chain.nextAllowedAt += cfg.WhiffRecovery -- whiff punish
			return
		end

		if not finisher then
			-- The forward step is done by the attacker's own client at the swing (smoother than a server push).
			CombatService.ApplyHit(player, target, { damage = cfg.Damage[index], stun = cfg.Hitstun, abilityId = `M1_{index}` })
			return
		end
		local f = Combat.Finishers[finisher]
		CombatService.ApplyHit(player, target, {
			damage = f.Damage,
			ragdoll = f.Ragdoll,
			stun = if f.Ragdoll > 0 then nil else 0.8,
			launch = f.Launch,
			abilityId = if finisher == "Downslam" then "M1_Downslam" else "M1_4",
		})
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

	local FINISHER_INPUTS = { None = true, Air = true, S = true }
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

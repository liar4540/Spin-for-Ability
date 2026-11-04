--!strict
-- CombatService: battlegrounds combat: M1 combo, block/guard break, dash, fighter states, hitstun, ragdoll, the one damage path, KOs + kill credit.
-- Status: Milestone 1 start. Only the damage path (damage + knockback + hit effect) is in,
-- so abilities can use it. M1, block, dash, states and KOs come next (vault: 07 Tech Plan, 08 Roadmap).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Knockback = require(Shared:WaitForChild("Knockback"))

-- Training dummies (tag "TrainingDummy", made in Studio) heal back to full this long after a hit.
local DUMMY_HEAL_SECONDS = 2

local CombatService = {}

local hitEffect: RemoteEvent
local knockbackRemote: RemoteEvent

-- The ONE place damage is dealt. attacker is the player who caused it (for kill credit later).
-- knockback is a velocity (studs/second); zero vector = none.
function CombatService.DealDamage(_attacker: Player, target: Humanoid, amount: number, knockback: Vector3, abilityId: string)
	if target.Health <= 0 then
		return
	end
	target:TakeDamage(amount)

	local model = target.Parent
	local root = model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	if knockback.Magnitude > 0 then
		local victim = Players:GetPlayerFromCharacter(model)
		if victim then
			-- A player's character is moved by their own client (it owns the physics).
			knockbackRemote:FireClient(victim, knockback)
		else
			Knockback.Apply(root, knockback)
		end
	end

	hitEffect:FireAllClients(model, abilityId, root.Position)
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
end

return CombatService

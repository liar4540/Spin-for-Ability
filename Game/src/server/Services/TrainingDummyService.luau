--!strict
-- TrainingDummyService: spawns test dummies when you press Play in Studio (not in live games).
-- Each dummy is a normal R15 rig tagged "TrainingDummy", so CombatService (never dies, heals)
-- and StateService (combat state + debug label) pick it up automatically.
--
-- Besides the three plain punching bags there are two that fight back, using the real combat system
-- (CombatService.NpcM1 / NpcBlock: same M1 string, block, guard, perfect block window, stun):
--   Attacker dummy (red)  stands still, faces you and throws M1 strings when you step in reach: test your block on it.
--   Blocker dummy (blue)  never stops blocking and keeps facing the nearest player: test skills against block.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Services = script.Parent
local CombatService = require(Services:WaitForChild("CombatService"))
local StateService = require(Services:WaitForChild("StateService"))

local STUDIO_ONLY = true
local DUMMY_COUNT = 3
local DISTANCE_FROM_SPAWN = 12 -- studs in front of the spawn
local SPACING = 8 -- studs between dummies

local AGGRO_RANGE = 45 -- the attacker dummy notices a player this close
local ATTACK_RANGE = 6.5 -- ...and swings from this close (the M1 box reaches about 7 studs)
local THINK_SECONDS = 0.12

type Special = { Name: string, Label: string, Behavior: string, Color: Color3, Sideways: number }
local SPECIAL: { Special } = {
	{ Name = "AttackerDummy", Label = "Attacker", Behavior = "Attacker", Color = Color3.fromRGB(205, 70, 70), Sideways = -28 },
	{ Name = "BlockerDummy", Label = "Blocker", Behavior = "Blocker", Color = Color3.fromRGB(70, 120, 225), Sideways = 28 },
}

local TrainingDummyService = {}

local function spawnOrigin(): CFrame
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawn then
		return (spawn :: SpawnLocation).CFrame + Vector3.new(0, 3, 0)
	end
	return CFrame.new(0, 5, 0)
end

local function makeDummy(name: string, cframe: CFrame, label: string?, color: Color3?): Model
	local description = Instance.new("HumanoidDescription")
	if color then
		description.HeadColor = color
		description.TorsoColor = color
		description.LeftArmColor = color
		description.RightArmColor = color
		description.LeftLegColor = color
		description.RightLegColor = color
	end
	local model = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	model.Name = name
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		if label then
			humanoid.DisplayName = label
		end
		humanoid.MaxHealth = 100
		humanoid.Health = 100
	end
	model:PivotTo(cframe)
	model.Parent = workspace
	-- Tag AFTER parenting: the dummy setup only accepts dummies already in Workspace.
	CollectionService:AddTag(model, "TrainingDummy")
	return model
end

-- ===== Behaviours =====

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.zero
end

-- The closest living player character within `range` studs (flat distance), its root, and the distance.
local function nearestPlayer(from: Vector3, range: number): (Model?, BasePart?, number)
	local best: Model? = nil
	local bestRoot: BasePart? = nil
	local bestDistance = range
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if character and root and humanoid and humanoid.Health > 0 then
			local distance = ((root.Position - from) * Vector3.new(1, 0, 1)).Magnitude
			if distance <= bestDistance then
				best, bestRoot, bestDistance = character, root, distance
			end
		end
	end
	return best, bestRoot, bestDistance
end

local function faceTowards(root: BasePart, direction: Vector3)
	if direction ~= Vector3.zero then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + direction)
	end
end

local function isFree(model: Model): boolean
	local state = StateService.GetState(model)
	return state == "Idle" or state == "Attacking" or state == "EndLag" or state == "Blocking"
end

-- Chases the nearest player and throws M1 strings at them.
local function runAttacker(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:WaitForChild("HumanoidRootPart") :: BasePart
	humanoid.AutoRotate = false
	while model.Parent and humanoid.Health > 0 do
		task.wait(THINK_SECONDS)
		local target, targetRoot, distance = nearestPlayer(root.Position, AGGRO_RANGE)
		if not target or not targetRoot or not isFree(model) then
			continue
		end
		-- Stands still: never walks. It turns to face you and swings when you come within reach.
		if distance <= ATTACK_RANGE then
			local toward = flat(targetRoot.Position - root.Position)
			if StateService.GetState(model) == "Idle" then
				faceTowards(root, toward)
			end
			CombatService.NpcM1(model, toward)
		end
	end
end

-- Holds a block all the time, facing the nearest player so the front cone covers them; raises it
-- again as soon as a guard break wears off.
local function runBlocker(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:WaitForChild("HumanoidRootPart") :: BasePart
	humanoid.AutoRotate = false
	while model.Parent and humanoid.Health > 0 do
		task.wait(THINK_SECONDS)
		local state = StateService.GetState(model)
		local target, targetRoot = nearestPlayer(root.Position, 200)
		if target and targetRoot and (state == "Idle" or state == "Blocking") then
			faceTowards(root, flat(targetRoot.Position - root.Position))
		end
		if state == "Idle" then
			CombatService.NpcBlock(model, true)
		end
	end
end

function TrainingDummyService.Init() end

function TrainingDummyService.Start()
	if STUDIO_ONLY and not RunService:IsStudio() then
		return
	end
	local origin = spawnOrigin()
	local function facingSpawn(sideways: number): CFrame
		local position = origin * CFrame.new(sideways, 0, -DISTANCE_FROM_SPAWN)
		-- Face the spawn so you hit them from the front.
		return CFrame.lookAt(position.Position, Vector3.new(origin.X, position.Y, origin.Z))
	end
	for i = 1, DUMMY_COUNT do
		makeDummy(`Dummy{i}`, facingSpawn((i - (DUMMY_COUNT + 1) / 2) * SPACING))
	end
	for _, special in SPECIAL do
		local model = makeDummy(special.Name, facingSpawn(special.Sideways), special.Label, special.Color)
		model:SetAttribute("DummyBehavior", special.Behavior)
		-- Wait a moment: the fighter is registered when the dummy is tagged.
		task.spawn(function()
			task.wait(1)
			if special.Behavior == "Attacker" then
				runAttacker(model)
			else
				runBlocker(model)
			end
		end)
	end
end

return TrainingDummyService

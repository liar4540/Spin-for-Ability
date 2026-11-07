--!strict
-- TrainingDummyService: spawns test dummies when you press Play in Studio (not in live games).
-- Each dummy is a normal R15 rig tagged "TrainingDummy", so CombatService (never dies, heals)
-- and StateService (combat state + debug label) pick it up automatically.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local STUDIO_ONLY = true
local DUMMY_COUNT = 3
local DISTANCE_FROM_SPAWN = 12 -- studs in front of the spawn
local SPACING = 8 -- studs between dummies

local TrainingDummyService = {}

local function spawnOrigin(): CFrame
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawn then
		return (spawn :: SpawnLocation).CFrame + Vector3.new(0, 3, 0)
	end
	return CFrame.new(0, 5, 0)
end

local function makeDummy(name: string, cframe: CFrame)
	local description = Instance.new("HumanoidDescription")
	local model = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	model.Name = name
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		humanoid.MaxHealth = 100
		humanoid.Health = 100
	end
	model:PivotTo(cframe)
	model.Parent = workspace
	-- Tag AFTER parenting: the dummy setup only accepts dummies already in Workspace.
	CollectionService:AddTag(model, "TrainingDummy")
end

function TrainingDummyService.Init() end

function TrainingDummyService.Start()
	if STUDIO_ONLY and not RunService:IsStudio() then
		return
	end
	local origin = spawnOrigin()
	for i = 1, DUMMY_COUNT do
		local sideways = (i - (DUMMY_COUNT + 1) / 2) * SPACING
		local position = origin * CFrame.new(sideways, 0, -DISTANCE_FROM_SPAWN)
		-- Face the spawn so you hit them from the front.
		local facing = CFrame.lookAt(position.Position, Vector3.new(origin.X, position.Y, origin.Z))
		makeDummy(`Dummy{i}`, facing)
	end
end

return TrainingDummyService

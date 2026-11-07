--!strict
-- Server main script: creates the remotes, then starts every service in order.
-- Everything else on the server is a ModuleScript (no _G).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local Services = script:WaitForChild("Services")

-- Run the Odds tests when you press Play in Studio. Set to false if they get in the way.
local RUN_TESTS_IN_STUDIO = true

type Service = {
	Init: () -> (),
	Start: () -> (),
}

-- Order matters: data first, so everything else can read player data.
local ORDER = {
	"DataService",
	"PolicyService",
	"RemoteGuard",
	"VFXTemplateService",
	"HitboxService",
	"StateService",
	"CombatService",
	"TrainingDummyService",
	"AbilityService",
	"EconomyService",
	"PotionService",
	"RewardService",
	"MonetizationService",
}

Remotes.Create()

local loaded: { Service } = {}
for _, name in ORDER do
	local service = require(Services:WaitForChild(name)) :: Service
	service.Init()
	table.insert(loaded, service)
end
for _, service in loaded do
	service.Start()
end

if RUN_TESTS_IN_STUDIO and RunService:IsStudio() then
	task.spawn(function()
		local OddsTest = require(script:WaitForChild("Tests"):WaitForChild("OddsTest"))
		OddsTest.Run()
	end)
end

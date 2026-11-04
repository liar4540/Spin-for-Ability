--!strict
-- ZoneService: which spin machine a player is standing at (more zones later:
-- safe zone / Battlegrounds arena, spawn shield).
--
-- Spin machines: tag a Part or Model "SpinMachine" (CollectionService / Tag Editor)
-- and give it a string attribute AreaId matching Config/Areas (e.g. "Starter", "Area1", "VIP").
-- The SERVER measures the distance; the client never says where it is.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Areas = require(Shared:WaitForChild("Config"):WaitForChild("Areas"))

type AreaDef = Areas.AreaDef

local MACHINE_TAG = "SpinMachine"
local MACHINE_RANGE = 14 -- studs from the machine's centre

local ZoneService = {}

local areasById: { [string]: AreaDef } = {}
local warnedNoMachines = false

local function machinePosition(machine: Instance): Vector3?
	if machine:IsA("BasePart") then
		return machine.Position
	elseif machine:IsA("Model") then
		return machine:GetPivot().Position
	end
	return nil
end

-- The area of the spin machine the player is standing at, or nil.
-- Does NOT check if the area is unlocked; SpinService does that.
function ZoneService.GetSpinMachineArea(player: Player): AreaDef?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end

	local machines = CollectionService:GetTagged(MACHINE_TAG)
	if #machines == 0 and RunService:IsStudio() then
		-- Studio only: no machines built yet, so spinning works anywhere as the Starter area.
		if not warnedNoMachines then
			warnedNoMachines = true
			warn(`[ZoneService] No "{MACHINE_TAG}" parts found; Studio test mode: spinning works anywhere.`)
		end
		return areasById.Starter
	end

	local best: AreaDef? = nil
	local bestDistance = MACHINE_RANGE
	for _, machine in machines do
		local position = machinePosition(machine)
		local areaId = machine:GetAttribute("AreaId")
		if position and type(areaId) == "string" and areasById[areaId] then
			local distance = (position - root.Position).Magnitude
			if distance <= bestDistance then
				best = areasById[areaId]
				bestDistance = distance
			end
		end
	end
	return best
end

function ZoneService.Init()
	for _, area in Areas do
		areasById[area.Id] = area
	end
end

function ZoneService.Start() end

return ZoneService

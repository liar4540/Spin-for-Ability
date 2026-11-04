--!strict
-- VFXTestController: chat commands for looking at ability VFX up close. Studio and the game's
-- creator only; everything it makes exists on this client alone (no server, no damage).
--
--   /vfxtest pebble   loop Pebble Toss at 0.25x speed: a copy of your character stands
--                     in front of the nearest training dummy and throws at it, over and over
--   /vfxtest off      stop (typing the same test again also stops it)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Client = script.Parent.Parent
local PebbleTossVFX = require(Client:WaitForChild("Abilities"):WaitForChild("PebbleTossVFX"))

local TIME_SCALE = 0.25
local LOOP_SECONDS = 2.4 -- one throw + its impact at normal speed; divided by TIME_SCALE
local DISTANCE = 16 -- studs between the thrower and the dummy
local DUMMY_TAG = "TrainingDummy"

type Test = (rig: Model, aim: Vector3) -> ()

local TESTS: { [string]: Test } = {
	pebble = function(rig, aim)
		PebbleTossVFX.Play(rig, aim, false, { TimeScale = TIME_SCALE, LocalHits = true, PlayAnimation = true })
	end,
}

local VFXTestController = {}

local running: { Name: string, Rig: Model }? = nil

local function nearestDummy(from: Vector3): Model?
	local best: Model? = nil
	local bestDistance = math.huge
	for _, dummy in CollectionService:GetTagged(DUMMY_TAG) do
		if dummy:IsA("Model") and dummy:IsDescendantOf(workspace) then
			local distance = (dummy:GetPivot().Position - from).Magnitude
			if distance < bestDistance then
				best, bestDistance = dummy, distance
			end
		end
	end
	return best
end

-- A copy of our character, standing still (anchored root) DISTANCE studs in front of the dummy.
local function makeRig(character: Model, dummy: Model): Model?
	local wasArchivable = character.Archivable
	character.Archivable = true
	local rig = character:Clone()
	character.Archivable = wasArchivable
	if not rig then
		return nil
	end
	rig.Name = "VFXTest"
	for _, item in rig:GetDescendants() do
		if item:IsA("BaseScript") or item:IsA("ForceField") then
			item:Destroy()
		end
	end
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		rig:Destroy()
		return nil
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	root.Anchored = true

	local target = dummy:GetPivot()
	local front = Vector3.new(target.LookVector.X, 0, target.LookVector.Z).Unit
	local spot = target.Position + front * DISTANCE
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, dummy, rig }
	local ground = workspace:Raycast(Vector3.new(spot.X, target.Position.Y + 10, spot.Z), Vector3.new(0, -60, 0), params)
	local groundY = if ground then ground.Position.Y else target.Position.Y - dummy:GetExtentsSize().Y / 2
	local height = groundY + humanoid.HipHeight + root.Size.Y / 2
	local standAt = Vector3.new(spot.X, height, spot.Z)
	local lookAt = Vector3.new(target.Position.X, height, target.Position.Z)
	rig:PivotTo(CFrame.lookAt(standAt, lookAt))
	rig.Parent = workspace
	return rig
end

local function stop()
	if running then
		running.Rig:Destroy()
		running = nil
	end
end

local function start(name: string)
	local test = TESTS[name]
	local character = Players.LocalPlayer.Character
	if not test or not character then
		return
	end
	stop()
	local dummy = nearestDummy(character:GetPivot().Position)
	if not dummy then
		warn(`[VFXTest] no "{DUMMY_TAG}" dummy in the world`)
		return
	end
	local rig = makeRig(character, dummy)
	if not rig then
		return
	end
	local this = { Name = name, Rig = rig }
	running = this
	task.spawn(function()
		while running == this and rig.Parent do
			local aim = dummy:GetPivot().Position - rig:GetPivot().Position
			test(rig, Vector3.new(aim.X, 0, aim.Z).Unit)
			task.wait(LOOP_SECONDS / TIME_SCALE)
		end
	end)
end

local function allowed(): boolean
	return RunService:IsStudio() or (game.CreatorType == Enum.CreatorType.User and Players.LocalPlayer.UserId == game.CreatorId)
end

function VFXTestController.Init() end

function VFXTestController.Start()
	if not allowed() then
		return
	end
	local command = Instance.new("TextChatCommand")
	command.Name = "VFXTestCommand"
	command.PrimaryAlias = "/vfxtest"
	command.Triggered:Connect(function(_source, text)
		local arg = string.lower(string.match(text, "^%S+%s+(%S+)") or "")
		if arg == "off" or arg == "stop" or (running and running.Name == arg) then
			stop()
		elseif TESTS[arg] then
			start(arg)
		end
	end)
	command.Parent = TextChatService
end

return VFXTestController

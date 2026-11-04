--!strict
-- VFXTestController: chat commands for looking at ability VFX up close. Studio and the game's
-- creator only; everything it makes exists on this client alone (no server, no damage).
--
--   /vfxtest pebble   loop Pebble Toss at 0.25x speed: a copy of your character stands
--                     in front of the nearest training dummy and throws at it, over and over
--   /vfxtest gale     loop Gale Step at 0.25x speed: a copy of your character dashes 30 studs
--                     across the nearest open area (next to you), then starts again where it began
--   /vfxtest off      stop (typing the same test again also stops it)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Client = script.Parent.Parent
local Abilities = Client:WaitForChild("Abilities")
local PebbleTossVFX = require(Abilities:WaitForChild("PebbleTossVFX"))
local GaleStepVFX = require(Abilities:WaitForChild("GaleStepVFX"))

local TIME_SCALE = 0.25
local DISTANCE = 16 -- studs between the thrower and the dummy
local DUMMY_TAG = "TrainingDummy"
local OPEN_STUDS = 36 -- an open area: this far clear in the dash direction
local OPEN_SIDE = 6 -- the dashing copy starts this far to your side

type Test = {
	Run: (rig: Model, aim: Vector3) -> (),
	LoopSeconds: number, -- one go at normal speed; divided by TIME_SCALE
	OpenArea: boolean?, -- true: needs room to move, not a dummy
}

local TESTS: { [string]: Test } = {
	pebble = {
		Run = function(rig, aim)
			PebbleTossVFX.Play(rig, aim, false, { TimeScale = TIME_SCALE, LocalHits = true, PlayAnimation = true })
		end,
		LoopSeconds = 2.4, -- one throw + its impact
	},
	gale = {
		Run = function(rig, aim)
			GaleStepVFX.Play(rig, aim, false, { TimeScale = TIME_SCALE, PlayAnimation = true, Move = true })
		end,
		LoopSeconds = 1.6, -- the 1.2 s skill + a short pause
		OpenArea = true,
	},
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

-- A copy of our character with an anchored root (not yet in the world).
local function copyCharacter(character: Model): Model?
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
	return rig
end

-- Stand the rig on the ground at `spot` (X/Z), looking toward `toward`.
local function stand(rig: Model, spot: Vector3, toward: Vector3, ignore: { Instance }): boolean
	local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local ground = workspace:Raycast(spot + Vector3.new(0, 10, 0), Vector3.new(0, -60, 0), params)
	if not ground then
		return false
	end
	local height = ground.Position.Y + humanoid.HipHeight + root.Size.Y / 2
	local standAt = Vector3.new(spot.X, height, spot.Z)
	rig:PivotTo(CFrame.lookAt(standAt, Vector3.new(toward.X, height, toward.Z)))
	return true
end

-- A copy of our character, standing still DISTANCE studs in front of the dummy.
local function rigAtDummy(character: Model, dummy: Model): Model?
	local rig = copyCharacter(character)
	if not rig then
		return nil
	end
	local target = dummy:GetPivot()
	local front = Vector3.new(target.LookVector.X, 0, target.LookVector.Z).Unit
	if not stand(rig, target.Position + front * DISTANCE, target.Position, { character, dummy, rig }) then
		rig:PivotTo(CFrame.lookAt(target.Position + front * DISTANCE, target.Position))
	end
	rig.Parent = workspace
	return rig
end

-- A copy of our character OPEN_SIDE studs to our side, facing the most open direction near where
-- the camera looks (OPEN_STUDS clear of walls, ground all the way).
local function rigInOpenArea(character: Model): Model?
	local rig = copyCharacter(character)
	if not rig then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, rig }
	local camera = workspace.CurrentCamera
	local look = if camera then camera.CFrame.LookVector else character:GetPivot().LookVector
	local first = math.atan2(-look.X, -look.Z)
	local origin = character:GetPivot().Position
	for i = 0, 15 do
		-- try straight ahead first, then alternate left/right in 22.5 deg steps
		local turn = math.ceil(i / 2) * (if i % 2 == 0 then 1 else -1) * math.pi / 8
		local dir = CFrame.fromAxisAngle(Vector3.yAxis, first + turn).LookVector
		local start = origin + dir:Cross(Vector3.yAxis) * OPEN_SIDE
		local clear = not workspace:Spherecast(start, 2, dir * OPEN_STUDS, params)
		local floor = workspace:Raycast(start + dir * OPEN_STUDS, Vector3.new(0, -12, 0), params)
		if clear and floor and stand(rig, start, start + dir, { character, rig }) then
			rig.Parent = workspace
			return rig
		end
	end
	warn("[VFXTest] no open area nearby; dashing straight ahead anyway")
	stand(rig, origin + look:Cross(Vector3.yAxis) * OPEN_SIDE, origin + look * 10, { character, rig })
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
	local rig: Model?
	local aimAt: () -> Vector3
	if test.OpenArea then
		rig = rigInOpenArea(character)
		local home = rig and rig:GetPivot()
		aimAt = function()
			-- back to where it started, then the same direction every time
			local h = home :: CFrame
			(rig :: Model):PivotTo(h)
			return h.LookVector
		end
	else
		local dummy = nearestDummy(character:GetPivot().Position)
		if not dummy then
			warn(`[VFXTest] no "{DUMMY_TAG}" dummy in the world`)
			return
		end
		rig = rigAtDummy(character, dummy)
		aimAt = function()
			local aim = dummy:GetPivot().Position - (rig :: Model):GetPivot().Position
			return Vector3.new(aim.X, 0, aim.Z).Unit
		end
	end
	if not rig then
		return
	end
	local copy: Model = rig
	local this = { Name = name, Rig = copy }
	running = this
	task.spawn(function()
		while running == this and copy.Parent do
			test.Run(copy, aimAt())
			task.wait(test.LoopSeconds / TIME_SCALE)
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

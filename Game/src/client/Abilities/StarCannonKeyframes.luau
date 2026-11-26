--!strict
-- Star Cannon: plant -> cup both hands at the right hip and gather -> thrust both palms forward ->
-- hold the firing stance (a slight strain tremor) -> lower the arms. Written by hand (2026-11-26): the
-- generated clip barely moved the hands to the side, thrust at 1.8 s and spread the hands 4 studs apart
-- while firing. Pose format: client/Abilities/Pose (degrees in the parent part's space: +X pitch swings
-- a limb forward, +Y yaw turns left, +Z roll swings a limb toward the body's right). Hand positions are
-- checked with forward kinematics. Markers: "Fire" (1.5 s, the release = the server's WindupSeconds).

local Pose = require(script.Parent.Pose)

local STANCE = {
	RightHip = { Rot = Vector3.new(-12, 0, 18) },
	RightKnee = { Rot = Vector3.new(-30, 0, 0) },
	LeftHip = { Rot = Vector3.new(30, 0, -18) },
	LeftKnee = { Rot = Vector3.new(-40, 0, 0) },
}

local function with(base: { [string]: Pose.JointPose }, extra: { [string]: Pose.JointPose }): { [string]: Pose.JointPose }
	local out = table.clone(base)
	for k, v in extra do
		out[k] = v
	end
	return out
end

-- charging: hands cupped together at the right hip, torso turned right
local function gather(depth: number, tremor: number): { [string]: Pose.JointPose }
	return with(STANCE, {
		Root = { Pos = Vector3.new(0, -0.6 - depth, 0), Rot = Vector3.new(0, -30 - tremor, 0) },
		Waist = { Rot = Vector3.new(-6, -20, 0) },
		RightShoulder = { Rot = Vector3.new(45, 0, -28) },
		RightElbow = { Rot = Vector3.new(55, 0, 0) },
		RightWrist = { Rot = Vector3.new(0, 0, 30) },
		LeftShoulder = { Rot = Vector3.new(15, 0, 78) },
		LeftElbow = { Rot = Vector3.new(55, 0, 0) },
		LeftWrist = { Rot = Vector3.new(0, 0, -30) },
	})
end

-- firing: both arms straight forward at chest height, palms out
local function fire(tremor: number): { [string]: Pose.JointPose }
	return with(STANCE, {
		Root = { Pos = Vector3.new(0, -0.65, 0), Rot = Vector3.new(0, 0, 0) },
		Waist = { Rot = Vector3.new(-4 + tremor, 3, 0) },
		RightShoulder = { Rot = Vector3.new(88 + tremor, 0, -35) }, -- angled in so the palms meet
		RightElbow = { Rot = Vector3.new(4, 0, 0) },
		RightWrist = { Rot = Vector3.new(-60, 0, 0) },
		LeftShoulder = { Rot = Vector3.new(88 - tremor, 0, 35) },
		LeftElbow = { Rot = Vector3.new(4, 0, 0) },
		LeftWrist = { Rot = Vector3.new(-60, 0, 0) },
	})
end

local OUT = { Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.Out }
local KEYFRAMES: { Pose.Keyframe } = {
	{ Time = 0, Pose = {} },
	{ Time = 0.35, Style = OUT.Style, Direction = OUT.Direction, Pose = gather(0, 0) },
	{ Time = 0.8, Style = Enum.EasingStyle.Sine, Direction = Enum.EasingDirection.InOut, Pose = gather(0.06, 3) },
	{ Time = 1.2, Style = Enum.EasingStyle.Sine, Direction = Enum.EasingDirection.InOut, Pose = gather(0.1, 1) },
	{ Time = 1.42, Style = Enum.EasingStyle.Sine, Direction = Enum.EasingDirection.InOut, Pose = gather(0.12, 5) }, -- drawn back, tense
	{ Time = 1.5, Style = OUT.Style, Direction = OUT.Direction, Markers = { "Fire" }, Pose = fire(0) }, -- THRUST
	{ Time = 1.8, Style = Enum.EasingStyle.Sine, Pose = fire(1.5) },
	{ Time = 2.1, Style = Enum.EasingStyle.Sine, Pose = fire(-1.5) },
	{ Time = 2.4, Style = Enum.EasingStyle.Sine, Pose = fire(1.5) },
	{ Time = 2.7, Style = Enum.EasingStyle.Sine, Pose = fire(-1.5) },
	{ Time = 3.0, Style = Enum.EasingStyle.Sine, Pose = fire(1.5) },
	{ Time = 3.5, Style = Enum.EasingStyle.Sine, Pose = fire(0) },
	{ Time = 3.9, Style = Enum.EasingStyle.Sine, Direction = Enum.EasingDirection.InOut, Pose = {} }, -- arms lowered
}

return KEYFRAMES

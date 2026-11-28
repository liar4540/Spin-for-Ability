--!strict
-- Sever: weave hand signs in front of the chest (1.1 s, the caster turns with the camera), hold the last
-- sign while the aim locks (0.25 s), then a wide right-arm sweep at 1.35 s (the release = the server's
-- WindupSeconds) and back to rest. Pose format: client/Abilities/Pose (degrees in the parent part's space:
-- +X pitch swings a limb forward, +Y yaw turns left, +Z roll swings a limb toward the body's right).
-- Marker: "Release" (1.35 s).

local Pose = require(script.Parent.Pose)

local STANCE = {
	RightHip = { Rot = Vector3.new(-8, 0, 12) },
	RightKnee = { Rot = Vector3.new(-18, 0, 0) },
	LeftHip = { Rot = Vector3.new(18, 0, -12) },
	LeftKnee = { Rot = Vector3.new(-24, 0, 0) },
}

local function with(base: { [string]: Pose.JointPose }, extra: { [string]: Pose.JointPose }): { [string]: Pose.JointPose }
	local out = table.clone(base)
	for k, v in extra do
		out[k] = v
	end
	return out
end

-- a hand sign: both hands meet in front of the chest; `twist` varies the sign so it reads as weaving
local function sign(twist: number, lift: number): { [string]: Pose.JointPose }
	return with(STANCE, {
		Root = { Pos = Vector3.new(0, -0.35, 0) },
		Waist = { Rot = Vector3.new(-4, twist * 0.3, 0) },
		Neck = { Rot = Vector3.new(-6, 0, 0) },
		RightShoulder = { Rot = Vector3.new(78 + lift, twist, -48) },
		RightElbow = { Rot = Vector3.new(78 - lift, 0, 0) },
		RightWrist = { Rot = Vector3.new(0, 0, 25 + twist) },
		LeftShoulder = { Rot = Vector3.new(78 - lift, twist, 48) },
		LeftElbow = { Rot = Vector3.new(78 + lift, 0, 0) },
		LeftWrist = { Rot = Vector3.new(0, 0, -25 + twist) },
	})
end

-- the sweep: right arm thrown out to the right at shoulder height, torso turned with it
local function sweep(follow: number): { [string]: Pose.JointPose }
	return with(STANCE, {
		Root = { Pos = Vector3.new(0, -0.45, 0), Rot = Vector3.new(0, -22 - follow, 0) },
		Waist = { Rot = Vector3.new(-6, -18 - follow, 0) },
		RightShoulder = { Rot = Vector3.new(88, 0, 70 + follow) },
		RightElbow = { Rot = Vector3.new(6, 0, 0) },
		RightWrist = { Rot = Vector3.new(0, 0, 10) },
		LeftShoulder = { Rot = Vector3.new(30, 0, 25) },
		LeftElbow = { Rot = Vector3.new(60, 0, 0) },
	})
end

-- wound up: right arm pulled across the body to the left before the sweep
local WIND = with(STANCE, {
	Root = { Pos = Vector3.new(0, -0.4, 0), Rot = Vector3.new(0, 25, 0) },
	Waist = { Rot = Vector3.new(-4, 18, 0) },
	RightShoulder = { Rot = Vector3.new(85, 0, -78) },
	RightElbow = { Rot = Vector3.new(40, 0, 0) },
	LeftShoulder = { Rot = Vector3.new(20, 0, 30) },
	LeftElbow = { Rot = Vector3.new(50, 0, 0) },
})

local SINE = Enum.EasingStyle.Sine
local IN_OUT = Enum.EasingDirection.InOut
local OUT = Enum.EasingDirection.Out
local KEYFRAMES: { Pose.Keyframe } = {
	{ Time = 0, Pose = {} },
	{ Time = 0.18, Style = Enum.EasingStyle.Quad, Direction = OUT, Pose = sign(0, 0) },
	{ Time = 0.38, Style = SINE, Direction = IN_OUT, Pose = sign(14, 12) },
	{ Time = 0.58, Style = SINE, Direction = IN_OUT, Pose = sign(-12, -8) },
	{ Time = 0.78, Style = SINE, Direction = IN_OUT, Pose = sign(10, 16) },
	{ Time = 0.98, Style = SINE, Direction = IN_OUT, Pose = sign(-8, 4) },
	{ Time = 1.1, Style = SINE, Direction = IN_OUT, Pose = sign(0, 10) }, -- the aim locks: last sign held
	{ Time = 1.27, Style = Enum.EasingStyle.Quad, Direction = OUT, Pose = WIND },
	{ Time = 1.35, Style = Enum.EasingStyle.Quart, Direction = OUT, Markers = { "Release" }, Pose = sweep(0) }, -- SWEEP
	{ Time = 1.6, Style = SINE, Direction = OUT, Pose = sweep(8) },
	{ Time = 1.95, Style = SINE, Direction = IN_OUT, Pose = {} },
}

return KEYFRAMES

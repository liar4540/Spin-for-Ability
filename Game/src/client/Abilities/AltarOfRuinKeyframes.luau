--!strict
-- Altar of Ruin: palms pressed together in front of the chest (a slow, heavy prayer), then both arms
-- spread wide and up as the altar is summoned at 1.5 s (the server's WindupSeconds), held a moment and
-- lowered. Pose format: client/Abilities/Pose. Marker: "Summon" (1.5 s).

local Pose = require(script.Parent.Pose)

local STANCE = {
	RightHip = { Rot = Vector3.new(-6, 0, 10) },
	LeftHip = { Rot = Vector3.new(6, 0, -10) },
}

local function with(base: { [string]: Pose.JointPose }, extra: { [string]: Pose.JointPose }): { [string]: Pose.JointPose }
	local out = table.clone(base)
	for k, v in extra do
		out[k] = v
	end
	return out
end

local function prayer(bow: number): { [string]: Pose.JointPose }
	return with(STANCE, {
		Waist = { Rot = Vector3.new(-bow, 0, 0) },
		Neck = { Rot = Vector3.new(-bow * 1.5, 0, 0) },
		RightShoulder = { Rot = Vector3.new(70, 0, -52) },
		RightElbow = { Rot = Vector3.new(100, 0, 0) },
		RightWrist = { Rot = Vector3.new(-20, 0, 20) },
		LeftShoulder = { Rot = Vector3.new(70, 0, 52) },
		LeftElbow = { Rot = Vector3.new(100, 0, 0) },
		LeftWrist = { Rot = Vector3.new(-20, 0, -20) },
	})
end

local function spread(open: number): { [string]: Pose.JointPose }
	return with(STANCE, {
		Waist = { Rot = Vector3.new(8, 0, 0) },
		Neck = { Rot = Vector3.new(12, 0, 0) },
		RightShoulder = { Rot = Vector3.new(120 + open, 0, 45 + open) },
		RightElbow = { Rot = Vector3.new(10, 0, 0) },
		RightWrist = { Rot = Vector3.new(-30, 0, 0) },
		LeftShoulder = { Rot = Vector3.new(120 + open, 0, -45 - open) },
		LeftElbow = { Rot = Vector3.new(10, 0, 0) },
		LeftWrist = { Rot = Vector3.new(-30, 0, 0) },
	})
end

local SINE = Enum.EasingStyle.Sine
local IN_OUT = Enum.EasingDirection.InOut
local OUT = Enum.EasingDirection.Out
local KEYFRAMES: { Pose.Keyframe } = {
	{ Time = 0, Pose = {} },
	{ Time = 0.3, Style = Enum.EasingStyle.Quad, Direction = OUT, Pose = prayer(4) },
	{ Time = 0.8, Style = SINE, Direction = IN_OUT, Pose = prayer(10) },
	{ Time = 1.25, Style = SINE, Direction = IN_OUT, Pose = prayer(14) }, -- bowed lowest just before the summon
	{ Time = 1.5, Style = Enum.EasingStyle.Back, Direction = OUT, Markers = { "Summon" }, Pose = spread(0) }, -- SUMMON
	{ Time = 2.2, Style = SINE, Direction = IN_OUT, Pose = spread(6) },
	{ Time = 2.8, Style = SINE, Direction = IN_OUT, Pose = {} },
}

return KEYFRAMES

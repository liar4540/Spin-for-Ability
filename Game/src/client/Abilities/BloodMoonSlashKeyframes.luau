--!strict
-- Blood Moon Slash: iaido draw. Written by hand (the Studio animation generator failed on this
-- description three times, 2026-11-26). The right hand reaches across to the katana at the LEFT hip,
-- holds while Blood Moon energy gathers, then draws in one horizontal cut out to the right - the
-- crescent is released as the blade clears the sheath - and ends in a follow-through, then a ready stance.
-- Pose format: client/Abilities/Pose (degrees in the parent part's space: X pitch, Y yaw, Z roll;
-- +X pitch swings a limb forward, +Y yaw turns left, +Z roll swings an arm out to the body's right;
-- Rot (90, 0, a) = arm level, a degrees right of straight ahead). Checked with forward kinematics.
-- Markers: "Grip" (hand on the hilt), "Release" (the draw's fastest moment: the crescent leaves).

local Pose = require(script.Parent.Pose)

local LEGS_LOW = {
	RightHip = { Rot = Vector3.new(35, 0, -5) },
	RightKnee = { Rot = Vector3.new(-50, 0, 0) },
	LeftHip = { Rot = Vector3.new(-15, 0, 8) },
	LeftKnee = { Rot = Vector3.new(-35, 0, 0) },
}

local function with(base: { [string]: Pose.JointPose }, extra: { [string]: Pose.JointPose }): { [string]: Pose.JointPose }
	local out = table.clone(base)
	for k, v in extra do
		out[k] = v
	end
	return out
end

local KEYFRAMES: { Pose.Keyframe } = {
	{ Time = 0, Pose = {} },
	{ -- reach across: crouch, twist left, right hand to the hilt at the left hip
		Time = 0.3,
		Style = Enum.EasingStyle.Quad,
		Direction = Enum.EasingDirection.Out,
		Markers = { "Grip" },
		Pose = with(LEGS_LOW, {
			Root = { Pos = Vector3.new(0, -0.55, 0), Rot = Vector3.new(0, 30, 0) },
			Waist = { Rot = Vector3.new(-8, 20, 0) },
			RightShoulder = { Rot = Vector3.new(35, 0, -55) },
			RightElbow = { Rot = Vector3.new(45, 0, 0) },
			LeftShoulder = { Rot = Vector3.new(25, 0, 15) },
			LeftElbow = { Rot = Vector3.new(50, 0, 0) },
		}),
	},
	{ -- hold the tension while the energy gathers (a little deeper)
		Time = 0.52,
		Style = Enum.EasingStyle.Linear,
		Pose = with(LEGS_LOW, {
			Root = { Pos = Vector3.new(0, -0.65, 0), Rot = Vector3.new(0, 33, 0) },
			Waist = { Rot = Vector3.new(-10, 25, 0) },
			RightShoulder = { Rot = Vector3.new(38, 0, -58) },
			RightElbow = { Rot = Vector3.new(48, 0, 0) },
			LeftShoulder = { Rot = Vector3.new(25, 0, 15) },
			LeftElbow = { Rot = Vector3.new(50, 0, 0) },
		}),
	},
	{ -- THE DRAW: the torso unwinds and the arm whips out to the right at shoulder height
		Time = 0.64,
		Style = Enum.EasingStyle.Quad,
		Direction = Enum.EasingDirection.Out,
		Markers = { "Release" },
		Pose = with(LEGS_LOW, {
			Root = { Pos = Vector3.new(0, -0.6, 0), Rot = Vector3.new(0, -15, 0) },
			Waist = { Rot = Vector3.new(-5, -10, 0) },
			RightShoulder = { Rot = Vector3.new(90, 0, 25) }, -- arm level, pointing forward-right
			RightElbow = { Rot = Vector3.new(5, 0, 0) },
			LeftShoulder = { Rot = Vector3.new(15, 0, -10) },
			LeftElbow = { Rot = Vector3.new(30, 0, 0) },
		}),
	},
	{ -- follow-through: the blade carries on behind to the right
		Time = 0.92,
		Style = Enum.EasingStyle.Sine,
		Direction = Enum.EasingDirection.Out,
		Pose = with(LEGS_LOW, {
			Root = { Pos = Vector3.new(0, -0.55, 0), Rot = Vector3.new(0, -35, 0) },
			Waist = { Rot = Vector3.new(-3, -15, 0) },
			RightShoulder = { Rot = Vector3.new(85, 0, 80) }, -- carried on out to the right
			RightElbow = { Rot = Vector3.new(8, 0, 0) },
			LeftShoulder = { Rot = Vector3.new(15, 0, -10) },
			LeftElbow = { Rot = Vector3.new(30, 0, 0) },
		}),
	},
	{ -- ready stance, blade low at the side
		Time = 1.45,
		Style = Enum.EasingStyle.Sine,
		Direction = Enum.EasingDirection.InOut,
		Pose = {
			Root = { Pos = Vector3.new(0, -0.2, 0), Rot = Vector3.new(0, -10, 0) },
			Waist = { Rot = Vector3.new(0, -5, 0) },
			RightShoulder = { Rot = Vector3.new(30, 0, 25) },
			RightElbow = { Rot = Vector3.new(25, 0, 0) },
			LeftShoulder = { Rot = Vector3.new(10, 0, -5) },
			RightHip = { Rot = Vector3.new(15, 0, 0) },
			RightKnee = { Rot = Vector3.new(-15, 0, 0) },
			LeftHip = { Rot = Vector3.new(-5, 0, 0) },
			LeftKnee = { Rot = Vector3.new(-10, 0, 0) },
		},
	},
	{ Time = 1.8, Style = Enum.EasingStyle.Sine, Direction = Enum.EasingDirection.InOut, Pose = {} },
}

return KEYFRAMES

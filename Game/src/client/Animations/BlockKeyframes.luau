--!strict
-- Block pose (hold F): forearms crossed in front of the face, slight crouch.
-- Hand-written placeholder until the animator makes the real one in Blender (build_combat_anims.py)
-- like the other combat moves. Same format as CombatKeyframes (client/Abilities/Pose):
-- Rot = degrees (pitch X, yaw Y, roll Z) in the parent part's space, -Z = forward.
-- Shoulders: roll the arm inward first, then pitch it forward; elbows bend the forearms up.

local Pose = require(script.Parent.Parent:WaitForChild("Abilities"):WaitForChild("Pose"))

local GUARD: { [string]: Pose.JointPose } = {
	Waist = { Rot = Vector3.new(8, 0, 0) },
	RightShoulder = { Rot = Vector3.new(80, 0, -30) },
	LeftShoulder = { Rot = Vector3.new(80, 0, 30) },
	RightElbow = { Rot = Vector3.new(100, 0, 0) },
	LeftElbow = { Rot = Vector3.new(100, 0, 0) },
	RightHip = { Rot = Vector3.new(10, 0, 0) },
	LeftHip = { Rot = Vector3.new(10, 0, 0) },
	RightKnee = { Rot = Vector3.new(-15, 0, 0) },
	LeftKnee = { Rot = Vector3.new(-15, 0, 0) },
}

local BlockKeyframes = {
	Block = {
		Length = 0.2,
		HitTime = 0,
		Keyframes = {
			{ Time = 0, Pose = GUARD },
			{ Time = 0.2, Pose = GUARD },
		} :: { Pose.Keyframe },
	},
}

return BlockKeyframes

--!strict
-- Pose: turns keyframes written in code into a real Roblox animation and plays it on the
-- character's Animator. Works with both joint kinds (Motor6D and the newer AnimationConstraint),
-- blends with the walk/idle animation, and Roblox replicates it to every other player.
--
-- Where the animation comes from:
--   * AnimationId set (in Shared/Config/Abilities): the uploaded animation. Live game.
--   * No AnimationId, in Studio: the keyframes are built into a KeyframeSequence and registered
--     as a temporary Studio-only animation, so moves can be made and tested before uploading.
--   * No AnimationId, live game: no animation (the VFX still play).
-- To upload: Pose.Build(...) the sequence (ServerStorage.AnimationSources has a copy), right-click
-- it → Save to Roblox, and put the new id in the ability's AnimationId.
--
-- R15 only. Each pose is the joint's rotation/offset in its parent part's space:
-- X = right, Y = up, -Z = forward. Rot = degrees (pitch X, yaw Y, roll Z), Pos = studs.
-- A joint left out of a keyframe = rest.

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local RunService = game:GetService("RunService")

export type JointPose = { Rot: Vector3?, Pos: Vector3? }
export type Keyframe = {
	Time: number,
	Pose: { [string]: JointPose },
	-- How the move INTO this keyframe eases.
	Style: Enum.EasingStyle?,
	Direction: Enum.EasingDirection?,
	-- KeyframeMarkers on this keyframe (track:GetMarkerReachedSignal(name)).
	Markers: { string }?,
}

-- R15 joint name → the part it moves, and that part's parent in the pose tree.
-- Optional joints are only posed in sequences that use them, so moves that leave them out keep
-- the idle/walk animation on the head, hands and feet.
local JOINTS: { { Joint: string, Part: string, Parent: string, Optional: boolean? } } = {
	{ Joint = "Root", Part = "LowerTorso", Parent = "HumanoidRootPart" },
	{ Joint = "Waist", Part = "UpperTorso", Parent = "LowerTorso" },
	{ Joint = "Neck", Part = "Head", Parent = "UpperTorso", Optional = true },
	{ Joint = "RightShoulder", Part = "RightUpperArm", Parent = "UpperTorso" },
	{ Joint = "RightElbow", Part = "RightLowerArm", Parent = "RightUpperArm" },
	{ Joint = "RightWrist", Part = "RightHand", Parent = "RightLowerArm", Optional = true },
	{ Joint = "LeftShoulder", Part = "LeftUpperArm", Parent = "UpperTorso" },
	{ Joint = "LeftElbow", Part = "LeftLowerArm", Parent = "LeftUpperArm" },
	{ Joint = "LeftWrist", Part = "LeftHand", Parent = "LeftLowerArm", Optional = true },
	{ Joint = "RightHip", Part = "RightUpperLeg", Parent = "LowerTorso" },
	{ Joint = "RightKnee", Part = "RightLowerLeg", Parent = "RightUpperLeg" },
	{ Joint = "RightAnkle", Part = "RightFoot", Parent = "RightLowerLeg", Optional = true },
	{ Joint = "LeftHip", Part = "LeftUpperLeg", Parent = "LowerTorso" },
	{ Joint = "LeftKnee", Part = "LeftLowerLeg", Parent = "LeftUpperLeg" },
	{ Joint = "LeftAnkle", Part = "LeftFoot", Parent = "LeftLowerLeg", Optional = true },
}

local Pose = {}

local studioIds: { [string]: string } = {} -- [name] = registered temporary id
local tracks: { [Animator]: { [string]: AnimationTrack } } = setmetatable({}, { __mode = "k" }) :: any

local function poseCFrame(pose: JointPose?): CFrame
	if not pose then
		return CFrame.identity
	end
	local rot = pose.Rot or Vector3.zero
	return CFrame.new(pose.Pos or Vector3.zero) * CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
end

local function poseEasing(keyframe: Keyframe?): (Enum.PoseEasingStyle, Enum.PoseEasingDirection)
	if not keyframe or keyframe.Style == Enum.EasingStyle.Linear then
		return Enum.PoseEasingStyle.Linear, Enum.PoseEasingDirection.In
	end
	local direction = keyframe.Direction or Enum.EasingDirection.Out
	local poseDirection = if direction == Enum.EasingDirection.In
		then Enum.PoseEasingDirection.In
		elseif direction == Enum.EasingDirection.InOut then Enum.PoseEasingDirection.InOut
		else Enum.PoseEasingDirection.Out
	return Enum.PoseEasingStyle.CubicV2, poseDirection
end

-- Build a KeyframeSequence from keyframes. Every joint gets a pose in every keyframe.
function Pose.Build(name: string, keyframes: { Keyframe }): KeyframeSequence
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = name
	sequence.Loop = false
	sequence.Priority = Enum.AnimationPriority.Action

	local used: { [string]: boolean } = {}
	for _, keyframe in keyframes do
		for joint in keyframe.Pose do
			used[joint] = true
		end
	end

	for index, keyframe in keyframes do
		-- A Pose's easing shapes the move from it to the NEXT keyframe.
		local style, direction = poseEasing(keyframes[index + 1])

		local frame = Instance.new("Keyframe")
		frame.Time = keyframe.Time
		local byPart: { [string]: Instance } = {}
		local root = Instance.new("Pose")
		root.Name = "HumanoidRootPart"
		root.Weight = 0
		root.Parent = frame
		byPart.HumanoidRootPart = root

		for _, joint in JOINTS do
			if joint.Optional and not used[joint.Joint] then
				continue
			end
			local pose = Instance.new("Pose")
			pose.Name = joint.Part
			pose.CFrame = poseCFrame(keyframe.Pose[joint.Joint])
			pose.EasingStyle = style
			pose.EasingDirection = direction
			pose.Weight = 1
			pose.Parent = byPart[joint.Parent]
			byPart[joint.Part] = pose
		end
		for _, markerName in keyframe.Markers or {} do
			local marker = Instance.new("KeyframeMarker")
			marker.Name = markerName
			frame:AddMarker(marker) -- parenting a marker directly is ignored
		end
		frame.Parent = sequence
	end
	return sequence
end

local function animationIdFor(name: string, keyframes: { Keyframe }, animationId: string?): string?
	if animationId and animationId ~= "" then
		return animationId
	end
	if not RunService:IsStudio() then
		return nil
	end
	local id = studioIds[name]
	if not id then
		id = KeyframeSequenceProvider:RegisterKeyframeSequence(Pose.Build(name, keyframes))
		studioIds[name] = id
	end
	return id
end

-- The character's track for this move (loaded once per character), or nil if there's none.
function Pose.Track(character: Model, name: string, keyframes: { Keyframe }, animationId: string?): AnimationTrack?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local perAnimator = tracks[animator]
	if not perAnimator then
		perAnimator = {}
		tracks[animator] = perAnimator
	end
	local track = perAnimator[name]
	if track then
		return track
	end
	local id = animationIdFor(name, keyframes, animationId)
	if not id then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	track = animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action
	perAnimator[name] = track
	return track
end

return Pose

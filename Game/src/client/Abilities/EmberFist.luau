--!strict
-- Ember Fist (Common, Melee): fiery punch, small knockback.
-- Look: images/abilities/fiery fist.png + vault 11 Abilities ("Orange-white flash on the fist,
-- small fire burst + shock ring at the hit"). Every texture is made in Blender
-- (Game/assets/vfx/_src/build_ember_fist.py); the ring, spike burst and swing arc are the shared
-- kit meshes rendered into sprites and played on oriented particles (Config/Assets).
--
--   1. Wind-up   0 – 0.21 s   arm pulls back; fist glows orange-white with flames, a fire trail,
--                             and an orange swing arc (crescent sprite) swirls round the body.
--   2. Impact    0.27 s       punch lands: flash, spike burst, upright shock rings facing the punch,
--                             flame burst + spark streaks, light flash, camera shake, sound.
--   3. Aftermath to ~1.6 s    double ground shock ring, ember flakes rising, a little smoke.
-- IMPACT_TIME matches WindupSeconds in Shared/Config/Abilities (when the server's hit lands).
--
-- Budget per cast (vault: 05 World & Art → particle budget): full ≈ 80 particles, 2 lights,
-- 2 sounds; Low (client/VFX/Quality) ≈ 35 particles: no arc, smoke, embers or second rings.
-- Pooled: each character gets its pieces once (on first use); every cast re-emits them.
-- Others' casts play the same VFX; the animation reaches them through Roblox's replication.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Abilities = require(Config:WaitForChild("Abilities"))
local Assets = require(Config:WaitForChild("Assets"))

local Client = script.Parent.Parent
local Pose = require(script.Parent.Pose)
local Quality = require(Client:WaitForChild("VFX"):WaitForChild("Quality"))

local IMPACT_TIME = 0.27
local GLOW_END = 0.45 -- fist glow, flames and trail switch off

local animationId: string? = nil
for _, def in Abilities do
	if def.Id == "EmberFist" then
		animationId = def.AnimationId
	end
end

-- Three tones per effect (vault rule): white-hot edge, main orange, dark red falloff.
local WHITE = Color3.fromRGB(255, 240, 205)
local ORANGE = Color3.fromRGB(255, 135, 30)
local RED = Color3.fromRGB(190, 45, 10)
local FIRE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, WHITE),
	ColorSequenceKeypoint.new(0.2, ORANGE),
	ColorSequenceKeypoint.new(1, RED),
})
local HOT = ColorSequence.new(WHITE, ORANGE)
-- Impact layers: orange-led with a pale-gold start, so stacked glow doesn't burn out to white.
local GOLD = ColorSequence.new(Color3.fromRGB(255, 200, 120), ORANGE)
local EMBER_ORANGE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 170, 60)),
	ColorSequenceKeypoint.new(0.4, ORANGE),
	ColorSequenceKeypoint.new(1, RED),
})

local KEYFRAMES: { Pose.Keyframe } = {
	{ Time = 0, Pose = {} },
	{ -- Wind-up: crouch, twist away, fist cocked back by the chest, left hand guarding.
		Time = 0.15,
		Style = Enum.EasingStyle.Quad,
		Pose = {
			Root = { Rot = Vector3.new(0, -30, 0), Pos = Vector3.new(0, -0.35, 0.25) },
			Waist = { Rot = Vector3.new(0, -20, 0) },
			RightShoulder = { Rot = Vector3.new(-45, 0, 45) },
			RightElbow = { Rot = Vector3.new(125, 0, 0) },
			LeftShoulder = { Rot = Vector3.new(70, 15, -10) },
			LeftElbow = { Rot = Vector3.new(80, 0, 0) },
			LeftHip = { Rot = Vector3.new(25, 0, 0) },
			LeftKnee = { Rot = Vector3.new(-35, 0, 0) },
			RightHip = { Rot = Vector3.new(-15, 0, 0) },
			RightKnee = { Rot = Vector3.new(-20, 0, 0) },
		},
	},
	{ -- Hold the wind-up a beat so the punch reads.
		Time = 0.21,
		Style = Enum.EasingStyle.Linear,
		Pose = {
			Root = { Rot = Vector3.new(0, -34, 0), Pos = Vector3.new(0, -0.4, 0.3) },
			Waist = { Rot = Vector3.new(0, -22, 0) },
			RightShoulder = { Rot = Vector3.new(-48, 0, 48) },
			RightElbow = { Rot = Vector3.new(130, 0, 0) },
			LeftShoulder = { Rot = Vector3.new(70, 15, -10) },
			LeftElbow = { Rot = Vector3.new(80, 0, 0) },
			LeftHip = { Rot = Vector3.new(25, 0, 0) },
			LeftKnee = { Rot = Vector3.new(-35, 0, 0) },
			RightHip = { Rot = Vector3.new(-15, 0, 0) },
			RightKnee = { Rot = Vector3.new(-20, 0, 0) },
		},
	},
	{ -- Punch: snap forward, lunge, arm straight, left arm pulled back.
		Time = IMPACT_TIME,
		Style = Enum.EasingStyle.Quart,
		Pose = {
			Root = { Rot = Vector3.new(0, 20, 0), Pos = Vector3.new(0, -0.45, -0.9) },
			Waist = { Rot = Vector3.new(-8, 15, 0) },
			RightShoulder = { Rot = Vector3.new(92, 0, 0) },
			RightElbow = { Rot = Vector3.new(5, 0, 0) },
			LeftShoulder = { Rot = Vector3.new(-25, 0, -15) },
			LeftElbow = { Rot = Vector3.new(100, 0, 0) },
			LeftHip = { Rot = Vector3.new(40, 0, 0) },
			LeftKnee = { Rot = Vector3.new(-50, 0, 0) },
			RightHip = { Rot = Vector3.new(-30, 0, 0) },
			RightKnee = { Rot = Vector3.new(-10, 0, 0) },
		},
	},
	{ -- Follow-through hold.
		Time = 0.48,
		Style = Enum.EasingStyle.Sine,
		Pose = {
			Root = { Rot = Vector3.new(0, 22, 0), Pos = Vector3.new(0, -0.4, -0.85) },
			Waist = { Rot = Vector3.new(-6, 15, 0) },
			RightShoulder = { Rot = Vector3.new(88, 0, 0) },
			RightElbow = { Rot = Vector3.new(10, 0, 0) },
			LeftShoulder = { Rot = Vector3.new(-25, 0, -15) },
			LeftElbow = { Rot = Vector3.new(100, 0, 0) },
			LeftHip = { Rot = Vector3.new(38, 0, 0) },
			LeftKnee = { Rot = Vector3.new(-48, 0, 0) },
			RightHip = { Rot = Vector3.new(-28, 0, 0) },
			RightKnee = { Rot = Vector3.new(-10, 0, 0) },
		},
	},
	{ Time = 0.78, Style = Enum.EasingStyle.Sine, Direction = Enum.EasingDirection.InOut, Pose = {} },
}

type Rig = {
	Folder: Folder,
	-- on the character
	Fist: Attachment,
	FistCore: ParticleEmitter,
	Glow: ParticleEmitter,
	Flames: ParticleEmitter,
	FistLight: PointLight,
	Trail: Trail,
	Arc: ParticleEmitter,
	Windup: Sound,
	-- at the hit (world, pooled)
	Impact: Part,
	Burst: Attachment, -- faces the punch (-Z = forward)
	Ground: Attachment, -- flat on the ground (Y = up)
	Flash: ParticleEmitter,
	Spikes: ParticleEmitter,
	FistRing: ParticleEmitter,
	Fire: ParticleEmitter,
	Sparks: ParticleEmitter,
	GroundRing: ParticleEmitter,
	Embers: ParticleEmitter,
	Smoke: ParticleEmitter,
	ImpactLight: PointLight,
	ImpactSound: Sound,
}

local EmberFist = {}

local rigs: { [Model]: Rig } = {}
local vfxFolder: Folder? = nil

local function folder(): Folder
	if vfxFolder and vfxFolder.Parent then
		return vfxFolder
	end
	local f = Instance.new("Folder")
	f.Name = "ClientVFX"
	f.Parent = workspace
	vfxFolder = f
	return f
end

local function numbers(...: number): NumberSequence
	local values = { ... }
	local points = {}
	for i = 1, #values, 2 do
		table.insert(points, NumberSequenceKeypoint.new(values[i], values[i + 1]))
	end
	return NumberSequence.new(points)
end

local function emitter(parent: Instance, name: string, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Enabled = false
	e.Rate = 0
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Color = FIRE
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

-- A flat sprite (ring, arc) that lies in the plane facing its emission direction.
local function flatSprite(parent: Instance, name: string, direction: Enum.NormalId, props: { [string]: any }): ParticleEmitter
	local e = emitter(parent, name, props)
	e.EmissionDirection = direction
	e.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	e.Speed = NumberRange.new(0.01)
	e.SpreadAngle = Vector2.zero
	return e
end

local function sound(parent: Instance, id: string, volume: number): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.RollOffMaxDistance = 120
	s.Parent = parent
	return s
end

local function handPart(character: Model): BasePart?
	return (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) :: BasePart?
end

local function attachment(parent: Instance, name: string, cframe: CFrame): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cframe
	a.Parent = parent
	return a
end

local function buildRig(character: Model, hand: BasePart, root: BasePart): Rig
	local f = Instance.new("Folder")
	f.Name = `EmberFist_{character.Name}`
	f.Parent = folder()

	-- R6 arms are 2 studs long: put the fist at the bottom.
	local fistY = if hand.Name == "Right Arm" then -1 else -0.1
	local fist = attachment(hand, "EmberFist", CFrame.new(0, fistY, 0))
	local trailTop = attachment(hand, "EmberFistTrailTop", CFrame.new(0, fistY + 0.5, 0))
	local trailBottom = attachment(hand, "EmberFistTrailBottom", CFrame.new(0, fistY - 0.5, 0))
	-- Swing arc lies in a plane tilted 20° (up = this attachment's Y), round the chest.
	local chest = attachment(root, "EmberFistArc", CFrame.new(0, 0.6, 0) * CFrame.Angles(math.rad(-20), 0, math.rad(-10)))

	local trail = Instance.new("Trail")
	trail.Name = "EmberFistTrail"
	trail.Attachment0 = trailTop
	trail.Attachment1 = trailBottom
	trail.Lifetime = 0.16
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.FaceCamera = true
	trail.Color = FIRE
	trail.Transparency = numbers(0, 0.05, 0.6, 0.5, 1, 1)
	trail.WidthScale = numbers(0, 1, 1, 0.2)
	trail.Enabled = false
	trail.Parent = hand

	local impact = Instance.new("Part")
	impact.Name = "Impact"
	impact.Anchored = true
	impact.CanCollide = false
	impact.CanTouch = false
	impact.CanQuery = false
	impact.CastShadow = false
	impact.Transparency = 1
	impact.Size = Vector3.one
	impact.Parent = f
	local burst = attachment(impact, "Burst", CFrame.identity)
	local ground = attachment(impact, "Ground", CFrame.identity)

	local rig: Rig = {
		Folder = f,
		Fist = fist,
		FistCore = emitter(fist, "FistCore", {
			Texture = Assets.Textures.Glow,
			Color = ColorSequence.new(Color3.fromRGB(255, 225, 170)),
			Size = numbers(0, 1.2, 1, 0.9),
			Transparency = numbers(0, 0, 1, 0.6),
			Lifetime = NumberRange.new(0.08),
			Rate = 40,
			Speed = NumberRange.new(0),
			LockedToPart = true,
			ZOffset = 2,
		}),
		Glow = emitter(fist, "FistGlow", {
			Texture = Assets.Textures.Glow,
			Color = GOLD,
			Size = numbers(0, 3, 1, 2),
			Transparency = numbers(0, 0.3, 1, 1),
			Lifetime = NumberRange.new(0.12),
			Rate = 30,
			Speed = NumberRange.new(0),
			LockedToPart = true,
			ZOffset = 1,
		}),
		Flames = emitter(fist, "FistFlames", {
			Texture = Assets.Textures.Flame,
			FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2,
			FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
			Size = numbers(0, 1.2, 1, 0.3),
			Transparency = numbers(0, 0.1, 1, 1),
			Lifetime = NumberRange.new(0.2, 0.32),
			Rate = 45,
			Speed = NumberRange.new(2, 4),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, 8, 0),
			Rotation = NumberRange.new(-20, 20),
		}),
		FistLight = Instance.new("PointLight"),
		Trail = trail,
		Arc = flatSprite(chest, "SwingArc", Enum.NormalId.Top, {
			Texture = Assets.Textures.ArcSprite,
			Color = EMBER_ORANGE,
			Size = numbers(0, 4, 1, 4.8),
			Transparency = numbers(0, 0.5, 0.3, 0, 1, 1),
			Lifetime = NumberRange.new(0.3),
			-- Starts with the arc's bright head behind-right, then whips round to the front.
			Rotation = NumberRange.new(140),
			RotSpeed = NumberRange.new(-520),
			LockedToPart = true,
		}),
		Windup = sound(fist, Assets.Sounds.EmberFistWindup, 0.6),
		Impact = impact,
		Burst = burst,
		Ground = ground,
		Flash = emitter(burst, "Flash", {
			Texture = Assets.Textures.Glow,
			Color = GOLD,
			LightEmission = 0.6,
			Size = numbers(0, 1.6, 1, 3.5),
			Transparency = numbers(0, 0.35, 1, 1),
			Lifetime = NumberRange.new(0.15),
			Speed = NumberRange.new(0),
			ZOffset = 3,
		}),
		Spikes = emitter(burst, "SpikeBurst", {
			Texture = Assets.Textures.BurstSprite,
			Color = EMBER_ORANGE,
			LightEmission = 0.8,
			Size = numbers(0, 1.5, 0.4, 5.5, 1, 6.5),
			Transparency = numbers(0, 0, 0.5, 0.2, 1, 1),
			Lifetime = NumberRange.new(0.2),
			Speed = NumberRange.new(0),
			Rotation = NumberRange.new(0, 360),
			ZOffset = 2,
		}),
		FistRing = flatSprite(burst, "FistRing", Enum.NormalId.Front, {
			Texture = Assets.Textures.RingSprite,
			Color = GOLD,
			Size = numbers(0, 1, 1, 7),
			Transparency = numbers(0, 0, 0.6, 0.3, 1, 1),
			Lifetime = NumberRange.new(0.3),
			ZOffset = 1,
		}),
		Fire = emitter(burst, "FireBurst", {
			Texture = Assets.Textures.Flame,
			FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2,
			FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
			EmissionDirection = Enum.NormalId.Front,
			Color = EMBER_ORANGE,
			LightEmission = 0.45,
			Size = numbers(0, 1.4, 0.4, 2.1, 1, 0.5),
			Transparency = numbers(0, 0.1, 0.7, 0.35, 1, 1),
			Lifetime = NumberRange.new(0.3, 0.5),
			Speed = NumberRange.new(10, 22),
			Drag = 7,
			SpreadAngle = Vector2.new(45, 45),
			Acceleration = Vector3.new(0, 6, 0),
			Rotation = NumberRange.new(-30, 30),
			ZOffset = 1,
		}),
		Sparks = emitter(burst, "Sparks", {
			Texture = Assets.Textures.Spark,
			EmissionDirection = Enum.NormalId.Front,
			Orientation = Enum.ParticleOrientation.VelocityParallel,
			Color = HOT,
			Size = numbers(0, 0.9, 1, 0),
			Squash = numbers(0, 1.5, 1, 1.5),
			Lifetime = NumberRange.new(0.12, 0.24),
			Speed = NumberRange.new(40, 70),
			Drag = 4,
			SpreadAngle = Vector2.new(60, 60),
			ZOffset = 2,
		}),
		GroundRing = flatSprite(ground, "GroundRing", Enum.NormalId.Top, {
			Texture = Assets.Textures.RingSprite,
			Color = EMBER_ORANGE,
			Size = numbers(0, 2, 1, 13),
			Transparency = numbers(0, 0.05, 0.5, 0.3, 1, 1),
			Lifetime = NumberRange.new(0.5),
		}),
		Embers = emitter(ground, "Embers", {
			Texture = Assets.Textures.Ember,
			EmissionDirection = Enum.NormalId.Top,
			Color = ColorSequence.new(Color3.fromRGB(255, 140, 35), RED),
			Size = numbers(0, 0.5, 1, 0.1),
			Transparency = numbers(0, 0, 0.8, 0.2, 1, 1),
			Lifetime = NumberRange.new(0.9, 1.6),
			Speed = NumberRange.new(4, 9),
			Acceleration = Vector3.new(0, 2, 0),
			Drag = 1.5,
			SpreadAngle = Vector2.new(70, 70),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-180, 180),
		}),
		Smoke = emitter(ground, "Smoke", {
			Texture = Assets.Textures.Smoke,
			EmissionDirection = Enum.NormalId.Top,
			Color = ColorSequence.new(Color3.fromRGB(130, 100, 80), Color3.fromRGB(70, 60, 55)),
			LightEmission = 0,
			LightInfluence = 1,
			Size = numbers(0, 2, 1, 5),
			Transparency = numbers(0, 0.55, 1, 1),
			Lifetime = NumberRange.new(0.8, 1.2),
			Speed = NumberRange.new(2, 4),
			SpreadAngle = Vector2.new(80, 80),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-40, 40),
		}),
		ImpactLight = Instance.new("PointLight"),
		ImpactSound = sound(burst, Assets.Sounds.EmberFistImpact, 0.8),
	}
	rig.FistLight.Color = ORANGE
	rig.FistLight.Range = 8
	rig.FistLight.Brightness = 0
	rig.FistLight.Parent = fist
	rig.ImpactLight.Color = ORANGE
	rig.ImpactLight.Range = 12
	rig.ImpactLight.Brightness = 0
	rig.ImpactLight.Parent = burst

	-- Cleanup: the world folder goes with the character. The hand/chest pieces live inside the
	-- character and go with it anyway.
	character.Destroying:Connect(function()
		rigs[character] = nil
		f:Destroy()
	end)
	return rig
end

local function getRig(character: Model): Rig?
	local existing = rigs[character]
	if existing and existing.Folder.Parent and existing.Fist.Parent then
		return existing
	end
	local hand = handPart(character)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hand or not root then
		return nil
	end
	local rig = buildRig(character, hand, root)
	rigs[character] = rig
	return rig
end

local function groundBelow(position: Vector3, character: Model): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, folder() }
	local result = workspace:Raycast(position, Vector3.new(0, -12, 0), params)
	return if result then result.Position + Vector3.new(0, 0.06, 0) else position - Vector3.new(0, 3, 0)
end

local function shakeCamera(strength: number, seconds: number)
	local camera = workspace.CurrentCamera
	local started = os.clock()
	local name = "EmberFistShake"
	RunService:UnbindFromRenderStep(name)
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function()
		local t = os.clock() - started
		if t >= seconds then
			RunService:UnbindFromRenderStep(name)
			return
		end
		local r = strength * (1 - t / seconds)
		camera.CFrame *= CFrame.Angles(math.rad((math.random() - 0.5) * r), math.rad((math.random() - 0.5) * r), 0)
	end)
end

local function impact(rig: Rig, character: Model, aim: Vector3, isLocal: boolean, low: boolean)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or not rig.Folder.Parent then
		return
	end
	local flat = Vector3.new(aim.X, 0, aim.Z).Unit
	-- At least chest height, so hunched or short avatars don't punch fire into the floor.
	local fist = rig.Fist.WorldPosition
	fist = Vector3.new(fist.X, math.max(fist.Y, root.Position.Y + 0.6), fist.Z)
	local center = fist + flat * 1.2

	rig.Impact.CFrame = CFrame.lookAt(center, center + flat)
	rig.Ground.WorldCFrame = CFrame.new(groundBelow(center + flat * 0.5, character))

	rig.Flash:Emit(1)
	rig.Spikes:Emit(if low then 1 else 2)
	rig.FistRing:Emit(1)
	rig.GroundRing:Emit(1)
	rig.Fire:Emit(if low then 6 else 11)
	rig.Sparks:Emit(if low then 6 else 12)
	if not low then
		rig.Embers:Emit(16)
		rig.Smoke:Emit(4)
		-- The reference's double ring: a second, later ring at the fist and on the ground.
		task.delay(0.08, function()
			rig.FistRing:Emit(1)
		end)
		task.delay(0.12, function()
			rig.GroundRing:Emit(1)
		end)
	end

	rig.ImpactLight.Brightness = 3
	TweenService:Create(rig.ImpactLight, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()
	rig.ImpactSound:Play()
	if isLocal then
		shakeCamera(1.6, 0.18)
	end
end

-- Play the whole move on a character. Every client runs this for every player who uses it.
-- isLocal = our own character: we play the animation (Roblox replicates it to everyone else)
-- and shake the camera. The VFX are made on each client.
function EmberFist.Play(character: Model, aim: Vector3, isLocal: boolean)
	if isLocal then
		local track = Pose.Track(character, "EmberFist", KEYFRAMES, animationId)
		if track then
			track:Play(0.05)
		end
	end

	local rig = getRig(character)
	if not rig then
		return
	end
	local low = Quality.Low

	rig.Windup:Play()
	rig.FistCore.Enabled = true
	rig.Glow.Enabled = true
	rig.Flames.Enabled = true
	rig.FistLight.Brightness = 3
	if not low then
		rig.Arc:Emit(1)
	end
	task.delay(0.04, function()
		rig.Trail.Enabled = true
	end)
	task.delay(GLOW_END, function()
		rig.Trail.Enabled = false
		rig.FistCore.Enabled = false
		rig.Glow.Enabled = false
		rig.Flames.Enabled = false
		TweenService:Create(rig.FistLight, TweenInfo.new(0.2), { Brightness = 0 }):Play()
	end)

	task.delay(IMPACT_TIME, impact, rig, character, aim, isLocal, low)
end

-- The keyframes, for building the uploadable KeyframeSequence (Pose.Build).
EmberFist.Keyframes = KEYFRAMES

return EmberFist

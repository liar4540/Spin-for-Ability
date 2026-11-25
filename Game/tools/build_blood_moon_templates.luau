--!strict
-- Builds ReplicatedStorage.VFX.BloodMoonSlash, v2 (2026-11-26, after the user's feedback: a real katana
-- not a "lightsaber", a darker / less transparent / more detailed slash with black flames and more
-- movement, a cross-body draw, a more visible bleed, ominous sounds with no drum).
-- Run in Studio's Edit mode (e.g. through the Studio MCP). Needs ServerStorage.KatanaSource (the free
-- Creator Store model 17863301465 "Katana W/ Sheath" by Jovannijk, no scripts) and keeps the existing
-- CastAnimation (built from client/Abilities/BloodMoonSlashKeyframes with Pose.Build).
--   Katana       the sword (blade, guard, grip) + BladeFX (swing trail, black flames, embers, red glow);
--                pivot = Grip (handle centre), +Y = toward the tip
--   Sheath       the scabbard; pivot = where the katana's Grip sits when sheathed
--   SheathMount  CFrameValue: the sheathed Grip in LowerTorso space (the hilt where the hand reaches at 0.52 s)
--   HandGrip     CFrameValue: the drawn Grip in RightHand space
--   Aura         black flames + gathering sparks around the caster during the charge
--   Crescent     5 Beam layers (Smear, Body, Veins, Core, Edge) the script strings along the arc,
--                + black / crimson flames, sparks, peeling streaks, embers, a light
--   Burst        release burst; HitCut on each enemy; Bleed on bleeding enemies (StatusController)
--   Sounds       Charge, Draw, Whoosh, Hit (free Creator Store sounds; swap freely)
-- Textures: Game/assets/vfx/_src/build_blood_moon_textures.py (+ shared glow / wisp / smoke / ring).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local TEX = {
	Edge = "rbxassetid://105743535803213",
	Body = "rbxassetid://86734814892879",
	Smear = "rbxassetid://76168226523013",
	Veins = "rbxassetid://103594726097423",
	Flame = "rbxassetid://136572725019318", -- 4x4 flipbook
	Glow = "rbxassetid://125847870568618",
	Wisp = "rbxassetid://83953606813781",
	Smoke = "rbxassetid://114965428672642", -- 4x4 flipbook
	Ring = "rbxassetid://130368105005697",
}
local SOUNDS = {
	Charge = { "rbxassetid://1837834352", 0.7, 0.85 }, -- REVERSE HARD STOP-Metal Build 02 (APM): ominous build into the draw
	Draw = { "rbxassetid://7326726969", 0.8, 1 }, -- Sword Pull out
	Whoosh = { "rbxassetid://9126228629", 0.9, 0.8 }, -- Whoosh Back Zoom Swoosh (Pro Sound Effects), pitched down
	Hit = { "rbxassetid://108257794693139", 0.7, 0.9 }, -- Impact (6)
}
local KATANA_SCALE = 0.75 -- the source is ~6.5 studs long; R15 characters are ~5 tall
-- Sheathed hilt in LowerTorso space: where the right hand's grip is at 0.52 s (forward kinematics of
-- CastAnimation on an R15 rig), blade running back and down past the left hip.
local SHEATH_POS = Vector3.new(-0.51, 0.88, -1.37)
local SHEATH_DIR = Vector3.new(-0.15, -0.35, 0.92) -- grip -> tip
-- Drawn: blade carries on along the arm (hand -Y), tipped a little forward (RightHand space).
-- (stage check: mostly -Z pointed the blade straight up once the arm was level)
local HAND_DIR = Vector3.new(0, -0.85, -0.5)

local WHITE = Color3.fromRGB(255, 240, 242)
local CRIMSON = Color3.fromRGB(190, 6, 28)
local BRIGHT = Color3.fromRGB(255, 40, 60)
local RED = Color3.fromRGB(120, 0, 12)
local BLOOD = Color3.fromRGB(110, 0, 10)
local INK = Color3.fromRGB(8, 0, 2)

local function fx(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
end

local function seq(points: { { number } }): NumberSequence
	local keys = {}
	for _, p in points do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2], p[3] or 0))
	end
	return NumberSequence.new(keys)
end

local function colors(points: { { any } }): ColorSequence
	local keys = {}
	for _, p in points do
		table.insert(keys, ColorSequenceKeypoint.new(p[1], p[2]))
	end
	return ColorSequence.new(keys)
end

local function emitter(parent: Instance, name: string, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Enabled = false
	e.Rate = 0
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

local function blackFlame(parent: Instance, name: string, size: { number }, rate: number, life: NumberRange)
	return emitter(parent, name, {
		Texture = TEX.Flame,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		Shape = Enum.ParticleEmitterShape.Box,
		Color = colors({ { 0, INK }, { 0.7, Color3.fromRGB(30, 0, 6) }, { 1, Color3.fromRGB(70, 0, 10) } }),
		LightEmission = 0,
		LightInfluence = 0,
		Size = seq({ { 0, size[1], size[1] * 0.3 }, { 1, size[2] } }),
		Transparency = seq({ { 0, 0.05 }, { 0.7, 0.25 }, { 1, 1 } }),
		Lifetime = life,
		Rate = rate,
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(25, 25),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, 7, 0),
		Drag = 2,
		Rotation = NumberRange.new(-12, 12),
		RotSpeed = NumberRange.new(-30, 30),
		ZOffset = 0.2,
	})
end

local function redFlame(parent: Instance, name: string, size: { number }, rate: number)
	return emitter(parent, name, {
		Texture = TEX.Flame,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		Shape = Enum.ParticleEmitterShape.Box,
		Color = colors({ { 0, BRIGHT }, { 0.5, CRIMSON }, { 1, RED } }),
		LightEmission = 0.6,
		Brightness = 1.5,
		Size = seq({ { 0, size[1] }, { 1, size[2] } }),
		Transparency = seq({ { 0, 0.2 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.25, 0.45),
		Rate = rate,
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(30, 30),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, 6, 0),
		ZOffset = 0.1,
	})
end

local function sparks(parent: Instance, name: string, speed: NumberRange)
	return emitter(parent, name, {
		Texture = TEX.Glow,
		Color = colors({ { 0, WHITE }, { 0.25, BRIGHT }, { 1, RED } }),
		LightEmission = 1,
		Brightness = 4,
		Size = seq({ { 0, 0.24, 0.08 }, { 0.6, 0.12 }, { 1, 0 } }),
		Squash = seq({ { 0, 1.6 }, { 1, 0.5 } }),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Lifetime = NumberRange.new(0.25, 0.7),
		Speed = speed,
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
		Acceleration = Vector3.new(0, -6, 0),
		ZOffset = 0.5,
	})
end

local function embers(parent: Instance, name: string, rate: number)
	return emitter(parent, name, {
		Texture = TEX.Glow,
		Shape = Enum.ParticleEmitterShape.Box,
		Color = colors({ { 0, Color3.fromRGB(255, 110, 120) }, { 1, CRIMSON } }),
		LightEmission = 1,
		Brightness = 4,
		Size = seq({ { 0, 0.2 }, { 0.8, 0.1 }, { 1, 0 } }),
		Lifetime = NumberRange.new(0.8, 1.6),
		Rate = rate,
		Speed = NumberRange.new(0.5, 2.5),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 1.5, 0),
		Drag = 1,
		ZOffset = 0.5,
	})
end

local vfx = ReplicatedStorage:FindFirstChild("VFX") or Instance.new("Folder")
vfx.Name = "VFX"
vfx.Parent = ReplicatedStorage
local old = vfx:FindFirstChild("BloodMoonSlash")
local keepAnimation = old and old:FindFirstChild("CastAnimation")
if keepAnimation then
	keepAnimation.Parent = nil
end
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "BloodMoonSlash"

-- ===== Katana + sheath (from the source model) =====
local source = ServerStorage:FindFirstChild("KatanaSource")
assert(source, "ServerStorage.KatanaSource is missing (insert Creator Store model 17863301465)")
local src = source:FindFirstChild("Katana") :: Model
local bladeCube = src.Blade.Blade:FindFirstChild("Cube") :: BasePart
local handle = src.Blade.Blade:FindFirstChild("Cube.003") :: BasePart
local up = (bladeCube.Position - handle.Position).Unit
local flat = bladeCube.CFrame.LookVector
flat = (flat - up * flat:Dot(up)).Unit
local gripCFrame = CFrame.fromMatrix(handle.Position, up:Cross(flat), up, -flat)

local function pivotPart(name: string, cf: CFrame): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(0.1, 0.1, 0.1)
	p.Transparency = 1
	fx(p)
	p.CFrame = cf
	return p
end

local katana = Instance.new("Model")
katana.Name = "Katana"
local grip = pivotPart("Grip", gripCFrame)
grip.Parent = katana
katana.PrimaryPart = grip
for _, part in src.Blade:GetDescendants() do
	if part:IsA("BasePart") then
		local copy = part:Clone()
		fx(copy)
		copy.Parent = katana
	end
end
-- BladeFX: an invisible strip along the blade (guard -> tip) carrying the trail and the blade effects
local tsuba = 0.87
local tipDistance = 5.81
local bladeLength = tipDistance - tsuba
local bladeFx = Instance.new("Part")
bladeFx.Name = "BladeFX"
bladeFx.Size = Vector3.new(0.15, bladeLength, 0.4)
bladeFx.Transparency = 1
fx(bladeFx)
bladeFx.CFrame = gripCFrame * CFrame.new(0, tsuba + bladeLength / 2, 0)
bladeFx.Parent = katana
local hilt = Instance.new("Attachment")
hilt.Name = "Hilt"
hilt.Position = Vector3.new(0, -bladeLength / 2 + 0.3, 0)
hilt.Parent = bladeFx
local tip = Instance.new("Attachment")
tip.Name = "Tip"
tip.Position = Vector3.new(0, bladeLength / 2, 0)
tip.Parent = bladeFx
local swing = Instance.new("Trail")
swing.Name = "Swing"
swing.Attachment0 = hilt
swing.Attachment1 = tip
swing.Texture = TEX.Body
swing.TextureMode = Enum.TextureMode.Stretch
swing.Color = colors({ { 0, WHITE }, { 0.15, BRIGHT }, { 0.5, CRIMSON }, { 1, INK } })
swing.LightEmission = 0.6
swing.Brightness = 2
swing.Transparency = seq({ { 0, 0 }, { 0.5, 0.25 }, { 1, 1 } })
swing.Lifetime = 0.3
swing.Enabled = false
swing.Parent = bladeFx
local edge = Instance.new("Part") -- faint crimson sheen along the edge (steel stays visible)
edge.Name = "EdgeGlow"
edge.Material = Enum.Material.Neon
edge.Color = CRIMSON
edge.Transparency = 0.55
edge.Size = Vector3.new(0.04, bladeLength * 0.95, 0.04)
fx(edge)
edge.CFrame = bladeFx.CFrame * CFrame.new(0.06, 0.05, 0)
edge.Parent = katana
blackFlame(bladeFx, "BlackFlame", { 0.9, 1.8 }, 45, NumberRange.new(0.3, 0.55))
redFlame(bladeFx, "RedFlame", { 0.5, 1.1 }, 25)
embers(bladeFx, "Embers", 18)
local bladeLight = Instance.new("PointLight")
bladeLight.Name = "Light"
bladeLight.Color = CRIMSON
bladeLight.Range = 9
bladeLight.Brightness = 0
bladeLight.Shadows = false
bladeLight.Parent = bladeFx
katana:ScaleTo(KATANA_SCALE)
katana.Parent = folder

local sheath = Instance.new("Model")
sheath.Name = "Sheath"
local sheathPivot = pivotPart("Mount", gripCFrame)
sheathPivot.Parent = sheath
sheath.PrimaryPart = sheathPivot
for _, part in src.Sheath:GetDescendants() do
	if part:IsA("BasePart") then
		local copy = part:Clone()
		fx(copy)
		copy.Parent = sheath
	end
end
sheath:ScaleTo(KATANA_SCALE)
sheath.Parent = folder

local function frame(pos: Vector3, dir: Vector3, side: Vector3): CFrame
	local y = dir.Unit
	local x = (side - y * side:Dot(y)).Unit
	return CFrame.fromMatrix(pos, x, y, x:Cross(y))
end
local mount = Instance.new("CFrameValue")
mount.Name = "SheathMount"
mount.Value = frame(SHEATH_POS, SHEATH_DIR, Vector3.new(0, 1, 0))
mount.Parent = folder
local handGrip = Instance.new("CFrameValue")
handGrip.Name = "HandGrip"
handGrip.Value = frame(Vector3.new(0, -0.15, 0), HAND_DIR, Vector3.new(1, 0, 0))
handGrip.Parent = folder

-- ===== Aura (charge): black flames wavering up round the caster + crimson sparks drawn in =====
local aura = Instance.new("Part")
aura.Name = "Aura"
aura.Size = Vector3.new(3.2, 0.4, 3.2)
aura.Transparency = 1
fx(aura)
blackFlame(aura, "BlackFlame", { 1.5, 3.2 }, 55, NumberRange.new(0.4, 0.7))
redFlame(aura, "RedFlame", { 0.8, 1.6 }, 20)
local pull = sparks(aura, "Gather", NumberRange.new(-6, -3))
pull.Shape = Enum.ParticleEmitterShape.Sphere
pull.Rate = 50
aura.Parent = folder

-- ===== Crescent =====
local crescent = Instance.new("Part")
crescent.Name = "Crescent"
crescent.Size = Vector3.new(22, 3, 2)
crescent.Transparency = 1
fx(crescent)
local function beam(name: string, tex: string, color: ColorSequence, emission: number, brightness: number, speed: number, alpha: number)
	local b = Instance.new("Beam")
	b.Name = name
	b.Texture = tex
	b.TextureMode = Enum.TextureMode.Stretch
	b.TextureSpeed = speed
	b.Color = color
	b.LightEmission = emission
	b.LightInfluence = 0
	b.Brightness = brightness
	b.FaceCamera = true
	b.Segments = 16
	b.Transparency = NumberSequence.new(alpha)
	b.Enabled = false
	b.Parent = crescent
end
-- back to front; widths (studs at the arc's middle) and how far each sits behind the edge are attributes
beam("Smear", TEX.Smear, colors({ { 0, INK }, { 1, Color3.fromRGB(35, 0, 6) } }), 0, 1, 0.8, 0)
beam("Body", TEX.Body, colors({ { 0, Color3.fromRGB(90, 0, 10) }, { 0.5, Color3.fromRGB(165, 0, 20) }, { 1, Color3.fromRGB(90, 0, 10) } }), 0.15, 1, 1.8, 0) -- dark: brighter read pink
beam("Veins", TEX.Veins, ColorSequence.new(INK), 0, 1, 2.6, 0)
beam("Core", TEX.Body, colors({ { 0, BRIGHT }, { 0.5, Color3.fromRGB(255, 90, 100) }, { 1, BRIGHT } }), 1, 1.6, 2.2, 0.15)
beam("Edge", TEX.Edge, ColorSequence.new(WHITE), 1, 5, 0, 0)
for name, value in {
	SmearWidth = 12,
	SmearBehind = 5.5,
	BodyWidth = 8.5,
	BodyBehind = 2.2,
	VeinsWidth = 7,
	VeinsBehind = 2.4,
	CoreWidth = 1.6,
	CoreBehind = 0.6,
	EdgeWidth = 1.1,
	EdgeBehind = 0,
} do
	crescent:SetAttribute(name, value)
end
blackFlame(crescent, "BlackFlame", { 2, 4.5 }, 140, NumberRange.new(0.3, 0.55))
redFlame(crescent, "RedFlame", { 1.2, 2.4 }, 50)
local cs = sparks(crescent, "Sparks", NumberRange.new(6, 16))
cs.Shape = Enum.ParticleEmitterShape.Box
cs.Rate = 90
emitter(crescent, "Streaks", {
	Texture = TEX.Wisp,
	Shape = Enum.ParticleEmitterShape.Box,
	Orientation = Enum.ParticleOrientation.VelocityParallel,
	Color = colors({ { 0, BRIGHT }, { 0.4, CRIMSON }, { 1, INK } }),
	LightEmission = 0.6,
	Brightness = 1.5,
	Size = seq({ { 0, 1.6 }, { 1, 0.4 } }),
	Transparency = seq({ { 0, 0.05 }, { 1, 1 } }),
	Lifetime = NumberRange.new(0.3, 0.6),
	Rate = 45,
	Speed = NumberRange.new(4, 10),
	SpreadAngle = Vector2.new(60, 60),
	Drag = 2,
})
embers(crescent, "Embers", 30)
local crescentLight = Instance.new("PointLight")
crescentLight.Name = "Light"
crescentLight.Color = CRIMSON
crescentLight.Range = 12
crescentLight.Brightness = 1.2 -- more tinted everything pink
crescentLight.Shadows = false
crescentLight.Parent = crescent
crescent.Parent = folder

-- ===== Release burst =====
local burst = Instance.new("Part")
burst.Name = "Burst"
burst.Size = Vector3.new(1.5, 1.5, 1.5)
burst.Transparency = 1
fx(burst)
emitter(burst, "Flash", {
	Texture = TEX.Glow,
	Color = colors({ { 0, WHITE }, { 0.3, BRIGHT }, { 1, RED } }),
	LightEmission = 1,
	Brightness = 3,
	Size = seq({ { 0, 1 }, { 0.3, 2.2 }, { 1, 2.6 } }),
	Transparency = seq({ { 0, 0.1 }, { 1, 1 } }),
	Lifetime = NumberRange.new(0.12, 0.16),
	Speed = NumberRange.new(0),
	ZOffset = 1,
})
emitter(burst, "Ring", {
	Texture = TEX.Ring,
	Color = colors({ { 0, BRIGHT }, { 1, RED } }),
	LightEmission = 0.8,
	Brightness = 2,
	Size = seq({ { 0, 1 }, { 1, 8 } }),
	Transparency = seq({ { 0, 0.15 }, { 1, 1 } }),
	Lifetime = NumberRange.new(0.25),
	Speed = NumberRange.new(0),
})
sparks(burst, "Sparks", NumberRange.new(10, 22))
local burstFlame = blackFlame(burst, "BlackFlame", { 2, 4 }, 0, NumberRange.new(0.35, 0.6))
burstFlame.Shape = Enum.ParticleEmitterShape.Sphere
burstFlame.Speed = NumberRange.new(3, 7)
burstFlame.SpreadAngle = Vector2.new(180, 180)
local burstLight = Instance.new("PointLight")
burstLight.Name = "Light"
burstLight.Color = CRIMSON
burstLight.Range = 14
burstLight.Brightness = 0
burstLight.Shadows = false
burstLight.Parent = burst
burst.Parent = folder

-- ===== Hit cut =====
local hit = Instance.new("Part")
hit.Name = "HitCut"
hit.Size = Vector3.new(1, 1, 1)
hit.Transparency = 1
fx(hit)
emitter(hit, "Cut", {
	Texture = TEX.Edge,
	Color = colors({ { 0, WHITE }, { 1, BRIGHT } }),
	LightEmission = 1,
	Brightness = 5,
	Size = seq({ { 0, 3.5 }, { 1, 5.5 } }),
	Transparency = seq({ { 0, 0 }, { 1, 1 } }),
	Lifetime = NumberRange.new(0.15),
	Speed = NumberRange.new(0),
	Rotation = NumberRange.new(-25, 25),
	ZOffset = 1,
})
sparks(hit, "Sparks", NumberRange.new(8, 18))
local hitBlood = emitter(hit, "Blood", {
	Texture = TEX.Glow,
	Color = ColorSequence.new(BLOOD),
	LightEmission = 0,
	LightInfluence = 0.6,
	Size = seq({ { 0, 0.35 }, { 1, 0.15 } }),
	Lifetime = NumberRange.new(0.4, 0.8),
	Speed = NumberRange.new(6, 12),
	SpreadAngle = Vector2.new(40, 40),
	Acceleration = Vector3.new(0, -30, 0),
})
hitBlood.EmissionDirection = Enum.NormalId.Back
hit.Parent = folder

-- ===== Bleeding Wound (StatusController puts this on a bleeding enemy's HumanoidRootPart) =====
local bleed = Instance.new("Attachment")
bleed.Name = "Bleed"
emitter(bleed, "Drops", { -- blood dripping off the body
	Texture = TEX.Glow,
	Color = colors({ { 0, Color3.fromRGB(170, 0, 18) }, { 1, BLOOD } }),
	LightEmission = 0.15,
	LightInfluence = 0.6,
	Size = seq({ { 0, 0.3 }, { 1, 0.18 } }),
	Squash = seq({ { 0, 0 }, { 0.5, -0.8 }, { 1, -1 } }),
	Lifetime = NumberRange.new(0.5, 0.9),
	Rate = 20,
	Speed = NumberRange.new(0.5, 2),
	SpreadAngle = Vector2.new(180, 180),
	Acceleration = Vector3.new(0, -24, 0),
})
emitter(bleed, "Streaks", { -- dark red slashes flicking off
	Texture = TEX.Wisp,
	Orientation = Enum.ParticleOrientation.VelocityParallel,
	Color = colors({ { 0, CRIMSON }, { 1, RED } }),
	LightEmission = 0.5,
	Size = seq({ { 0, 1.6 }, { 1, 0.5 } }),
	Transparency = seq({ { 0, 0.05 }, { 1, 1 } }),
	Lifetime = NumberRange.new(0.35, 0.6),
	Rate = 4,
	Speed = NumberRange.new(3, 6),
	SpreadAngle = Vector2.new(180, 180),
})
emitter(bleed, "Mist", { -- a faint red haze round the wound
	Texture = TEX.Smoke,
	FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
	FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
	Color = colors({ { 0, CRIMSON }, { 1, RED } }),
	LightEmission = 0.3,
	Size = seq({ { 0, 1.2 }, { 1, 2.6 } }),
	Transparency = seq({ { 0, 0.55 }, { 1, 1 } }),
	Lifetime = NumberRange.new(0.6, 1),
	Rate = 6,
	Speed = NumberRange.new(0.3, 1),
	SpreadAngle = Vector2.new(180, 180),
})
emitter(bleed, "Splash", { -- burst on every bleed tick
	Texture = TEX.Glow,
	Color = ColorSequence.new(Color3.fromRGB(160, 0, 16)),
	LightEmission = 0.2,
	LightInfluence = 0.5,
	Size = seq({ { 0, 0.35 }, { 1, 0.15 } }),
	Lifetime = NumberRange.new(0.4, 0.7),
	Speed = NumberRange.new(5, 10),
	SpreadAngle = Vector2.new(180, 180),
	Acceleration = Vector3.new(0, -30, 0),
})
bleed.Parent = folder

-- ===== Sounds =====
local sounds = Instance.new("Folder")
sounds.Name = "Sounds"
for name, spec in SOUNDS do
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = spec[1] :: string
	sound.Volume = spec[2] :: number
	sound.PlaybackSpeed = spec[3] :: number
	sound.RollOffMaxDistance = 120
	sound.Parent = sounds
end
sounds.Parent = folder

if keepAnimation then
	keepAnimation.Parent = folder
end
folder.Parent = vfx
return `built {#folder:GetChildren()} templates`

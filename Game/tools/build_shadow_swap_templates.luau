--!strict
-- Builds ReplicatedStorage.VFX.ShadowSwap (run in Studio's Edit mode, e.g. through the Studio MCP).
-- Re-running replaces the folder. Every piece is a template that client/Abilities/ShadowSwapVFX clones,
-- places and times; tweak colours, sizes and particles in Studio afterwards - the script reads them.
--   Burst        smoke puff for vanish + reappear: dark flipbook smoke (not glowing, so it reads as
--                shadow even in daylight) + glowing violet smoke + embers + tearing wisps
--   Gather       shadows rising around the feet during the crouch, with a turning swirl on the ground
--   Swirl        ground swirl that spins open under the caster when they reappear
--   StrandDark / StrandGlow   ribbon strands (Trail between two attachments) that fly the teleport
--                path; they shed drifting smoke and embers while they fly
--   CastAnimation  the crouch -> reform animation (KeyframeSequence; Studio plays it straight from here)
-- Textures: Game/assets/vfx/_src/build_shadow_swap_textures.py (+ the shared soft glow from Frost Bloom).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local TEX = {
	Smoke = "rbxassetid://114965428672642", -- 4x4 flipbook
	Wisp = "rbxassetid://83953606813781",
	Swirl = "rbxassetid://102015595169561",
	Glow = "rbxassetid://125847870568618",
}
local INK = Color3.fromRGB(14, 5, 22) -- near-black purple
local DEEP = Color3.fromRGB(58, 16, 96) -- deep purple
local VIOLET = Color3.fromRGB(150, 70, 255) -- dark violet glow
local MAGENTA = Color3.fromRGB(230, 90, 255)
local PALE = Color3.fromRGB(215, 170, 255)

local function fx(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Transparency = 1
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

local function smoke(parent: Instance, name: string, glow: boolean, size: { number }, speed: NumberRange, life: NumberRange)
	return emitter(parent, name, {
		Texture = TEX.Smoke,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		Color = if glow then colors({ { 0, MAGENTA }, { 0.4, VIOLET }, { 1, DEEP } }) else colors({ { 0, INK }, { 1, DEEP } }),
		LightEmission = if glow then 0.9 else 0,
		LightInfluence = if glow then 0 else 0.15,
		Brightness = if glow then 1.6 else 1,
		Size = seq({ { 0, size[1], size[1] * 0.25 }, { 1, size[2], size[2] * 0.2 } }),
		Transparency = if glow then seq({ { 0, 0.35 }, { 0.6, 0.55 }, { 1, 1 } }) else seq({ { 0, 0.05 }, { 0.55, 0.25 }, { 1, 1 } }),
		Lifetime = life,
		Speed = speed,
		SpreadAngle = Vector2.new(180, 180),
		Drag = 5,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-60, 60),
		Acceleration = Vector3.new(0, 1.5, 0),
		ZOffset = if glow then 0.2 else 0,
	})
end

local function embers(parent: Instance, name: string)
	return emitter(parent, name, {
		Texture = TEX.Glow,
		Color = colors({ { 0, PALE }, { 0.35, MAGENTA }, { 1, VIOLET } }),
		LightEmission = 1,
		Brightness = 4,
		Size = seq({ { 0, 0.28, 0.1 }, { 0.7, 0.14 }, { 1, 0 } }),
		Transparency = seq({ { 0, 0 }, { 0.8, 0.2 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.5, 1.3),
		Speed = NumberRange.new(5, 13),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 3.5,
		Acceleration = Vector3.new(0, 2.5, 0),
		ZOffset = 0.5,
	})
end

local function flatImage(part: BasePart, tex: string, color: Color3, transparency: number)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Gui"
	gui.Face = Enum.NormalId.Top
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.CanvasSize = Vector2.new(512, 512)
	gui.Parent = part
	local img = Instance.new("ImageLabel")
	img.Name = "Image"
	img.BackgroundTransparency = 1
	img.Image = tex
	img.ImageColor3 = color
	img.ImageTransparency = transparency
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Position = UDim2.fromScale(0.5, 0.5)
	img.Size = UDim2.fromScale(1, 1)
	img.Parent = gui
end

local vfx = ReplicatedStorage:FindFirstChild("VFX") or Instance.new("Folder")
vfx.Name = "VFX"
vfx.Parent = ReplicatedStorage
local old = vfx:FindFirstChild("ShadowSwap")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "ShadowSwap"

-- Burst: vanish + reappear puff (emitted in bursts by the script)
local burst = Instance.new("Part")
burst.Name = "Burst"
burst.Size = Vector3.new(2, 4, 2) -- spread over the body
fx(burst)
smoke(burst, "DarkSmoke", false, { 2.2, 6 }, NumberRange.new(3, 7), NumberRange.new(0.7, 1.05))
smoke(burst, "VioletSmoke", true, { 1.2, 3.8 }, NumberRange.new(4, 9), NumberRange.new(0.45, 0.75))
embers(burst, "Embers")
emitter(burst, "Wisps", {
	Texture = TEX.Wisp,
	Orientation = Enum.ParticleOrientation.VelocityParallel,
	Color = colors({ { 0, VIOLET }, { 1, INK } }),
	LightEmission = 0.5,
	Size = seq({ { 0, 1.6 }, { 1, 0.6 } }),
	Transparency = seq({ { 0, 0.15 }, { 1, 1 } }),
	Lifetime = NumberRange.new(0.3, 0.55),
	Speed = NumberRange.new(9, 15),
	SpreadAngle = Vector2.new(180, 180),
	Drag = 4,
})
burst.Parent = folder

-- Gather: shadows rising round the feet during the crouch
local gather = Instance.new("Part")
gather.Name = "Gather"
gather.Size = Vector3.new(3.4, 0.2, 3.4)
fx(gather)
emitter(gather, "Rise", {
	Texture = TEX.Smoke,
	FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
	FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
	Shape = Enum.ParticleEmitterShape.Box,
	EmissionDirection = Enum.NormalId.Top,
	Color = colors({ { 0, INK }, { 1, DEEP } }),
	LightEmission = 0,
	LightInfluence = 0.15,
	Size = seq({ { 0, 0.8, 0.3 }, { 1, 2.4 } }),
	Transparency = seq({ { 0, 0.1 }, { 0.6, 0.3 }, { 1, 1 } }),
	Lifetime = NumberRange.new(0.35, 0.55),
	Rate = 90,
	Speed = NumberRange.new(2, 5),
	SpreadAngle = Vector2.new(20, 20),
	Rotation = NumberRange.new(0, 360),
	RotSpeed = NumberRange.new(-90, 90),
})
emitter(gather, "Motes", {
	Texture = TEX.Glow,
	Shape = Enum.ParticleEmitterShape.Box,
	EmissionDirection = Enum.NormalId.Top,
	Color = colors({ { 0, MAGENTA }, { 1, VIOLET } }),
	LightEmission = 1,
	Brightness = 3,
	Size = seq({ { 0, 0.2 }, { 1, 0 } }),
	Lifetime = NumberRange.new(0.3, 0.6),
	Rate = 50,
	Speed = NumberRange.new(3, 7),
	SpreadAngle = Vector2.new(15, 15),
	ZOffset = 0.5,
})
flatImage(gather, TEX.Swirl, VIOLET, 0.2)
gather.Parent = folder

-- Swirl: spins open on the ground where the caster reappears
local swirl = Instance.new("Part")
swirl.Name = "Swirl"
swirl.Size = Vector3.new(7, 0.1, 7)
fx(swirl)
flatImage(swirl, TEX.Swirl, MAGENTA, 0)
swirl.Parent = folder

-- Ribbon strands: a Trail between two attachments on a small carrier part
local function strand(name: string, glow: boolean, width: number, color: ColorSequence)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	fx(part)
	local a0 = Instance.new("Attachment")
	a0.Name = "A0"
	a0.Position = Vector3.new(0, width / 2, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Name = "A1"
	a1.Position = Vector3.new(0, -width / 2, 0)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Name = "Trail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Texture = TEX.Wisp
	trail.TextureMode = Enum.TextureMode.Stretch
	trail.FaceCamera = true
	trail.Lifetime = if glow then 0.8 else 0.9 -- lingers so the path reads (stage check: 0.6 looked like thin lines)
	trail.MinLength = 0
	trail.Color = color
	trail.LightEmission = if glow then 1 else 0.3
	trail.LightInfluence = if glow then 0 else 0.2
	trail.Brightness = if glow then 2.5 else 1
	trail.Transparency = seq({ { 0, 0.05 }, { 0.5, 0.35 }, { 1, 1 } })
	trail.WidthScale = seq({ { 0, 1 }, { 0.6, 0.7 }, { 1, 0.2 } })
	trail.Enabled = false
	trail.Parent = part
	emitter(part, "Drift", {
		Texture = TEX.Smoke,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		Color = if glow then colors({ { 0, VIOLET }, { 1, DEEP } }) else colors({ { 0, INK }, { 1, DEEP } }),
		LightEmission = if glow then 0.7 else 0,
		LightInfluence = if glow then 0 else 0.15,
		Size = seq({ { 0, 0.6 }, { 1, 1.8 } }),
		Transparency = seq({ { 0, 0.3 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.5, 0.9),
		Rate = if glow then 70 else 120,
		Speed = NumberRange.new(0.5, 2),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 2,
		Acceleration = Vector3.new(0, 1.2, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-45, 45),
	})
	if glow then
		local e = embers(part, "Sparks")
		e.Rate = 60
		e.Speed = NumberRange.new(1, 4)
	end
	part.Parent = folder
end
strand("StrandDark", false, 3.2, colors({ { 0, DEEP }, { 0.5, Color3.fromRGB(80, 24, 130) }, { 1, INK } })) -- deep purple: near-black read as nothing on the floor
strand("StrandGlow", true, 1.3, colors({ { 0, PALE }, { 0.3, MAGENTA }, { 1, VIOLET } }))

-- Cast animation (generated with the Studio MCP's generate_animation)
local source = ServerStorage:FindFirstChild("RBX_ASSISTANT_ANIMGEN")
local clip = source and source:FindFirstChild("thePlayerBrieflyCrou")
if clip and clip:IsA("KeyframeSequence") then
	local copy = clip:Clone()
	copy.Name = "CastAnimation"
	copy.Loop = false
	copy.Parent = folder
end

folder.Parent = vfx
return `built {#folder:GetChildren()} templates`

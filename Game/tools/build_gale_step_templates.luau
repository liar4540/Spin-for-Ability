--!strict
-- Gale Step: builds the VFX templates in ReplicatedStorage.VFX.GaleStep (run in Studio, edit mode).
--
-- Run from the Studio command bar or the Studio MCP (needs plugin security, see below):
--     loadstring(<this file>)()        -- or paste it into the command bar
-- then save/publish the place. The templates are SAVED IN THE PLACE, not built at server start
-- like Pebble Toss: the wind meshes use a SurfaceAppearance, and its texture maps (ColorMapContent,
-- EmissiveMaskContent) can only be set by plugins/Studio. Its Color, EmissiveTint, EmissiveStrength
-- and the MeshPart's Transparency ARE scriptable, so GaleStepVFX tints and fades clones at runtime.
-- VFXTemplateService leaves this folder alone (it only rebuilds VFX.PebbleToss).
--
-- Sources: Game/assets/gale_step.blend + Game/assets/vfx/_src/build_gale_step_*.py; asset ids from
-- Game/assets/vfx/gale_step_assets.json (uploaded by upload_gale_step_assets.py).
--
-- Contents (all white/grey textures, tinted with the palette below):
--   CrescentA, CrescentB, Ring, Spiral   MeshPart + SurfaceAppearance (wind_gradient, emissive), unlit-
--                                        looking, DoubleSided, anchored, no collision/shadow
--   Sparkle, Wisp, Swirl, Glow, Dust     ParticleEmitter (Enabled = false, Rate = 0: emit from code)
--   Trail                                Trail (wind_streaks), 0.25 s, width 0.8 -> 0
--   Streak                               Beam (wind_streaks), speed lines along the dash path

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetService = game:GetService("AssetService")

local CORE, MAIN, EDGE = Color3.fromHex("#E9FBFF"), Color3.fromHex("#7FE6FF"), Color3.fromHex("#2FA8D8")

local MESHES = { -- template name -> mesh asset id (inside the uploaded FBX model packages)
	CrescentA = 81358747084401, -- wind_crescent_a (package 97251964717099)
	CrescentB = 73019651433783, -- wind_crescent_b (package 139020940779892)
	Ring = 90664669742250, -- wind_ring (package 71169891453451)
	Spiral = 115628997654552, -- wind_spiral (package 85431287904931)
}
local TEX = {
	Gradient = "rbxassetid://115854320689894", -- wind_gradient.png
	Streaks = "rbxassetid://83090249483866", -- wind_streaks.png
	Sparkle = "rbxassetid://76795312198770", -- sparkle.png
	Glow = "rbxassetid://134061496595746", -- soft_glow.png
	Wisp = "rbxassetid://115689752915482", -- wind_wisp.png
	Swirl = "rbxassetid://76836933588665", -- wind_swirl_flipbook.png (4x4 = 16 frames)
	Dust = "rbxassetid://119015403999595", -- dust_puff.png (shared with Pebble Toss)
}
local GRADIENT_ID = 115854320689894

local function numbers(...: number): NumberSequence
	local values = { ... }
	local points = {}
	for i = 1, #values, 2 do
		table.insert(points, NumberSequenceKeypoint.new(values[i], values[i + 1]))
	end
	return NumberSequence.new(points)
end

local function meshTemplate(name: string, meshId: number, parent: Instance)
	local part = AssetService:CreateMeshPartAsync(Content.fromAssetId(meshId))
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	part.DoubleSided = true
	part.Material = Enum.Material.SmoothPlastic
	part.Color = MAIN
	part.Transparency = 0
	local look = Instance.new("SurfaceAppearance")
	look.ColorMapContent = Content.fromAssetId(GRADIENT_ID)
	look.AlphaMode = Enum.AlphaMode.Transparency
	look.Color = MAIN
	look.EmissiveMaskContent = Content.fromAssetId(GRADIENT_ID)
	look.EmissiveTint = MAIN
	look.EmissiveStrength = 4
	look.Parent = part
	part:SetAttribute("Source", "Game/assets/" .. ({
		CrescentA = "wind_crescent_a",
		CrescentB = "wind_crescent_b",
		Ring = "wind_ring",
		Spiral = "wind_spiral",
	})[name] .. ".fbx")
	part.Parent = parent
end

local function emitter(name: string, props: { [string]: any }, parent: Instance)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Enabled = false
	e.Rate = 0
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Brightness = 1
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
end

local vfx = ReplicatedStorage:FindFirstChild("VFX")
if not vfx then
	vfx = Instance.new("Folder")
	vfx.Name = "VFX"
	vfx.Parent = ReplicatedStorage
end
local old = vfx:FindFirstChild("GaleStep")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "GaleStep"

for name, id in MESHES do
	meshTemplate(name, id, folder)
end

-- Diamond sparkles: small, face the camera, twinkle out.
emitter("Sparkle", {
	Texture = TEX.Sparkle,
	Color = ColorSequence.new(CORE, MAIN),
	Size = numbers(0, 0.35, 0.3, 0.45, 1, 0),
	Transparency = numbers(0, 0, 0.7, 0.1, 1, 1),
	Lifetime = NumberRange.new(0.4),
	Speed = NumberRange.new(0),
	Rotation = NumberRange.new(-15, 15),
	ZOffset = 1,
}, folder)

-- Thin wind slivers that line up with where they fly.
emitter("Wisp", {
	Texture = TEX.Wisp,
	Orientation = Enum.ParticleOrientation.VelocityParallel,
	Color = ColorSequence.new(CORE, MAIN),
	Size = numbers(0, 0.6, 0.4, 1.1, 1, 0.8),
	Transparency = numbers(0, 1, 0.15, 0.1, 0.7, 0.3, 1, 1),
	Lifetime = NumberRange.new(0.35, 0.5),
	Speed = NumberRange.new(10, 18),
	Drag = 3,
}, folder)

-- Swirl flipbook: 16 frames over its 0.5 s life (32 fps), plays once.
emitter("Swirl", {
	Texture = TEX.Swirl,
	FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
	FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
	FlipbookFramerate = NumberRange.new(32),
	FlipbookStartRandom = false,
	Color = ColorSequence.new(MAIN),
	Size = numbers(0, 6, 1, 6),
	Transparency = numbers(0, 0, 1, 0),
	Lifetime = NumberRange.new(0.5),
	Speed = NumberRange.new(0),
	Rotation = NumberRange.new(0, 360),
	ZOffset = 0.5,
}, folder)

-- One-frame chest flash.
emitter("Glow", {
	Texture = TEX.Glow,
	Color = ColorSequence.new(CORE),
	Size = numbers(0, 3, 1, 4),
	Transparency = numbers(0, 0.2, 1, 1),
	Lifetime = NumberRange.new(1 / 30),
	Speed = NumberRange.new(0),
	ZOffset = 2,
}, folder)

-- Small pale dust kick at the back foot (dust_puff tinted the core colour).
emitter("Dust", {
	Texture = TEX.Dust,
	Color = ColorSequence.new(CORE),
	LightEmission = 0.3,
	LightInfluence = 0.2,
	Size = numbers(0, 0.8, 1, 2),
	Transparency = numbers(0, 0.4, 0.5, 0.6, 1, 1),
	Lifetime = NumberRange.new(0.3, 0.4),
	Speed = NumberRange.new(4, 8),
	Drag = 5,
	SpreadAngle = Vector2.new(60, 20),
	Rotation = NumberRange.new(0, 360),
	RotSpeed = NumberRange.new(-60, 60),
}, folder)

local trail = Instance.new("Trail")
trail.Name = "Trail"
trail.Texture = TEX.Streaks
trail.TextureMode = Enum.TextureMode.Stretch
trail.Lifetime = 0.25
trail.WidthScale = numbers(0, 1, 1, 0)
trail.Color = ColorSequence.new(CORE, MAIN)
trail.Transparency = numbers(0, 0.1, 1, 1)
trail.LightEmission = 1
trail.LightInfluence = 0
trail.FaceCamera = true
trail.Enabled = false
trail.Parent = folder

local beam = Instance.new("Beam")
beam.Name = "Streak"
beam.Texture = TEX.Streaks
beam.TextureMode = Enum.TextureMode.Stretch
beam.TextureLength = 1
beam.FaceCamera = true
beam.Segments = 1
beam.Width0 = 0.5
beam.Width1 = 0.5
beam.Color = ColorSequence.new(CORE, EDGE)
beam.Transparency = numbers(0, 0.1, 1, 1)
beam.LightEmission = 1
beam.LightInfluence = 0
beam.Enabled = true
beam.Parent = folder

folder:SetAttribute("Palette", "#E9FBFF #7FE6FF #2FA8D8")
folder:SetAttribute("BuiltBy", "Game/tools/build_gale_step_templates.luau")
folder.Parent = vfx

local names = {}
for _, child in folder:GetChildren() do
	table.insert(names, `{child.Name} ({child.ClassName})`)
end
table.sort(names)
return "ReplicatedStorage.VFX.GaleStep: " .. table.concat(names, ", ")

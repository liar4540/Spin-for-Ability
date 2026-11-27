--!strict
-- Builds ReplicatedStorage.VFX.FrostBloom (run in Studio's Edit mode, e.g. through the Studio MCP).
-- Re-running replaces the folder. Every piece is a template: client/Abilities/FrostBloomVFX clones,
-- places and animates them; nothing here runs on its own. Tweak colours / sizes in Studio afterwards
-- if you like - the client script reads them from the templates, not from code.
--   Rune     36 x 36 stud disc (the AoE: radius 18) with the rune + a soft glow on a SurfaceGui
--   Pulse    flat ring that expands at full bloom
--   Mist     invisible square that carries every ground emitter (mist, motes, streaks, flakes)
--   PetalOuter / PetalInner / PetalCore   textured crystal meshes (Creator Store, see CRYSTAL_SOURCE), pivot at the base,
--            pointing up (+Y) closed; +Z is their outer (convex) side
-- Textures: Game/assets/vfx/_src/build_frost_bloom_textures.py

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TEX = {
	Rune = "rbxassetid://94608839020658",
	Glow = "rbxassetid://125847870568618",
	Flake = "rbxassetid://90676397522799",
	Sparkle = "rbxassetid://139943859945889",
	Mist = "rbxassetid://97151928278679",
	Ring = "rbxassetid://130368105005697",
}
local ICE = Color3.fromRGB(150, 215, 255) -- ice blue
local PALE = Color3.fromRGB(205, 240, 255) -- pale cyan
local WHITE = Color3.fromRGB(245, 252, 255)
local CRYSTAL = Color3.fromRGB(90, 190, 255) -- crystal blue

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

local function flatGui(part: BasePart, name: string): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = Enum.NormalId.Top
	gui.LightInfluence = 0
	gui.Brightness = 2.5
	gui.CanvasSize = Vector2.new(1024, 1024)
	gui.ClipsDescendants = false
	gui.Parent = part
	return gui
end

local function image(gui: Instance, name: string, tex: string, color: Color3, transparency: number, scale: number): ImageLabel
	local img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	img.Image = tex
	img.ImageColor3 = color
	img.ImageTransparency = transparency
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Position = UDim2.fromScale(0.5, 0.5)
	img.Size = UDim2.fromScale(scale, scale)
	img.Parent = gui
	return img
end

-- Petal crystal: free Creator Store MeshPart 1059108490 "Crystal" by Cobleth (mesh + its own ice texture,
-- no scripts), kept at ServerStorage.StoreMeshes.IceCrystal.
local storeMeshes = game:GetService("ServerStorage"):FindFirstChild("StoreMeshes")
local CRYSTAL_SOURCE = (storeMeshes and storeMeshes:FindFirstChild("IceCrystal")) :: MeshPart
assert(CRYSTAL_SOURCE and CRYSTAL_SOURCE:IsA("MeshPart"), "ServerStorage.StoreMeshes.IceCrystal is missing (insert Creator Store 1059108490)")

local function petal(name: string, length: number, width: number, widestAt: number, ridge: number): Model
	local model = Instance.new("Model")
	model.Name = name
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(0.2, 0.2, 0.2)
	base.Transparency = 1
	fx(base)
	base.CFrame = CFrame.new()
	base.Parent = model
	model.PrimaryPart = base

	-- The crystal itself: a textured crystal mesh from the Creator Store, stretched to the petal's length,
	-- standing on the pivot and pointing up (+Y). The hand-built wedge kites read as bland and fake.
	local crystal = CRYSTAL_SOURCE:Clone()
	crystal.Name = "Crystal"
	fx(crystal)
	local depth = width * CRYSTAL_SOURCE.Size.Z / CRYSTAL_SOURCE.Size.X
	crystal.Size = Vector3.new(width, length, depth)
	crystal.CFrame = CFrame.new(0, length / 2, ridge * 0.3)
	crystal.Color = WHITE
	crystal.Transparency = 0.05
	crystal.Parent = model
	local _ = widestAt
	model:SetAttribute("Length", length)
	return model
end

local function emitter(parent: Instance, name: string, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Enabled = false
	e.LockedToPart = false
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

local vfx = ReplicatedStorage:FindFirstChild("VFX") or Instance.new("Folder")
vfx.Name = "VFX"
vfx.Parent = ReplicatedStorage
local old = vfx:FindFirstChild("FrostBloom")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "FrostBloom"

-- Rune: the AoE circle (36 studs = radius 18)
local rune = Instance.new("Part")
rune.Name = "Rune"
rune.Size = Vector3.new(36, 0.1, 36)
rune.Transparency = 1
fx(rune)
local runeGui = flatGui(rune, "Gui")
image(runeGui, "Glow", TEX.Glow, CRYSTAL, 0.55, 0.75)
image(runeGui, "Rune", TEX.Rune, ICE, 0, 1)
local light = Instance.new("PointLight")
light.Name = "Light"
light.Color = ICE
light.Range = 18
light.Brightness = 0
light.Shadows = false
light.Parent = rune
rune.Parent = folder

-- Pulse ring at full bloom
local pulse = Instance.new("Part")
pulse.Name = "Pulse"
pulse.Size = Vector3.new(4, 0.1, 4)
pulse.Transparency = 1
fx(pulse)
image(flatGui(pulse, "Gui"), "Ring", TEX.Ring, WHITE, 0, 1)
pulse.Parent = folder

-- Ground emitters (Box shape on a 26 x 26 square)
local mist = Instance.new("Part")
mist.Name = "Mist"
mist.Size = Vector3.new(26, 0.2, 26) -- corners stay inside the 18-stud circle
mist.Transparency = 1
fx(mist)
emitter(mist, "Mist", {
	Texture = TEX.Mist,
	Shape = Enum.ParticleEmitterShape.Box, -- Disc is not laid flat: almost nothing emits
	ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	EmissionDirection = Enum.NormalId.Top,
	Color = ColorSequence.new(PALE),
	LightEmission = 0.35,
	LightInfluence = 0.2,
	Size = seq({ { 0, 5, 1 }, { 1, 10, 2 } }),
	Transparency = seq({ { 0, 1 }, { 0.25, 0.55 }, { 0.7, 0.7 }, { 1, 1 } }),
	Lifetime = NumberRange.new(2.4, 3.4),
	Rate = 28,
	Speed = NumberRange.new(0.4, 1.4),
	SpreadAngle = Vector2.new(70, 70),
	Drag = 1,
	Rotation = NumberRange.new(0, 360),
	RotSpeed = NumberRange.new(-12, 12),
})
emitter(mist, "Motes", {
	Texture = TEX.Sparkle,
	Shape = Enum.ParticleEmitterShape.Box, -- Disc is not laid flat: almost nothing emits
	ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	EmissionDirection = Enum.NormalId.Top,
	Color = ColorSequence.new(WHITE, ICE),
	LightEmission = 1,
	Brightness = 2,
	Size = seq({ { 0, 0 }, { 0.15, 0.45, 0.15 }, { 0.6, 0.3 }, { 1, 0 } }),
	Transparency = seq({ { 0, 0.1 }, { 1, 0.6 } }),
	Lifetime = NumberRange.new(1.4, 2.4),
	Rate = 22,
	Speed = NumberRange.new(1.5, 4),
	SpreadAngle = Vector2.new(25, 25),
	Acceleration = Vector3.new(0, 0.5, 0),
	Drag = 0.6,
})
emitter(mist, "Streaks", {
	Texture = TEX.Glow,
	Shape = Enum.ParticleEmitterShape.Box, -- Disc is not laid flat: almost nothing emits
	ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	EmissionDirection = Enum.NormalId.Top,
	Orientation = Enum.ParticleOrientation.FacingCameraWorldUp,
	Color = ColorSequence.new(WHITE, CRYSTAL),
	LightEmission = 1,
	Brightness = 2.5,
	Size = seq({ { 0, 0.5 }, { 1, 0.3 } }),
	Squash = seq({ { 0, 2.6 }, { 1, 2.6 } }),
	Transparency = seq({ { 0, 1 }, { 0.2, 0.15 }, { 1, 1 } }),
	Lifetime = NumberRange.new(0.35, 0.6),
	Rate = 0,
	Speed = NumberRange.new(9, 15),
	SpreadAngle = Vector2.new(3, 3),
})
emitter(mist, "Flakes", {
	Texture = TEX.Flake,
	Shape = Enum.ParticleEmitterShape.Box, -- Disc is not laid flat: almost nothing emits
	ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	EmissionDirection = Enum.NormalId.Top,
	Color = ColorSequence.new(WHITE, PALE),
	LightEmission = 0.8,
	Brightness = 1.5,
	Size = seq({ { 0, 0.35, 0.1 }, { 1, 0.15 } }),
	Transparency = seq({ { 0, 0.1 }, { 0.8, 0.3 }, { 1, 1 } }),
	Lifetime = NumberRange.new(1.6, 2.6),
	Rate = 0,
	Speed = NumberRange.new(2, 5),
	SpreadAngle = Vector2.new(35, 35),
	Acceleration = Vector3.new(0, -2, 0),
	Drag = 1.2,
	Rotation = NumberRange.new(0, 360),
	RotSpeed = NumberRange.new(-90, 90),
})
mist.Parent = folder

-- Petals per cast: 8 outer + 8 inner + 6 core (a closed bud in the middle)
petal("PetalOuter", 15, 6, 0.4, 0.6).Parent = folder
petal("PetalInner", 11, 4.8, 0.42, 0.5).Parent = folder
petal("PetalCore", 5, 2, 0.45, 0.3).Parent = folder

folder.Parent = vfx
return "built " .. #folder:GetChildren() .. " templates"

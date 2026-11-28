--!strict
-- SlashBlade: one blade of cutting light, pointed at both ends (Sever's grid, Altar of Ruin's slashes).
-- Three stacked ellipsoids sharing one CFrame:
--   Glow     dark crimson haze around it (Neon, see-through)
--   Outline  white-hot edge (Neon)
--   Core     black body, slightly deeper than the others so it shows on both faces
-- The blade's length runs along its local Y, its width along X, its thin depth along Z.
-- Move many blades with one workspace:BulkMoveTo (Parts + CFrames from SlashBlade.Collect).

local SlashBlade = {}

export type Blade = {
	Model: Model,
	Glow: BasePart,
	Outline: BasePart,
	Core: BasePart,
	GlowMesh: SpecialMesh,
	OutlineMesh: SpecialMesh,
	CoreMesh: SpecialMesh,
	Length: number,
	Width: number,
}

SlashBlade.GLOW = Color3.fromRGB(150, 10, 25)
SlashBlade.EDGE = Color3.fromRGB(255, 245, 240)
SlashBlade.CORE = Color3.fromRGB(8, 4, 6)

local function layer(parent: Instance, name: string, color: Color3, material: Enum.Material, transparency: number): (Part, SpecialMesh)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Size = Vector3.one
	part.Color = color
	part.Material = material
	part.Transparency = transparency
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.one
	mesh.Parent = part
	part.Parent = parent
	return part, mesh
end

function SlashBlade.new(parent: Instance, length: number, width: number): Blade
	local model = Instance.new("Model")
	model.Name = "Blade"
	local glow, glowMesh = layer(model, "Glow", SlashBlade.GLOW, Enum.Material.Neon, 0.55)
	local outline, outlineMesh = layer(model, "Outline", SlashBlade.EDGE, Enum.Material.Neon, 0)
	local core, coreMesh = layer(model, "Core", SlashBlade.CORE, Enum.Material.SmoothPlastic, 0)
	model.Parent = parent
	local blade: Blade = {
		Model = model,
		Glow = glow,
		Outline = outline,
		Core = core,
		GlowMesh = glowMesh,
		OutlineMesh = outlineMesh,
		CoreMesh = coreMesh,
		Length = length,
		Width = width,
	}
	SlashBlade.Shape(blade, 1, 0)
	return blade
end

-- grow = 0..1 of the full length (and a bit of width), fade = 0 (solid) .. 1 (gone)
function SlashBlade.Shape(blade: Blade, grow: number, fade: number)
	local l = blade.Length * grow
	local w = blade.Width * (0.4 + 0.6 * grow)
	blade.GlowMesh.Scale = Vector3.new(w * 3.2, l * 1.08, 0.1)
	blade.OutlineMesh.Scale = Vector3.new(w + 0.55, l * 1.03, 0.14)
	blade.CoreMesh.Scale = Vector3.new(w, l, 0.24)
	blade.Glow.Transparency = 0.55 + 0.45 * fade
	blade.Outline.Transparency = fade
	blade.Core.Transparency = fade
end

-- Adds this blade's three parts and `cframe` (for each) to the lists for one BulkMoveTo.
function SlashBlade.Collect(blade: Blade, cframe: CFrame, parts: { BasePart }, cframes: { CFrame })
	table.insert(parts, blade.Glow)
	table.insert(cframes, cframe)
	table.insert(parts, blade.Outline)
	table.insert(cframes, cframe)
	table.insert(parts, blade.Core)
	table.insert(cframes, cframe)
end

function SlashBlade.Move(blade: Blade, cframe: CFrame)
	blade.Glow.CFrame = cframe
	blade.Outline.CFrame = cframe
	blade.Core.CFrame = cframe
end

return SlashBlade

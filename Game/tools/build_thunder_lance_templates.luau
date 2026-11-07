--!strict
-- Thunder Lance: builds the mesh templates in ReplicatedStorage.VFX.ThunderLance (run in Studio, edit mode).
--
-- Run from the Studio command bar or the Studio MCP (needs plugin security, see below):
--     loadstring(<this file>)()        -- or paste it into the command bar
-- then save/publish the place. The templates are SAVED IN THE PLACE, like Frost Jab's: the ribbons and
-- the ring use a SurfaceAppearance, whose texture maps (ColorMapContent, EmissiveMaskContent) only
-- plugins/Studio can set. Colour, EmissiveStrength, Transparency, Size and CFrame stay scriptable, so
-- ThunderLanceVFX scales and fades clones at runtime. VFXTemplateService leaves this folder alone.
-- Emitters, beams, the trail, the light and the scorch decal are NOT templates: ThunderLanceVFX builds
-- them from its CONFIG (the one place their numbers live).
--
-- Sources: Game/assets/thunder_lance.blend + Game/assets/vfx/_src/build_thunder_lance_meshes.py /
-- build_thunder_lance_textures.py; ids from Game/assets/vfx/thunder_lance_assets.json
-- (upload_thunder_lance_assets.py); origin offsets from Game/assets/vfx/thunder_lance_meshes.json.
--
-- Contents (palette white #FFFDF0, yellow #FFE14D):
--   SpearCore  the lance: Neon, #FFFDF0 (prompt). Neon ignores textures, so its length fade is the
--              mesh's own taper; the soft glow edge is the inner Beam ThunderLanceVFX adds.
--   Ribbons    the crossed ribbons (double helix): glow_line.png along each ribbon (fades out at both
--              ends), #FFE14D, emissive, Transparency 0.2. Not Neon: Neon would drop that fade.
--   Ring       the shock ring: glow_line.png across the band (soft edges), #FFE14D, emissive, both sides.
-- Each carries OriginFromCentre (Vector3, studs: where the Blender origin - the spear's grip / the ring's
-- centre - sits from the mesh's bounding-box centre; Roblox centres imported meshes) and Source.
-- The spear and ribbons point along the part's LookVector (-Z), tip first.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetService = game:GetService("AssetService")

local WHITE, YELLOW = Color3.fromHex("#FFFDF0"), Color3.fromHex("#FFE14D")
local GLOW_LINE = 77325461611512 -- glow_line.png

local MESHES = {
	SpearCore = { Mesh = 74205448858788, Origin = Vector3.new(0, 0, 1), Source = "spear_core" },
	Ribbons = { Mesh = 137288918407462, Origin = Vector3.new(0, 0, 1), Source = "ribbon_helix" },
	Ring = { Mesh = 108495321187592, Origin = Vector3.zero, Source = "shock_ring" },
}

local function meshTemplate(name: string, spec: { Mesh: number, Origin: Vector3, Source: string }, parent: Instance)
	local part = AssetService:CreateMeshPartAsync(Content.fromAssetId(spec.Mesh))
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	if name == "SpearCore" then
		part.Material = Enum.Material.Neon
		part.Color = WHITE
	else
		part.Material = Enum.Material.SmoothPlastic
		part.Color = YELLOW
		part.DoubleSided = true -- thin ribbons / a flat ring: seen from both sides
		part.Transparency = if name == "Ribbons" then 0.2 else 0
		local look = Instance.new("SurfaceAppearance")
		look.ColorMapContent = Content.fromAssetId(GLOW_LINE)
		look.AlphaMode = Enum.AlphaMode.Transparency
		look.Color = YELLOW
		look.EmissiveMaskContent = Content.fromAssetId(GLOW_LINE)
		look.EmissiveTint = YELLOW
		look.EmissiveStrength = 6
		look.Parent = part
	end
	part:SetAttribute("OriginFromCentre", spec.Origin)
	part:SetAttribute("Source", `Game/assets/{spec.Source}.fbx`)
	part.Parent = parent
end

local vfx = ReplicatedStorage:FindFirstChild("VFX")
if not vfx then
	vfx = Instance.new("Folder")
	vfx.Name = "VFX"
	vfx.Parent = ReplicatedStorage
end
local old = vfx:FindFirstChild("ThunderLance")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "ThunderLance"

for name, spec in MESHES do
	meshTemplate(name, spec, folder)
end

folder:SetAttribute("Palette", "#FFFDF0 #FFE14D #FFB000 (+ #9FD8FF sparks, #4A3200 trail afterimage)")
folder:SetAttribute("BuiltBy", "Game/tools/build_thunder_lance_templates.luau")
folder.Parent = vfx

local names = {}
for _, child in folder:GetChildren() do
	local p = child :: MeshPart
	table.insert(names, `{child.Name} ({child.ClassName}, {math.round(p.Size.X * 100) / 100} x {math.round(p.Size.Y * 100) / 100} x {math.round(p.Size.Z * 100) / 100})`)
end
table.sort(names)
return "ReplicatedStorage.VFX.ThunderLance: " .. table.concat(names, ", ")

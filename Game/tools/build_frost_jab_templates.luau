--!strict
-- Frost Jab: builds the ice mesh templates in ReplicatedStorage.VFX.FrostJab (run in Studio, edit mode).
--
-- Run from the Studio command bar or the Studio MCP (needs plugin security, see below):
--     loadstring(<this file>)()        -- or paste it into the command bar
-- then save/publish the place. The templates are SAVED IN THE PLACE, like Gale Step's: each mesh
-- uses a SurfaceAppearance, and its texture maps (ColorMapContent, EmissiveMaskContent) can only be
-- set by plugins/Studio. Its Color, EmissiveTint, EmissiveStrength and the MeshPart's Transparency /
-- Size / CFrame ARE scriptable, so FrostJabVFX tints, scales and fades clones at runtime.
-- VFXTemplateService leaves this folder alone (it only rebuilds VFX.PebbleToss).
-- Particle emitters, the light and the frost highlight are NOT templates: FrostJabVFX builds them
-- from its CONFIG (the one place their numbers live).
--
-- Sources: Game/assets/frost_jab.blend + Game/assets/vfx/_src/build_frost_jab_meshes.py /
-- build_frost_jab_textures.py; ids from Game/assets/vfx/frost_jab_assets.json
-- (upload_frost_jab_assets.py).
--
-- Contents (white/grey textures, tinted with the palette below):
--   ShardA..ShardD   ice crystals (frost_shard.png along the length), lit + faint emissive, flat facets
--   Ring             flat ground ring (frost_ring.png: bright rim at the outer edge), emissive
--   Crown            ring of 12 ice spikes (frost_shard.png), lit + faint emissive
-- Each carries attributes OriginFromCentre (Vector3, studs: where the Blender origin, i.e. the shard
-- base / ring centre, sits from the mesh's bounding-box centre; Roblox centres imported meshes) and Source.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetService = game:GetService("AssetService")

local CORE, MAIN, DEEP = Color3.fromHex("#F2FBFF"), Color3.fromHex("#A8E6FF"), Color3.fromHex("#4FA3D9")

local TEX = {
	Shard = 110622299282904, -- frost_shard.png
	Ring = 77037636668101, -- frost_ring.png
}

-- template name -> mesh id (inside the uploaded FBX model package), texture, origin offset, source
local MESHES = {
	ShardA = { Mesh = 74767379733751, Tex = TEX.Shard, Origin = Vector3.new(-0.0116, -0.8, -0.0255), Source = "ice_shard_a" },
	ShardB = { Mesh = 83748209218763, Tex = TEX.Shard, Origin = Vector3.new(0.0172, -0.55, 0.013), Source = "ice_shard_b" },
	ShardC = { Mesh = 131712182637805, Tex = TEX.Shard, Origin = Vector3.new(-0.01, -1.0, -0.007), Source = "ice_shard_c" },
	ShardD = { Mesh = 124088321679540, Tex = TEX.Shard, Origin = Vector3.new(-0.0183, -0.675, 0.0157), Source = "ice_shard_d" },
	Ring = { Mesh = 101229161717226, Tex = TEX.Ring, Origin = Vector3.zero, Source = "frost_ring" },
	Crown = { Mesh = 128961005325770, Tex = TEX.Shard, Origin = Vector3.new(0.052, -0.4347, -0.1121), Source = "frost_crown" },
}

local function meshTemplate(name: string, spec: { Mesh: number, Tex: number, Origin: Vector3, Source: string }, parent: Instance)
	local part = AssetService:CreateMeshPartAsync(Content.fromAssetId(spec.Mesh))
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	part.DoubleSided = name == "Ring"
	part.Material = Enum.Material.SmoothPlastic
	part.Color = MAIN
	part.Transparency = 0
	local look = Instance.new("SurfaceAppearance")
	look.ColorMapContent = Content.fromAssetId(spec.Tex)
	look.AlphaMode = Enum.AlphaMode.Transparency
	look.Color = if name == "Ring" then MAIN else CORE
	look.EmissiveMaskContent = Content.fromAssetId(spec.Tex)
	look.EmissiveTint = MAIN
	look.EmissiveStrength = if name == "Ring" then 4 else 0.6 -- the ring glows; crystals stay lit/faceted
	look.Parent = part
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
local old = vfx:FindFirstChild("FrostJab")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "FrostJab"

for name, spec in MESHES do
	meshTemplate(name, spec, folder)
end

folder:SetAttribute("Palette", "#F2FBFF #A8E6FF #4FA3D9")
folder:SetAttribute("BuiltBy", "Game/tools/build_frost_jab_templates.luau")
folder.Parent = vfx

local names = {}
for _, child in folder:GetChildren() do
	local p = child :: MeshPart
	table.insert(names, `{child.Name} ({child.ClassName}, {math.round(p.Size.X * 100) / 100} x {math.round(p.Size.Y * 100) / 100} x {math.round(p.Size.Z * 100) / 100})`)
end
table.sort(names)
return "ReplicatedStorage.VFX.FrostJab: " .. table.concat(names, ", ")

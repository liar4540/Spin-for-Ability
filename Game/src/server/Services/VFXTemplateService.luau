--!strict
-- VFXTemplateService: builds the mesh templates the client VFX clone, in ReplicatedStorage.VFX.
-- Pebble Toss: Rock + Chip1..5 in ReplicatedStorage.VFX.PebbleToss, carved from the Blender shapes
-- (Shared/Config/PebbleTossMeshes) with CSG: start from a block, cut away everything outside each
-- face's plane. Same faceted shape as the FBX in Game/assets, without a mesh upload.
-- Rebuilt at every server start so the shapes always match the source data.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local PebbleTossMeshes = require(Config:WaitForChild("PebbleTossMeshes"))

local ROCK_COLOR = Color3.fromHex("#8A8A90")
local CUTTER_SIZE = 4 -- studs; far bigger than any shape
local SAME_PLANE = 0.9995 -- normals this close (and offsets within 0.001) are one face

local VFXTemplateService = {}

type Plane = { Normal: Vector3, Offset: number }

local function planesOf(mesh: PebbleTossMeshes.MeshData): { Plane }
	local function vertex(index: number): Vector3
		local v = mesh.Verts[index + 1]
		return Vector3.new(v[1], v[2], v[3])
	end
	local planes: { Plane } = {}
	for _, tri in mesh.Tris do
		local a, b, c = vertex(tri[1]), vertex(tri[2]), vertex(tri[3])
		local normal = (b - a):Cross(c - a).Unit
		if normal:Dot(a) < 0 then
			normal = -normal -- shapes are convex and centred, so outward points away from the origin
		end
		local offset = normal:Dot(a)
		local duplicate = false
		for _, plane in planes do
			if plane.Normal:Dot(normal) > SAME_PLANE and math.abs(plane.Offset - offset) < 1e-3 then
				duplicate = true
				break
			end
		end
		if not duplicate then
			table.insert(planes, { Normal = normal, Offset = offset })
		end
	end
	return planes
end

-- Carve one convex shape at the world origin. Returns nil (and warns) if CSG fails.
local function carve(name: string, mesh: PebbleTossMeshes.MeshData, parent: Instance): UnionOperation?
	local block = Instance.new("Part")
	block.Size = Vector3.one
	block.CFrame = CFrame.identity
	block.Anchored = true
	local cutters = {}
	for _, plane in planesOf(mesh) do
		local cutter = Instance.new("Part")
		cutter.Size = Vector3.one * CUTTER_SIZE
		local centre = plane.Normal * (plane.Offset + CUTTER_SIZE / 2)
		cutter.CFrame = CFrame.lookAt(centre, centre + plane.Normal)
		table.insert(cutters, cutter)
	end
	block.Parent = workspace -- CSG needs the base part in the world
	local ok, result = pcall(function()
		return block:SubtractAsync(cutters, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Precise)
	end)
	block:Destroy()
	for _, cutter in cutters do
		cutter:Destroy()
	end
	if not ok then
		warn(`[VFXTemplateService] could not carve {name}: {result}`)
		return nil
	end
	local union = result :: UnionOperation
	union.Name = name
	union.UsePartColor = true
	union.Color = ROCK_COLOR
	union.Material = Enum.Material.SmoothPlastic
	-- Flat shading comes from the default SmoothingAngle (0); a live server may not set it.
	union.Anchored = true
	union.CanCollide = false
	union.CanTouch = false
	union.CanQuery = false
	union.CastShadow = false
	union.Massless = true
	union.Parent = parent
	return union
end

function VFXTemplateService.BuildPebbleToss(): Folder
	local vfx = ReplicatedStorage:FindFirstChild("VFX")
	if not vfx then
		vfx = Instance.new("Folder")
		vfx.Name = "VFX"
		vfx.Parent = ReplicatedStorage
	end
	local old = vfx:FindFirstChild("PebbleToss")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "PebbleToss"
	for name, mesh in PebbleTossMeshes do
		carve(name, mesh, folder)
	end
	folder.Parent = vfx
	return folder
end

function VFXTemplateService.Init()
	VFXTemplateService.BuildPebbleToss()
end

function VFXTemplateService.Start() end

return VFXTemplateService

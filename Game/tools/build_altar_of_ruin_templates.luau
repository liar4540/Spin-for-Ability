--!strict
-- Builds ReplicatedStorage.VFX.AltarOfRuin (run in Studio's Edit mode, e.g. through the Studio MCP).
-- Re-running replaces the folder. client/Abilities/AltarOfRuinVFX clones these; nothing here runs on its own.
-- Sources (added by the user in Studio, kept script-free in ServerStorage.StoreSources):
--   AltarShrine      the shrine model that rises behind the caster
--   AltarSlashField  a big invisible part whose ParticleEmitters are the slash storm; its two Sounds are
--                    the cast line (played on the key press) and the track (played while the slashes run)
-- Templates:
--   Altar        the shrine: anchored, no collisions or queries, its own lights / emitters kept, no sounds
--   SlashField   the emitter part: every emitter off (the client switches them on), resized at run time
--   Sounds       Cast (key press), Loop (while the slashes run)
--   HitEffect    the user's hit burst (StoreSources.AltarHitEffect), played on enemies inside
-- Every emitter is switched off here. The attribute "Always" = true marks the ones that were on in the
-- source (they run while the slashes run); the others are bursts (fired with :Emit(EmitCount)).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local sources = ServerStorage:FindFirstChild("StoreSources")
local shrine = sources and sources:FindFirstChild("AltarShrine")
local field = sources and sources:FindFirstChild("AltarSlashField")
assert(shrine and shrine:IsA("Model"), "ServerStorage.StoreSources.AltarShrine is missing")
assert(field and field:IsA("BasePart"), "ServerStorage.StoreSources.AltarSlashField is missing")

local vfx = ReplicatedStorage:FindFirstChild("VFX") or Instance.new("Folder")
vfx.Name = "VFX"
vfx.Parent = ReplicatedStorage
local old = vfx:FindFirstChild("AltarOfRuin")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "AltarOfRuin"

local function quiet(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
end

-- Altar
local altar = shrine:Clone()
altar.Name = "Altar"
for _, d in altar:GetDescendants() do
	if d:IsA("LuaSourceContainer") or d:IsA("Sound") then
		d:Destroy()
	elseif d:IsA("BasePart") then
		quiet(d)
	end
end
-- pivot at the bottom centre, so the client can stand it on the ground
local cf, size = altar:GetBoundingBox()
altar.WorldPivot = CFrame.new(cf.Position - Vector3.new(0, size.Y / 2, 0)) * cf.Rotation
altar.Parent = folder

-- Slash field + its sounds
local sounds = Instance.new("Folder")
sounds.Name = "Sounds"
local slashField = field:Clone()
slashField.Name = "SlashField"
quiet(slashField)
slashField.Transparency = 1
-- emitters: remember which were on (continuous) vs off (bursts), then switch all off
local function prepareEmitters(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		elseif d:IsA("ParticleEmitter") then
			d:SetAttribute("Always", d.Enabled)
			d.Enabled = false
		end
	end
end
prepareEmitters(slashField)
local castSound: Sound? = nil
local loopSound: Sound? = nil
for _, d in field:GetDescendants() do
	if d:IsA("Sound") then
		if d.Parent == field then
			castSound = d -- the short line, straight on the part
		else
			loopSound = d -- the long track, nested under it
		end
	end
end
for _, d in slashField:GetDescendants() do
	if d:IsA("Sound") then
		d:Destroy()
	end
end
slashField.Parent = folder
if castSound then
	local s = Instance.new("Sound")
	s.Name = "Cast"
	s.SoundId = castSound.SoundId
	s.Volume = castSound.Volume
	s.Parent = sounds
end
if loopSound then
	local s = Instance.new("Sound")
	s.Name = "Loop"
	s.SoundId = loopSound.SoundId
	s.Volume = loopSound.Volume
	s.Parent = sounds
end
sounds.Parent = folder

-- Hit effect
local hitSource = sources:FindFirstChild("AltarHitEffect")
if hitSource and hitSource:IsA("BasePart") then
	local hit = hitSource:Clone()
	hit.Name = "HitEffect"
	quiet(hit)
	hit.Transparency = 1
	prepareEmitters(hit)
	for _, d in hit:GetDescendants() do
		if d:IsA("Sound") then
			d:Destroy()
		end
	end
	hit.Parent = folder
end

folder.Parent = vfx
return `built AltarOfRuin: altar {math.floor(size.Y)} studs tall, {#slashField:GetChildren()} field children, sounds: {#sounds:GetChildren()}`

--!strict
-- Builds ReplicatedStorage.VFX.StarCannon (run in Studio's Edit mode; sync it in as a temporary
-- ModuleScript and require it, like the Blood Moon builder). Re-running replaces the folder.
-- client/Abilities/StarCannonVFX clones, places and times these; tweak them in Studio freely.
--   Orb          the star between the palms: white-hot ball + gold glow, a turning 4-point flare,
--                sparks drawn in, a light; 3 Rings (flat, both faces) spin round it on different axes
--   Aura         v3: the user's Creator Store aura (StoreSources.SaiyanAura) recoloured gold, as one
--                Folder of emitters per body part; Ground under the feet: lifting dust, spinning rings;
--                Ribbon = a trail the script spirals up the body; Rock = a store rock mesh it levitates
--   Beam         v3: the user's Creator Store beam (StoreSources.KamehamehaBeam) recoloured gold and
--                scaled 1.5x; the script stretches it to the real length. Sparks = a box along the
--                beam; Muzzle = the light at the hands
--   Coil         a thin BLUE line (Trail) the script spirals round the beam (user request)
--   TravelRing   the big energy ring that runs down the beam (pooled)
--   Impact       where the beam meets a wall / on each enemy hit
--   Sounds       Charge, Release, Loop, Rumble, Hit;  CastAnimation (from StarCannonKeyframes)
-- Textures: Game/assets/vfx/_src/build_star_cannon_textures.py + shared glow / sparkle / flame / smoke.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local TEX = {
	Soft = "rbxassetid://78770175955033",
	Flow = "rbxassetid://99537022800713",
	Ring = "rbxassetid://88803161682130",
	Glow = "rbxassetid://125847870568618",
	Sparkle = "rbxassetid://139943859945889", -- 4-point star
	Flame = "rbxassetid://136572725019318", -- 4x4 flipbook
	Smoke = "rbxassetid://114965428672642", -- 4x4 flipbook
	Wisp = "rbxassetid://83953606813781",
	-- beam layers use the *_beam copies, turned 90 degrees: on a Beam the image's vertical axis runs
	-- along the beam (left-right streaks showed as bars across it)
	SoftBeam = "rbxassetid://84034366441002",
	FlowBeam = "rbxassetid://75988274168338",
	Plasma = "rbxassetid://99197618070252", -- v2 beam body
	Rim = "rbxassetid://128576546261355", -- v2 beam outline lines
	Veins = "rbxassetid://81948472054498", -- dark streaks
	Line = "rbxassetid://105743535803213", -- thin bright line (shared with Blood Moon): the blue coils
}
local SOUNDS = {
	Charge = { "rbxassetid://9114343926", 0.8, 0.7 }, -- Energy Presence 4 (Pro Sound Effects); pitch rises while charging
	Release = { "rbxassetid://9114156829", 1, 0.9 }, -- Doppler Whooshes Crackly Airy Bursts 2 (Pro Sound Effects)
	Loop = { "rbxassetid://9114339706", 0.8, 1 }, -- Energy Pass Bys 9 (Pro Sound Effects): the beam hum
	Rumble = { "rbxassetid://9114344093", 0.9, 0.7 }, -- Energy Presence 8 (Pro Sound Effects), low
	Hit = { "rbxassetid://108257794693139", 0.6, 1.2 }, -- Impact (6)
}
local WHITE = Color3.fromRGB(255, 252, 238)
local PALE = Color3.fromRGB(255, 236, 170) -- pale gold
local GOLD = Color3.fromRGB(255, 205, 60)
local YELLOW = Color3.fromRGB(255, 225, 90)
local AMBER = Color3.fromRGB(205, 140, 20)
local DUST = Color3.fromRGB(120, 100, 70)

local function fx(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
end

-- The store aura and beam are blue: turn every value gold, keeping its brightness, so dark navy
-- becomes dark amber and blue becomes yellow. minSat lifts pale tints (pale yellow read as white in
-- daylight, the old washout lesson); grey tints on effects (the beam's sky swooshes) become pale gold.
local GOLD_HUE = 0.13
local BEAM_WIDTH_SCALE = 1.5 -- the store beam is ~8 wide; Star Cannon hits a 12-wide strip
local AURA_MIN_SAT = 0.8 -- the aura reads yellow, not white, in daylight
local function goldOf(c: Color3, minSat: number, tintGrey: boolean): Color3
	local _, sat, val = c:ToHSV()
	if sat < 0.08 then
		if not tintGrey or val < 0.05 then
			return c
		end
		return Color3.fromHSV(GOLD_HUE, 0.55, math.min(1, val * 1.6))
	end
	return Color3.fromHSV(GOLD_HUE, math.max(sat, minSat), val)
end
local function recolour(root: Instance, minSat: number?)
	local all = root:GetDescendants()
	table.insert(all, root)
	local floor = minSat or 0
	for _, d in all do
		if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
			local keys = {}
			for _, k in ((d :: any).Color :: ColorSequence).Keypoints do
				table.insert(keys, ColorSequenceKeypoint.new(k.Time, goldOf(k.Value, floor, true)))
			end
			(d :: any).Color = ColorSequence.new(keys)
		elseif d:IsA("BasePart") then
			d.Color = goldOf(d.Color, floor, false)
		elseif d:IsA("Light") then
			d.Color = goldOf(d.Color, floor, false)
		end
	end
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

local function part(name: string, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Transparency = 1
	fx(p)
	return p
end

local function light(parent: Instance, range: number)
	local l = Instance.new("PointLight")
	l.Name = "Light"
	l.Color = GOLD
	l.Range = range
	l.Brightness = 0
	l.Shadows = false
	l.Parent = parent
end

-- A flat ring visible from both sides (SurfaceGuis on Top and Bottom).
local function ringPart(name: string, size: number, color: Color3, brightness: number?): Part
	local p = part(name, Vector3.new(size, 0.05, size))
	for _, face in { Enum.NormalId.Top, Enum.NormalId.Bottom } do
		local gui = Instance.new("SurfaceGui")
		gui.Name = face.Name
		gui.Face = face
		gui.LightInfluence = 0
		gui.Brightness = brightness or 3
		gui.CanvasSize = Vector2.new(512, 512)
		gui.Parent = p
		local img = Instance.new("ImageLabel")
		img.Name = "Image"
		img.BackgroundTransparency = 1
		img.Image = TEX.Ring
		img.ImageColor3 = color
		img.Size = UDim2.fromScale(1, 1)
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Parent = gui
	end
	return p
end

local vfx = ReplicatedStorage:FindFirstChild("VFX") or Instance.new("Folder")
vfx.Name = "VFX"
vfx.Parent = ReplicatedStorage
local old = vfx:FindFirstChild("StarCannon")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "StarCannon"

-- ===== Orb =====
local orb = Instance.new("Part")
orb.Name = "Orb"
orb.Shape = Enum.PartType.Ball
orb.Material = Enum.Material.Neon
orb.Color = WHITE
orb.Size = Vector3.new(0.3, 0.3, 0.3)
fx(orb)
emitter(orb, "Glow", {
	Texture = TEX.Glow,
	Color = colors({ { 0, WHITE }, { 0.4, YELLOW }, { 1, GOLD } }),
	LightEmission = 1,
	Brightness = 3,
	LockedToPart = true,
	Size = seq({ { 0, 2.5 }, { 1, 4 } }),
	Transparency = seq({ { 0, 0.3 }, { 1, 1 } }),
	Lifetime = NumberRange.new(0.25, 0.4),
	Rate = 30,
	Speed = NumberRange.new(0),
})
emitter(orb, "Flare", {
	Texture = TEX.Sparkle,
	Color = colors({ { 0, WHITE }, { 1, PALE } }),
	LightEmission = 1,
	Brightness = 4,
	LockedToPart = true,
	Size = seq({ { 0, 3 }, { 0.5, 5 }, { 1, 3 } }),
	Transparency = seq({ { 0, 0.2 }, { 1, 1 } }),
	Lifetime = NumberRange.new(0.3),
	Rate = 8,
	Speed = NumberRange.new(0),
	Rotation = NumberRange.new(0, 90),
	RotSpeed = NumberRange.new(60, 120),
	ZOffset = 1,
})
emitter(orb, "Gather", {
	Texture = TEX.Glow,
	Shape = Enum.ParticleEmitterShape.Sphere,
	ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
	Color = colors({ { 0, PALE }, { 1, WHITE } }),
	LightEmission = 1,
	Brightness = 3,
	Size = seq({ { 0, 0 }, { 0.5, 0.25 }, { 1, 0 } }),
	Squash = seq({ { 0, 1.5 }, { 1, 1.5 } }),
	Orientation = Enum.ParticleOrientation.VelocityParallel,
	Lifetime = NumberRange.new(0.25, 0.45),
	Rate = 60,
	Speed = NumberRange.new(6, 10),
	ZOffset = 0.5,
})
light(orb, 14)
orb.Parent = folder
for i = 1, 3 do
	ringPart(`OrbRing{i}`, 3, if i == 2 then WHITE else GOLD).Parent = folder
end

-- ===== Aura (v3, user request): the user's Creator Store aura "ui goku" (kept at
-- ServerStorage.StoreSources.SaiyanAura, no scripts), recoloured gold. One Folder per R15 body part
-- the script parents its emitters into (the source is R6: Torso -> UpperTorso, legs -> upper legs);
-- RootAttachments = the rising foot flames + dots, as Attachments on the HumanoidRootPart. The source's
-- "SSJ Aura" emitters (disabled, Rate 1e9) and the hair mesh are left out.
local storeSources = ServerStorage:FindFirstChild("StoreSources")
local auraSource = storeSources and storeSources:FindFirstChild("SaiyanAura")
assert(auraSource, "ServerStorage.StoreSources.SaiyanAura is missing (the Creator Store aura)")
local aura = Instance.new("Folder")
aura.Name = "Aura"
local R15 = { Head = "Head", Torso = "UpperTorso", ["Left Leg"] = "LeftUpperLeg", ["Right Leg"] = "RightUpperLeg" }
for r6, r15 in R15 do
	local bodyPart = auraSource:FindFirstChild(r6)
	if bodyPart then
		local slot = Instance.new("Folder")
		slot.Name = r15
		for _, e in bodyPart:GetChildren() do
			if (e:IsA("ParticleEmitter") and e.Name ~= "SSJ Aura") or e:IsA("PointLight") then
				local copy = e:Clone()
				recolour(copy, AURA_MIN_SAT)
				copy.Enabled = false
				copy.Parent = slot
			end
		end
		slot.Parent = aura
	end
end
local rootSlot = Instance.new("Folder")
rootSlot.Name = "HumanoidRootPart"
local torso = auraSource:FindFirstChild("Torso") :: BasePart
local mystical = torso and torso:FindFirstChild("mystical aura")
local handle = mystical and mystical:FindFirstChild("Handle")
if handle then
	for _, a in handle:GetChildren() do
		if a:IsA("Attachment") and a:FindFirstChildWhichIsA("ParticleEmitter") then
			local copy = Instance.new("Attachment")
			copy.Name = a.Name
			copy.Position = torso.CFrame:PointToObjectSpace(a.WorldPosition) -- R6 torso centre = root
			for _, e in a:GetChildren() do
				if e:IsA("ParticleEmitter") then
					local ec = e:Clone()
					recolour(ec, AURA_MIN_SAT)
					ec.Enabled = false
					ec.Parent = copy
				end
			end
			copy.Parent = rootSlot
		end
	end
end
rootSlot.Parent = aura
aura.Parent = folder

local ground = ringPart("Ground", 9, GOLD)
emitter(ground, "Dust", { -- wind pushing outward, dust lifting
	Texture = TEX.Smoke,
	FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
	FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
	Shape = Enum.ParticleEmitterShape.Box,
	EmissionDirection = Enum.NormalId.Top,
	Color = colors({ { 0, DUST }, { 1, Color3.fromRGB(150, 130, 100) } }),
	LightEmission = 0,
	LightInfluence = 0.8,
	Size = seq({ { 0, 1.5 }, { 1, 4 } }),
	Transparency = seq({ { 0, 0.55 }, { 1, 1 } }),
	Lifetime = NumberRange.new(0.6, 1.0),
	Rate = 20,
	Speed = NumberRange.new(4, 8),
	SpreadAngle = Vector2.new(80, 80),
	Drag = 2,
})
emitter(ground, "Debris", { -- small grit flicking up
	Texture = TEX.Glow,
	Shape = Enum.ParticleEmitterShape.Box,
	EmissionDirection = Enum.NormalId.Top,
	Color = ColorSequence.new(Color3.fromRGB(70, 60, 45)),
	LightEmission = 0,
	Size = seq({ { 0, 0.18 }, { 1, 0.12 } }),
	Lifetime = NumberRange.new(0.6, 1.1),
	Rate = 25,
	Speed = NumberRange.new(4, 9),
	SpreadAngle = Vector2.new(40, 40),
	Acceleration = Vector3.new(0, -18, 0),
})
ground.Parent = folder

local ribbon = part("Ribbon", Vector3.new(0.2, 0.2, 0.2))
local r0 = Instance.new("Attachment")
r0.Name = "A0"
r0.Position = Vector3.new(0, 0.3, 0)
r0.Parent = ribbon
local r1 = Instance.new("Attachment")
r1.Name = "A1"
r1.Position = Vector3.new(0, -0.3, 0)
r1.Parent = ribbon
local trail = Instance.new("Trail")
trail.Name = "Trail"
trail.Attachment0 = r0
trail.Attachment1 = r1
trail.Texture = TEX.Wisp
trail.TextureMode = Enum.TextureMode.Stretch
trail.FaceCamera = true
trail.Color = colors({ { 0, WHITE }, { 0.4, YELLOW }, { 1, GOLD } })
trail.LightEmission = 1
trail.Brightness = 3
trail.Transparency = seq({ { 0, 0.1 }, { 1, 1 } })
trail.Lifetime = 0.35
trail.Enabled = false
trail.Parent = ribbon
ribbon.Parent = folder

-- Rock: a faceted low-poly rock mesh (free Creator Store MeshPart 2557003106 "Rock" by FWS_Sinister,
-- mesh only, kept at ServerStorage.StoreMeshes.Rock). Box parts read as cardboard.
local rockSource = game:GetService("ServerStorage"):FindFirstChild("StoreMeshes")
rockSource = rockSource and rockSource:FindFirstChild("Rock")
assert(rockSource and rockSource:IsA("MeshPart"), "ServerStorage.StoreMeshes.Rock is missing (insert Creator Store 2557003106)")
local rock = rockSource:Clone()
rock.Name = "Rock"
rock.Material = Enum.Material.Basalt
rock.Color = Color3.fromRGB(58, 54, 50)
rock.Size = Vector3.new(0.6, 0.45, 0.55)
fx(rock)
rock.CastShadow = true
rock.Parent = folder

-- ===== Beam (v3, user request): the user's Creator Store "Ultimate Kamehameha" (kept at
-- ServerStorage.StoreSources.KamehamehaBeam, no scripts), recoloured gold and scaled to Star Cannon's
-- width. PrimaryPart Origin sits at the hands with its LookVector along the beam; the script stretches
-- it to the real length every frame (parts tagged Stretch are the long tubes; attachments past the
-- muzzle slide along). Attribute Length = its built length.
local beamSource = storeSources and storeSources:FindFirstChild("KamehamehaBeam")
assert(beamSource, "ServerStorage.StoreSources.KamehamehaBeam is missing (the Creator Store beam)")
local beam = beamSource:Clone()
beam.Name = "Beam"
local start = beam:FindFirstChild("Start") :: BasePart
local origin = Instance.new("Part")
origin.Name = "Origin"
origin.Size = Vector3.new(0.2, 0.2, 0.2)
origin.Transparency = 1
origin.CFrame = start.CFrame * CFrame.Angles(math.rad(-90), 0, 0) -- the source beam runs down Start's -Y
origin.Parent = beam
beam.PrimaryPart = origin
local tubes = beam:FindFirstChild("Beam")
for _, d in beam:GetDescendants() do
	if d:IsA("LuaSourceContainer") then
		d:Destroy()
	elseif d:IsA("BasePart") then
		fx(d)
		local isTube = d:IsA("MeshPart") and tubes ~= nil and d.Parent == tubes
		d:SetAttribute("Stretch", isTube or nil)
		if not isTube then
			d.Transparency = 1
		end
	elseif d:IsA("ParticleEmitter") then
		d.Enabled = false
	end
end
recolour(beam)
beam:PivotTo(CFrame.new())
beam:ScaleTo(beam:GetScale() * BEAM_WIDTH_SCALE) -- the source already carries its own scale factor
local far = 0
for _, d in beam:GetDescendants() do
	if d:IsA("Attachment") then
		far = math.max(far, -d.WorldPosition.Z)
	end
end
beam:SetAttribute("Length", far)
beam.Parent = folder

local beamSparks = part("Sparks", Vector3.new(6, 6, 20))
emitter(beamSparks, "Sparks", {
	Texture = TEX.Glow,
	Shape = Enum.ParticleEmitterShape.Box,
	Color = colors({ { 0, WHITE }, { 1, GOLD } }),
	LightEmission = 1,
	Brightness = 3,
	Size = seq({ { 0, 0.3 }, { 1, 0 } }),
	Squash = seq({ { 0, 1.8 }, { 1, 0.8 } }),
	Orientation = Enum.ParticleOrientation.VelocityParallel,
	Lifetime = NumberRange.new(0.25, 0.5),
	Rate = 60, -- 160 read as vertical rain along the beam
	Speed = NumberRange.new(8, 16),
	SpreadAngle = Vector2.new(180, 180),
	Drag = 3,
})
emitter(beamSparks, "Motes", {
	Texture = TEX.Sparkle,
	Shape = Enum.ParticleEmitterShape.Box,
	Color = colors({ { 0, WHITE }, { 1, PALE } }),
	LightEmission = 1,
	Brightness = 3,
	Size = seq({ { 0, 0 }, { 0.2, 0.6 }, { 1, 0 } }),
	Lifetime = NumberRange.new(0.5, 1),
	Rate = 40,
	Speed = NumberRange.new(1, 3),
	SpreadAngle = Vector2.new(180, 180),
	RotSpeed = NumberRange.new(-120, 120),
})
beamSparks.Parent = folder

-- Muzzle: just the light at the hands now (the store beam brings its own muzzle burst)
local muzzle = part("Muzzle", Vector3.new(1, 1, 1))
light(muzzle, 16)
muzzle.Parent = folder

-- Coil: a thin blue line spiralling round the beam
local coil = part("Coil", Vector3.new(0.2, 0.2, 0.2))
local c0 = Instance.new("Attachment")
c0.Name = "A0"
c0.Position = Vector3.new(0, 0.22, 0)
c0.Parent = coil
local c1 = Instance.new("Attachment")
c1.Name = "A1"
c1.Position = Vector3.new(0, -0.22, 0)
c1.Parent = coil
local coilTrail = Instance.new("Trail")
coilTrail.Name = "Trail"
coilTrail.Attachment0 = c0
coilTrail.Attachment1 = c1
coilTrail.Texture = TEX.Line
coilTrail.TextureMode = Enum.TextureMode.Stretch
coilTrail.FaceCamera = true
coilTrail.Color = colors({ { 0, Color3.fromRGB(190, 230, 255) }, { 0.25, Color3.fromRGB(60, 150, 255) }, { 1, Color3.fromRGB(30, 80, 255) } }) -- deeper blue: paler read washed against the gold
coilTrail.LightEmission = 1
coilTrail.Brightness = 3
coilTrail.Transparency = seq({ { 0, 0 }, { 0.7, 0.4 }, { 1, 1 } })
coilTrail.WidthScale = seq({ { 0, 1 }, { 1, 0.3 } })
coilTrail.Lifetime = 0.3
coilTrail.Enabled = false
coilTrail.Parent = coil
emitter(coil, "Sparkles", {
	Texture = TEX.Sparkle,
	Color = colors({ { 0, Color3.fromRGB(220, 245, 255) }, { 1, Color3.fromRGB(90, 160, 255) } }),
	LightEmission = 1,
	Brightness = 3,
	Size = seq({ { 0, 0.5 }, { 1, 0 } }),
	Lifetime = NumberRange.new(0.2, 0.4),
	Rate = 25,
	Speed = NumberRange.new(0.5, 2),
	SpreadAngle = Vector2.new(180, 180),
})
coil.Parent = folder

ringPart("TravelRing", 14, Color3.fromRGB(255, 200, 70), 1.5).Parent = folder -- gold reads on the beam; white vanished

-- ===== Impact =====
local impact = part("Impact", Vector3.new(3, 3, 3))
emitter(impact, "Flash", {
	Texture = TEX.Glow,
	Color = colors({ { 0, WHITE }, { 1, YELLOW } }),
	LightEmission = 1,
	Brightness = 5,
	Size = seq({ { 0, 6 }, { 1, 10 } }),
	Transparency = seq({ { 0, 0.1 }, { 1, 1 } }),
	Lifetime = NumberRange.new(0.15, 0.25),
	Speed = NumberRange.new(0),
	ZOffset = 1,
})
emitter(impact, "Ring", {
	Texture = TEX.Ring,
	Color = colors({ { 0, WHITE }, { 1, GOLD } }),
	LightEmission = 1,
	Brightness = 3,
	Size = seq({ { 0, 2 }, { 1, 14 } }),
	Transparency = seq({ { 0, 0.1 }, { 1, 1 } }),
	Lifetime = NumberRange.new(0.35, 0.5),
	Speed = NumberRange.new(0),
	Rotation = NumberRange.new(0, 360),
})
emitter(impact, "Sparks", {
	Texture = TEX.Glow,
	Color = colors({ { 0, WHITE }, { 1, GOLD } }),
	LightEmission = 1,
	Brightness = 4,
	Size = seq({ { 0, 0.35 }, { 1, 0 } }),
	Squash = seq({ { 0, 2 }, { 1, 1 } }),
	Orientation = Enum.ParticleOrientation.VelocityParallel,
	Lifetime = NumberRange.new(0.3, 0.7),
	Speed = NumberRange.new(14, 28),
	SpreadAngle = Vector2.new(180, 180),
	Drag = 3,
	Acceleration = Vector3.new(0, -10, 0),
})
emitter(impact, "Stars", { -- celestial spark fragments
	Texture = TEX.Sparkle,
	Color = colors({ { 0, WHITE }, { 1, PALE } }),
	LightEmission = 1,
	Brightness = 4,
	Size = seq({ { 0, 0.9 }, { 1, 0 } }),
	Lifetime = NumberRange.new(0.5, 1),
	Speed = NumberRange.new(6, 12),
	SpreadAngle = Vector2.new(180, 180),
	Drag = 2,
	RotSpeed = NumberRange.new(-180, 180),
})
light(impact, 20)
impact.Parent = folder

-- ===== Sounds =====
local sounds = Instance.new("Folder")
sounds.Name = "Sounds"
for name, spec in SOUNDS do
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = spec[1] :: string
	sound.Volume = spec[2] :: number
	sound.PlaybackSpeed = spec[3] :: number
	sound.RollOffMaxDistance = 160
	sound.Looped = name == "Loop"
	sound.Parent = sounds
end
sounds.Parent = folder

-- ===== Cast animation (hand-written: client/Abilities/StarCannonKeyframes) =====
local abilities = StarterPlayer.StarterPlayerScripts:FindFirstChild("Client")
	and StarterPlayer.StarterPlayerScripts.Client:FindFirstChild("Abilities")
if abilities and abilities:FindFirstChild("Pose") and abilities:FindFirstChild("StarCannonKeyframes") then
	local Pose = require(abilities.Pose) :: any
	local copy = abilities.StarCannonKeyframes:Clone() -- a copy, so an edited file is read fresh
	copy.Name = "StarCannonKeyframes_build"
	copy.Parent = abilities
	local ok, keyframes = pcall(require, copy)
	copy:Destroy()
	if ok then
		local sequence = Pose.Build("StarCannon", keyframes)
		sequence.Name = "CastAnimation"
		sequence.Parent = folder
	end
end

folder.Parent = vfx
return `built {#folder:GetChildren()} templates`

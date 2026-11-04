--!strict
-- Gale Step (Uncommon, Movement): an extremely fast dash with wind trails.
-- Look: images/abilities/gale step.png (12 panels). Anime wind: white core, cyan glow, crisp crescent
-- swooshes, diamond sparkles. Palette #E9FBFF core / #7FE6FF main / #2FA8D8 deep edge, nothing else.
-- Every asset is made in Blender (Game/assets/gale_step.blend, Game/assets/vfx/_src/build_gale_step_*.py):
-- the dash animation (GaleStepKeyframes, uploaded), the wind meshes and textures (templates in
-- ReplicatedStorage.VFX.GaleStep, built by Game/tools/build_gale_step_templates.luau).
--
--   1. Charge     0 – 0.15 s   crouch; 3 ground rings spin up at the feet (2 -> 5 studs), sparkles and
--                              wisps drawn inward, 2 crescents circle the body, ground glow + light
--   2. Dash start 0.15 s       3 crescents fan out behind, a big bow-wave crescent in front, a shock
--                              ring, white wind spikes shot backward along the floor, dust kick at the
--                              back foot, one-frame flash at the chest
--   3. Dash       DashStart    "DashStart" marker (frame 6 = 0.2 s): 30 studs toward where the camera
--                 – 0.5 s      faces in 0.3 s, 2 studs short of any wall. Trails on hands/feet/torso,
--                              an afterimage every 0.05 s, 6 streak beams riding with the body + 4
--                              drawn along the path, sparkles + wisps shed behind, 2 crescents orbiting,
--                              crescents peeling off every 0.075 s, upright "wind tunnel" rings bursting
--                              open every 6 studs, a cyan aura round the body, a glow streak drawn on
--                              the floor and pale dust skimmed off it
--   4. Finish     0.5 – 0.75 s stops hard: spiral wraps the body, swirl flipbook, 2 rings expanding at
--                              the feet, 2 tilted rings at waist/chest, 2 crescents circling overhead,
--                              wisps + sparkles thrown outward
--   5. Fade       0.75 – 1.2 s rings shrink and fade, a few sparkles float up, ground glow dies out
-- Every wind mesh is 3 tones (white core, cyan main a little wider, deep-edge copy a little narrower);
-- Low quality (client/VFX/Quality) keeps one tone and about half of everything.
--
-- Movement: our own client moves our own character (smooth): a LinearVelocity in the ground plane,
-- so walls and the floor still collide; a spherecast first shortens the dash to stop 2 studs before
-- any wall. The server (AbilityService) checks the cooldown and pulls back any dash over 32 studs.
-- The dasher plays everything on the key press; everyone else from AbilityUsed. Others' dashes start
-- on a timer (their animation reaches us by replication, so we get no marker events for it).
--
-- Budget per dash (full): ~90 wind mesh parts (pooled), ~100 afterimage parts (0.3 s each), 5 trails,
-- 10 beams, ~120 particles, 1 light. Everything lives in one Folder under workspace.ClientVFX (plus the
-- trail attachments on the character) and is destroyed when the dash is over.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Types = require(Shared:WaitForChild("Types"))
local Abilities = require(Config:WaitForChild("Abilities"))

local Client = script.Parent.Parent
local Quality = require(Client:WaitForChild("VFX"):WaitForChild("Quality"))
local Pose = require(script.Parent.Pose)
local KEYFRAMES = require(script.Parent.GaleStepKeyframes)

local def: Types.AbilityDef? = nil
for _, ability in Abilities do
	if ability.Id == "GaleStep" then
		def = ability
	end
end
assert(def, "GaleStep is missing from Shared/Config/Abilities")

local CONFIG = {
	-- Movement (studs, seconds). Cooldown/range/max live in Shared/Config/Abilities: the server reads them.
	COOLDOWN = def.Cooldown, -- 4 s
	DASH_STUDS = def.Range, -- 30
	DASH_SECONDS = 0.3,
	MAX_DASH_STUDS = def.MaxDashStuds or 32, -- server-side limit
	WALL_CLEARANCE = 2, -- the front of the body stops this far before a wall
	BODY_RADIUS = 1.2, -- the sphere swept ahead to find walls (about the body's half-width)
	BODY_REACH = 2.55, -- how far the body reaches ahead of the root at the brake (arm swung out by the twist)
	DASH_START = def.WindupSeconds or 0.2, -- "DashStart" marker, frame 6
	MARKER_GRACE = 0.08, -- if our own track never fires the marker, dash this much later anyway
	FOV_KICK = 8, -- degrees, our own camera only, during the dash

	-- Timeline (seconds at normal speed)
	CHARGE_SECONDS = 0.15,
	BURST_AT = 0.15,
	FINISH_SECONDS = 0.25, -- spiral/swirl phase after the stop
	FADE_SECONDS = 0.45, -- rings shrink, sparkles float up

	-- Palette (no other colours)
	CORE = "#E9FBFF",
	MAIN = "#7FE6FF",
	EDGE = "#2FA8D8",
	BRIGHTNESS = 1.8, -- particles/beams/trails above 1 reach the place's Bloom (threshold 2) where they overlap

	-- 1. Charge
	CHARGE_RING_FROM = 2, -- studs across
	CHARGE_RING_TO = 5,
	CHARGE_RING_TURNS = 2, -- turns per second
	CHARGE_RING_ALPHA = 0.8, -- = transparency 0.2 at its brightest
	CHARGE_SPARKLES = 6,
	CHARGE_WISPS = 12,
	CHARGE_ORBIT_RADIUS = 2.2,

	-- 2. Dash start
	BURST_CRESCENTS = 3,
	BURST_SCALE_FROM = 1,
	BURST_SCALE_TO = 1.6,
	BURST_SECONDS = 0.2,
	BURST_SPIKES = 16,
	BURST_DUST = 6,
	FLASH_SIZE = 4,

	-- 3. Dash
	TRAIL_WIDTH = 0.8, -- studs, narrowing to 0
	TRAIL_LIFETIME = 0.25,
	AFTERIMAGE_EVERY = 0.05,
	AFTERIMAGE_FROM = 0.4, -- transparency
	AFTERIMAGE_SECONDS = 0.3,
	RIDING_STREAKS = 10, -- long horizontal wind lines riding with the body (panels 4-6)
	RIDING_STREAK_MIN = 9, -- studs long
	RIDING_STREAK_MAX = 15,
	PATH_STREAKS = 4,
	PATH_STREAK_MIN = 6, -- studs long
	PATH_STREAK_MAX = 10,
	SPARKLES_PER_SECOND = 20,
	SPARKLE_LIFETIME = 0.4,
	WISPS_PER_SECOND = 30,
	DASH_ORBIT_TURNS = 2.5,
	TUNNEL_RING_EVERY = 6, -- studs along the path: an upright ring bursts open as the body passes
	TUNNEL_RING_FROM = 2.5, -- studs across
	TUNNEL_RING_TO = 6.5,
	TUNNEL_RING_SECONDS = 0.3,
	SLICE_EVERY = 0.075, -- seconds: a crescent peels off around the body
	SLICE_SECONDS = 0.22,
	AURA_PER_SECOND = 30, -- soft glow wrapped round the body
	GROUND_STREAK_WIDTH = 2, -- studs: glow ribbon drawn on the floor under the dash
	GROUND_STREAK_SECONDS = 0.35, -- how long it takes to fade behind the body
	SKIM_DUST_PER_SECOND = 15,

	-- 4. Finish
	SPIRAL_TURNS = 1.5, -- per second
	SPIRAL_SCALE_FROM = 0.6,
	SPIRAL_SCALE_TO = 1.2,
	SWIRL_PARTICLES = 7,
	SWIRL_SIZE = 6,
	SWIRL_LIFETIME = 0.5,
	SWIRL_BRIGHTNESS = 0.9,
	FINISH_WISPS = 12,
	FINISH_SPARKLES = 8,

	-- 5. Fade
	FLOAT_SPARKLES = 5,

	-- Asset ids (uploaded with Open Cloud, owned by the game's owner; see Game/assets/vfx/gale_step_assets.json).
	-- The textures are applied from here; mesh ids can't change at runtime, so the templates carry them.
	ASSETS = {
		Animation = def.AnimationId or "rbxassetid://130755455737261", -- GaleStep_Dash
		Textures = {
			WindGradient = "rbxassetid://115854320689894",
			WindStreaks = "rbxassetid://83090249483866",
			Sparkle = "rbxassetid://76795312198770",
			SoftGlow = "rbxassetid://134061496595746",
			WindWisp = "rbxassetid://115689752915482",
			SwirlFlipbook = "rbxassetid://76836933588665", -- 4x4 grid, 16 frames
			Dust = "rbxassetid://119015403999595", -- dust_puff, shared with Pebble Toss
		},
		Meshes = { -- mesh id (FBX model package)
			CrescentA = "rbxassetid://81358747084401", -- 97251964717099
			CrescentB = "rbxassetid://73019651433783", -- 139020940779892
			Ring = "rbxassetid://90664669742250", -- 71169891453451
			Spiral = "rbxassetid://115628997654552", -- 85431287904931
		},
	},
}

-- The spiral mesh is centred on its bounding box; its axis base (the Blender origin) is this far
-- from that centre, in the mesh's own axes (measured in Blender, build_gale_step_meshes.py).
local SPIRAL_CENTRE = Vector3.new(0.1061, 2.5, -0.1442)
local RING_DIAMETER = 5 -- the wind_ring mesh, studs across
local TRAIL_PARTS = { "UpperTorso", "LeftHand", "RightHand", "LeftFoot", "RightFoot" }

export type Options = {
	TimeScale: number?, -- 1 = normal speed; /vfxtest plays at 0.25
	PlayAnimation: boolean?, -- play the dash animation on this character (always for our own)
	Move: boolean?, -- move this character (always for our own); an anchored rig is moved by CFrame
}

type Tone = { Color: Color3, Scale: number, Alpha: number, Glow: number }
type Layer = { Template: string, Parts: { MeshPart }, Base: Vector3, Tones: { Tone } }
type Anim = { Start: number, Duration: number, Update: (a: number) -> () }

type Cast = {
	Character: Model,
	Root: BasePart,
	Folder: Folder,
	TimeScale: number,
	Low: boolean,
	IsLocal: boolean,
	Moves: boolean, -- this client moves the character (our own, or a test rig)
	T0: number,
	Flat: Vector3,
	Anims: { Anim },
	Layers: { Layer },
	Extras: { Instance }, -- made outside the folder (attachments on the character)
	Connections: { RBXScriptConnection },
	Carrier: BasePart?, -- follows the root during the dash
	Ended: boolean,
	Restore: { () -> () },
}

local function color(hex: string): Color3
	return Color3.fromHex(hex)
end
local CORE, MAIN, EDGE = color(CONFIG.CORE), color(CONFIG.MAIN), color(CONFIG.EDGE)

-- Cyan carries the shape; white is only a thinner core line inside it (reference: saturated cyan
-- with white centres, not white swooshes with a cyan fringe).
local TONES_FULL: { Tone } = {
	{ Color = MAIN, Scale = 1, Alpha = 1, Glow = 3.5 },
	{ Color = CORE, Scale = 0.985, Alpha = 0.6, Glow = 3 },
	{ Color = EDGE, Scale = 1.06, Alpha = 0.55, Glow = 2 },
}
local TONES_LOW: { Tone } = {
	{ Color = MAIN, Scale = 1, Alpha = 1, Glow = 4 },
}

local GaleStepVFX = {}

local casts: { [Model]: Cast } = {}
local vfxFolder: Folder? = nil
local pool: { [string]: { MeshPart } } = {}

local function folder(): Folder
	if vfxFolder and vfxFolder.Parent then
		return vfxFolder
	end
	local existing = workspace:FindFirstChild("ClientVFX")
	if existing and existing:IsA("Folder") then
		vfxFolder = existing
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = "ClientVFX"
	f.Parent = workspace
	vfxFolder = f
	return f
end

local function templates(): Folder
	return ReplicatedStorage:WaitForChild("VFX"):WaitForChild("GaleStep") :: Folder
end

local function numbers(...: number): NumberSequence
	local values = { ... }
	local points = {}
	for i = 1, #values, 2 do
		table.insert(points, NumberSequenceKeypoint.new(values[i], values[i + 1]))
	end
	return NumberSequence.new(points)
end

local function easeOut(a: number): number
	return 1 - (1 - a) * (1 - a)
end

-- 0 -> 1 over the first `fadeIn` of a, 1 until `fadeOutFrom`, then back to 0 at a = 1.
local function inOut(a: number, fadeIn: number, fadeOutFrom: number): number
	if a < fadeIn then
		return a / fadeIn
	elseif a > fadeOutFrom then
		return math.max(0, (1 - a) / (1 - fadeOutFrom))
	end
	return 1
end

local function elapsed(cast: Cast): number
	return (os.clock() - cast.T0) * cast.TimeScale
end

-- Run fn at skill time t (seconds at normal speed), unless the cast ended first.
local function at(cast: Cast, t: number, fn: () -> ())
	task.delay(math.max(0, t - elapsed(cast)) / cast.TimeScale, function()
		if not cast.Ended then
			fn()
		end
	end)
end

-- Call update(a) every frame with a going 0 -> 1 over `duration` skill-seconds, starting now.
local function animate(cast: Cast, duration: number, update: (a: number) -> ())
	update(0)
	table.insert(cast.Anims, { Start = elapsed(cast), Duration = duration, Update = update })
end

-- ===== pooled wind meshes (3 tones each) =====

local function acquire(name: string): MeshPart
	local list = pool[name]
	if list and #list > 0 then
		return table.remove(list) :: MeshPart
	end
	return templates():WaitForChild(name):Clone() :: MeshPart
end

local function release(part: MeshPart, name: string)
	part.Parent = nil
	part.Transparency = 1
	local list = pool[name]
	if not list then
		list = {}
		pool[name] = list
	end
	table.insert(list, part)
end

local function layer(cast: Cast, name: string): Layer
	local tones = if cast.Low then TONES_LOW else TONES_FULL
	local base = (templates():WaitForChild(name) :: MeshPart).Size
	local parts = {}
	for _, tone in tones do
		local part = acquire(name)
		local look = part:FindFirstChildOfClass("SurfaceAppearance")
		if look then
			look.Color = tone.Color
			look.EmissiveTint = tone.Color
			look.EmissiveStrength = tone.Glow
		end
		part.Transparency = 1
		part.Parent = cast.Folder
		table.insert(parts, part)
	end
	local l: Layer = { Template = name, Parts = parts, Base = base, Tones = tones }
	table.insert(cast.Layers, l)
	return l
end

-- Place a layer: cf = where the shape sits (for the spiral: its base on the ground), scale = size
-- multiplier, alpha = 0 (gone) .. 1 (fully visible).
local function setLayer(l: Layer, cf: CFrame, scale: number, alpha: number)
	for i, part in l.Parts do
		local tone = l.Tones[i]
		local s = scale * tone.Scale
		part.Size = l.Base * s
		part.CFrame = if l.Template == "Spiral" then cf * CFrame.new(SPIRAL_CENTRE * s) else cf
		part.Transparency = 1 - math.clamp(alpha, 0, 1) * tone.Alpha
	end
end

-- ===== small helpers =====

local function anchor(cast: Cast, name: string, cframe: CFrame, size: Vector3?): (Part, Attachment)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size or Vector3.one * 0.2
	part.CFrame = cframe
	part.Parent = cast.Folder
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	return part, attachment
end

local TEXTURE_OF: { [string]: string } = {
	Sparkle = CONFIG.ASSETS.Textures.Sparkle,
	Wisp = CONFIG.ASSETS.Textures.WindWisp,
	Swirl = CONFIG.ASSETS.Textures.SwirlFlipbook,
	Glow = CONFIG.ASSETS.Textures.SoftGlow,
	Dust = CONFIG.ASSETS.Textures.Dust,
}

-- A ParticleEmitter from the templates, with overrides. parent: an Attachment, or a Part (then the
-- emitter's Shape uses the part's size).
local function emitter(cast: Cast, name: string, parent: Instance, props: { [string]: any }?): ParticleEmitter
	local e = templates():WaitForChild(name):Clone() :: ParticleEmitter
	e.Texture = TEXTURE_OF[name] or e.Texture
	e.TimeScale = cast.TimeScale
	if name ~= "Dust" then
		e.Brightness = CONFIG.BRIGHTNESS
	end
	for key, value in props or {} do
		(e :: any)[key] = value
	end
	-- VelocityParallel lines the texture's X axis up with the motion; the wisp is drawn along Y,
	-- so turn it a quarter so it streaks along its path instead of standing across it.
	if e.Orientation == Enum.ParticleOrientation.VelocityParallel and not (props and props.Rotation) then
		e.Rotation = NumberRange.new(90)
	end
	e.Parent = parent
	return e
end

local function count(cast: Cast, full: number): number
	return if cast.Low then math.max(1, math.ceil(full / 2)) else full
end

local function excludeParams(character: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, folder() }
	return params
end

-- Ground under a point (a CFrame on the floor facing `flat`).
local function groundAt(position: Vector3, flat: Vector3, character: Model): CFrame
	local result = workspace:Raycast(position, Vector3.new(0, -12, 0), excludeParams(character))
	local y = if result then result.Position.Y else position.Y - 3
	local p = Vector3.new(position.X, y + 0.05, position.Z)
	return CFrame.lookAt(p, p + flat)
end

-- How far the dash can go: DASH_STUDS, or so the front of the body (BODY_REACH ahead of the root,
-- the brake pose's front foot) ends WALL_CLEARANCE short of the first wall in the way.
function GaleStepVFX.DashDistance(character: Model, from: Vector3, flat: Vector3): number
	local reach = CONFIG.DASH_STUDS + CONFIG.WALL_CLEARANCE + CONFIG.BODY_REACH
	local hit = workspace:Spherecast(from, CONFIG.BODY_RADIUS, flat * reach, excludeParams(character))
	if not hit then
		return CONFIG.DASH_STUDS
	end
	-- the sphere touches the wall after hit.Distance, so the wall is BODY_RADIUS further on
	local wall = hit.Distance + CONFIG.BODY_RADIUS
	return math.clamp(wall - CONFIG.WALL_CLEARANCE - CONFIG.BODY_REACH, 0, CONFIG.DASH_STUDS)
end

local function endCast(cast: Cast)
	if cast.Ended then
		return
	end
	cast.Ended = true
	for _, connection in cast.Connections do
		connection:Disconnect()
	end
	table.clear(cast.Connections)
	for _, restore in cast.Restore do
		restore()
	end
	for _, l in cast.Layers do
		for _, part in l.Parts do
			release(part, l.Template)
		end
	end
	for _, extra in cast.Extras do
		extra:Destroy()
	end
	cast.Folder:Destroy()
	if casts[cast.Character] == cast then
		casts[cast.Character] = nil
	end
end

-- ===== 1. Charge =====

local function charge(cast: Cast)
	local root = cast.Root
	local ground = groundAt(root.Position, cast.Flat, cast.Character)

	-- Ground rings: spin up and grow at the feet, stay where the dash started and fade after it.
	-- (from, to) in studs across, turns/s, tilt degrees, height, brightest alpha
	local rings = {
		{ CONFIG.CHARGE_RING_FROM, CONFIG.CHARGE_RING_TO, CONFIG.CHARGE_RING_TURNS, 0, 0.06, CONFIG.CHARGE_RING_ALPHA },
	}
	if not cast.Low then
		table.insert(rings, { 1.5, 3.4, -2.6, 8, 0.14, 0.6 })
		table.insert(rings, { 3, 6.2, 1.4, -6, 0.22, 0.45 })
	end
	local total = CONFIG.DASH_START + 0.3
	for _, spec in rings do
		local from, to, turns, tilt, height, bright = spec[1], spec[2], spec[3], spec[4], spec[5], spec[6]
		local l = layer(cast, "Ring")
		animate(cast, total, function(a)
			local t = a * total
			local grow = easeOut(math.min(1, t / CONFIG.CHARGE_SECONDS))
			local fade = if t < CONFIG.DASH_START then 1 else 1 - (t - CONFIG.DASH_START) / 0.3
			local size = from + (to - from) * grow + (if t > CONFIG.DASH_START then (t - CONFIG.DASH_START) * 3 else 0)
			local cf = ground * CFrame.new(0, height, 0) * CFrame.Angles(math.rad(tilt), 0, 0)
				* CFrame.Angles(0, turns * math.pi * 2 * t, 0)
			setLayer(l, cf, size / RING_DIAMETER, bright * grow * fade)
		end)
	end

	-- Sparkles and wind wisps drawn inward from a circle round the body.
	local gather = anchor(cast, "Gather", ground * CFrame.new(0, 1.4, 0), Vector3.new(6.5, 2.4, 6.5))
	emitter(cast, "Sparkle", gather, {
		Shape = Enum.ParticleEmitterShape.Cylinder,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Speed = NumberRange.new(6, 8),
		Size = numbers(0, 0.25, 0.5, 0.45, 1, 0),
	}):Emit(CONFIG.CHARGE_SPARKLES)
	emitter(cast, "Wisp", gather, {
		Shape = Enum.ParticleEmitterShape.Cylinder,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Speed = NumberRange.new(8, 12),
		Lifetime = NumberRange.new(0.25, 0.3),
		Acceleration = Vector3.new(0, 6, 0),
	}):Emit(count(cast, CONFIG.CHARGE_WISPS))

	-- Swirl gathering: 2 crescents circling the body at waist and chest height.
	if not cast.Low then
		for i, height in { 1.3, 2.7 } do
			local l = layer(cast, "CrescentA")
			local dir = if i == 1 then 1 else -1
			local tilt = if i == 1 then 18 else -14
			animate(cast, CONFIG.DASH_START + 0.1, function(a)
				local t = a * (CONFIG.DASH_START + 0.1)
				local centre = ground * CFrame.new(0, height, 0) * CFrame.Angles(math.rad(tilt), 0, 0)
				local angle = dir * CONFIG.CHARGE_RING_TURNS * math.pi * 2 * t + i * math.pi
				local cf = centre * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -CONFIG.CHARGE_ORBIT_RADIUS)
				setLayer(l, cf, 0.75 + 0.25 * a, 0.9 * inOut(a, 0.4, 0.7))
			end)
		end
	end

	-- Soft glow lying on the ground under the feet, and a cyan light.
	local _, glowAt = anchor(cast, "GroundGlow", ground * CFrame.new(0, 0.1, 0))
	emitter(cast, "Glow", glowAt, {
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(0.01),
		Color = ColorSequence.new(MAIN),
		Size = numbers(0, 3, 0.3, 6, 1, 6.5),
		Transparency = numbers(0, 1, 0.2, 0.55, 0.6, 0.7, 1, 1),
		Lifetime = NumberRange.new(CONFIG.DASH_START + 0.4),
		Brightness = 1.5,
	}):Emit(1)
	if not cast.Low then
		local light = Instance.new("PointLight")
		light.Color = MAIN
		light.Range = 12
		light.Brightness = 0
		light.Shadows = false
		light.Parent = glowAt
		animate(cast, CONFIG.DASH_START + 0.25, function(a)
			light.Brightness = 2 * inOut(a, 0.4, 0.6)
		end)
	end
end

-- ===== 2. Dash start =====

local function burst(cast: Cast)
	local root = cast.Root
	local flat = cast.Flat
	local facing = CFrame.lookAt(root.Position, root.Position + flat)
	local ground = groundAt(root.Position, flat, cast.Character)

	-- 3 crescents fanned out behind, opening backward and outward, growing 1 -> 1.6 while fading.
	local fan = { { 0, 2.6, 90 }, { 38, 1.6, 55 }, { -38, 3.4, 125 } } -- yaw, height, roll
	for i = 1, CONFIG.BURST_CRESCENTS do
		local spec = fan[i]
		local l = layer(cast, "CrescentB")
		local out = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(spec[1])):VectorToWorldSpace(-flat)
		local origin = Vector3.new(root.Position.X, ground.Position.Y + spec[2], root.Position.Z) - flat * 1.2
		animate(cast, CONFIG.BURST_SECONDS, function(a)
			local p = origin + out * (0.4 + 2.2 * easeOut(a))
			local cf = CFrame.lookAt(p, p + out) * CFrame.Angles(0, 0, math.rad(spec[3]))
			local scale = CONFIG.BURST_SCALE_FROM + (CONFIG.BURST_SCALE_TO - CONFIG.BURST_SCALE_FROM) * easeOut(a)
			setLayer(l, cf, scale, 1 - a * a)
		end)
	end

	-- Bow wave: a big upright crescent bulging forward in front of the body.
	local bow = layer(cast, "CrescentB")
	animate(cast, 0.25, function(a)
		local p = root.Position + flat * (1.8 + 1.5 * a) + Vector3.new(0, 0.3, 0)
		local cf = CFrame.lookAt(p, p + flat) * CFrame.Angles(0, 0, math.rad(90))
		setLayer(bow, cf, 2 + 0.8 * easeOut(a), 0.95 * (1 - a))
	end)

	-- Shock ring at the feet.
	local shock = layer(cast, "Ring")
	animate(cast, 0.25, function(a)
		setLayer(shock, ground * CFrame.new(0, 0.08, 0), (2 + 5 * easeOut(a)) / RING_DIAMETER, 0.9 * (1 - a))
	end)

	-- White wind spikes shot backward along the floor, a dust kick at the back foot.
	local backFoot = cast.Character:FindFirstChild("RightFoot") :: BasePart?
	local footAt = if backFoot then backFoot.Position else root.Position - flat
	local kick = Vector3.new(footAt.X, ground.Position.Y + 0.3, footAt.Z)
	local _, spikeAt = anchor(cast, "Spikes", CFrame.lookAt(kick, kick - flat + Vector3.new(0, 0.12, 0)))
	emitter(cast, "Wisp", spikeAt, {
		EmissionDirection = Enum.NormalId.Front,
		Color = ColorSequence.new(CORE),
		Speed = NumberRange.new(25, 40),
		Lifetime = NumberRange.new(0.18, 0.25),
		Size = numbers(0, 1.8, 1, 0.3),
		Squash = numbers(0, 1.2, 1, 1.2), -- long and thin
		Transparency = numbers(0, 0, 0.7, 0.3, 1, 1),
		SpreadAngle = Vector2.new(35, 8),
		Drag = 2,
	}):Emit(count(cast, CONFIG.BURST_SPIKES))
	emitter(cast, "Dust", spikeAt, {
		EmissionDirection = Enum.NormalId.Front,
	}):Emit(count(cast, CONFIG.BURST_DUST))

	-- One frame of soft glow at the chest.
	local chest = cast.Character:FindFirstChild("UpperTorso") :: BasePart?
	local _, flashAt = anchor(cast, "Flash", if chest then chest.CFrame else facing)
	emitter(cast, "Glow", flashAt, {
		Size = numbers(0, CONFIG.FLASH_SIZE, 1, CONFIG.FLASH_SIZE * 1.2),
		Lifetime = NumberRange.new(1 / 30),
	}):Emit(1)
end

-- ===== 3. Dash =====

-- Moves the character DASH_STUDS (or less, before a wall) in DASH_SECONDS. Calls done() when it stops.
local function move(cast: Cast, distance: number, done: () -> ())
	local character, root, flat = cast.Character, cast.Root, cast.Flat
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local start = root.Position
	local speed = CONFIG.DASH_STUDS / CONFIG.DASH_SECONDS * cast.TimeScale
	local limit = CONFIG.DASH_SECONDS / cast.TimeScale + 0.15 -- real seconds; blocked by something unexpected
	local began = os.clock()
	root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)

	if root.Anchored then
		-- A test rig (anchored root): slide it by CFrame.
		local slide: RBXScriptConnection
		slide = RunService.RenderStepped:Connect(function()
			local travelled = math.min(distance, speed * (os.clock() - began))
			root.CFrame = CFrame.lookAt(start + flat * travelled, start + flat * (travelled + 1))
			if travelled >= distance then
				slide:Disconnect()
				done()
			end
		end)
		table.insert(cast.Connections, slide)
		return
	end

	-- Our own character: physics velocity in the ground plane (gravity and collisions still apply).
	local attachment = Instance.new("Attachment")
	attachment.Name = "GaleStepDash"
	attachment.Parent = root
	local push = Instance.new("LinearVelocity")
	push.Name = "GaleStepDash"
	push.Attachment0 = attachment
	push.RelativeTo = Enum.ActuatorRelativeTo.World
	push.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	push.PrimaryTangentAxis = Vector3.xAxis
	push.SecondaryTangentAxis = Vector3.zAxis
	push.ForceLimitMode = Enum.ForceLimitMode.Magnitude
	push.MaxForce = math.huge
	push.PlaneVelocity = Vector2.new(flat.X, flat.Z) * speed
	push.Parent = root
	table.insert(cast.Extras, attachment)
	table.insert(cast.Extras, push)
	local autoRotate = humanoid and humanoid.AutoRotate
	if humanoid then
		humanoid.AutoRotate = false
	end

	local stepping: RBXScriptConnection
	local function stop()
		stepping:Disconnect()
		push:Destroy()
		attachment:Destroy()
		-- Stops hard: no sliding on after the dash.
		root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
		if humanoid and autoRotate ~= nil then
			humanoid.AutoRotate = autoRotate
		end
		done()
	end
	stepping = RunService.Heartbeat:Connect(function(dt)
		local travelled = flat:Dot(root.Position - start)
		local left = distance - travelled
		if left <= 0.05 or os.clock() - began > limit or not root.Parent then
			stop()
			return
		end
		local v = math.min(speed, left / math.max(dt, 1 / 240))
		push.PlaneVelocity = Vector2.new(flat.X, flat.Z) * v
	end)
	table.insert(cast.Connections, stepping)
end

local function afterimage(cast: Cast)
	local ghost = Instance.new("Folder")
	ghost.Name = "Afterimage"
	for _, part in cast.Character:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Transparency < 1 then
			local copy = part:Clone()
			for _, child in copy:GetChildren() do
				child:Destroy()
			end
			copy.Anchored = true
			copy.CanCollide = false
			copy.CanTouch = false
			copy.CanQuery = false
			copy.CastShadow = false
			copy.Massless = true
			copy.Material = Enum.Material.ForceField
			copy.Color = MAIN
			copy.Transparency = CONFIG.AFTERIMAGE_FROM
			copy.CFrame = part.CFrame
			copy.Parent = ghost
		end
	end
	ghost.Parent = cast.Folder
	animate(cast, CONFIG.AFTERIMAGE_SECONDS, function(a)
		for _, copy in ghost:GetChildren() do
			(copy :: BasePart).Transparency = CONFIG.AFTERIMAGE_FROM + (1 - CONFIG.AFTERIMAGE_FROM) * a
		end
		if a >= 1 then
			ghost:Destroy()
		end
	end)
end

local function streakBeam(cast: Cast, a0: Attachment, a1: Attachment, width: number, parent: Instance): Beam
	local beam = templates():WaitForChild("Streak"):Clone() :: Beam
	-- one bold band per beam (wind_gradient); wind_streaks' hair-thin lines vanish at game distance
	beam.Texture = CONFIG.ASSETS.Textures.WindGradient
	beam.Attachment0 = a0 -- the texture's solid end
	beam.Attachment1 = a1
	beam.Width0 = width
	beam.Width1 = width * 0.6
	beam.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, CORE),
		ColorSequenceKeypoint.new(0.2, MAIN),
		ColorSequenceKeypoint.new(1, EDGE),
	})
	beam.Brightness = CONFIG.BRIGHTNESS
	beam.TextureSpeed = 1.5 * cast.TimeScale
	beam.Parent = parent
	return beam
end

local function fadeBeam(beam: Beam, alpha: number)
	local t = 1 - math.clamp(alpha, 0, 1) * 0.9
	beam.Transparency = numbers(0, t, 1, 1)
end

local function dash(cast: Cast, distance: number, onStop: () -> ())
	local character, root, flat = cast.Character, cast.Root, cast.Flat
	local start = root.Position
	local seconds = distance / (CONFIG.DASH_STUDS / CONFIG.DASH_SECONDS) -- skill-seconds of movement

	-- Carrier: follows the root without its rotation, facing the dash. -Z = forward, +Z = behind.
	local carrier, behind = anchor(cast, "Carrier", CFrame.lookAt(start, start + flat))
	behind.CFrame = CFrame.new(0, 0, 1) * CFrame.Angles(0, math.pi, 0) -- faces backward
	cast.Carrier = carrier
	local follow = RunService.RenderStepped:Connect(function()
		if root.Parent then
			carrier.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
		end
	end)
	table.insert(cast.Connections, follow)

	-- Trails on the torso, hands and feet: width TRAIL_WIDTH narrowing to 0.
	local trails: { Trail } = {}
	for _, name in TRAIL_PARTS do
		local part = character:FindFirstChild(name) :: BasePart?
		if part and (not cast.Low or name == "UpperTorso" or name:find("Foot")) then
			local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
			a0.Name, a1.Name = "GaleStepTrail0", "GaleStepTrail1"
			a0.Position = Vector3.new(0, CONFIG.TRAIL_WIDTH / 2, 0)
			a1.Position = Vector3.new(0, -CONFIG.TRAIL_WIDTH / 2, 0)
			a0.Parent, a1.Parent = part, part
			local trail = templates():WaitForChild("Trail"):Clone() :: Trail
			trail.Texture = CONFIG.ASSETS.Textures.WindStreaks
			trail.Attachment0, trail.Attachment1 = a0, a1
			trail.Lifetime = CONFIG.TRAIL_LIFETIME / cast.TimeScale
			-- white only at the head, cyan behind, deep edge at the tail (all white reads as flat slabs)
			trail.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, CORE),
				ColorSequenceKeypoint.new(0.15, MAIN),
				ColorSequenceKeypoint.new(1, EDGE),
			})
			trail.Transparency = numbers(0, 0.15, 0.4, 0.45, 1, 1)
			trail.Brightness = 1.6
			trail.Enabled = true
			trail.Parent = cast.Folder
			table.insert(trails, trail)
			table.insert(cast.Extras, a0)
			table.insert(cast.Extras, a1)
		end
	end

	-- Streak beams riding with the body: solid end near the body, stretching back 6-10 studs.
	local riding: { Beam } = {}
	local rnd = Random.new()
	for i = 1, count(cast, CONFIG.RIDING_STREAKS) do
		local side = if i % 2 == 0 then 1 else -1
		local x = side * rnd:NextNumber(0.5, 2.6)
		local y = -2.4 + 4.8 * (i - 0.5) / CONFIG.RIDING_STREAKS + rnd:NextNumber(-0.2, 0.2) -- spread over the body height
		local head, tail = Instance.new("Attachment"), Instance.new("Attachment")
		head.Position = Vector3.new(x, y, rnd:NextNumber(-0.5, 1))
		tail.Position = Vector3.new(x * 1.15, y, rnd:NextNumber(CONFIG.RIDING_STREAK_MIN, CONFIG.RIDING_STREAK_MAX))
		head.Parent, tail.Parent = carrier, carrier
		table.insert(riding, streakBeam(cast, head, tail, rnd:NextNumber(0.25, 0.55), carrier))
	end

	-- Streaks drawn along the path: each one fixed in the world, its front end following the body.
	local pathPart = anchor(cast, "PathStreaks", CFrame.lookAt(start, start + flat))
	type PathStreak = { Beam: Beam, Head: Attachment, From: number, To: number, Offset: Vector2 }
	local pathStreaks: { PathStreak } = {}
	for i = 1, count(cast, CONFIG.PATH_STREAKS) do
		local length = rnd:NextNumber(CONFIG.PATH_STREAK_MIN, CONFIG.PATH_STREAK_MAX)
		local from = rnd:NextNumber(0, math.max(0, distance - length))
		local offset = Vector2.new((if i % 2 == 0 then 1 else -1) * rnd:NextNumber(1, 2.4), rnd:NextNumber(-2.4, 1.6))
		local head, tail = Instance.new("Attachment"), Instance.new("Attachment")
		tail.Position = Vector3.new(offset.X, offset.Y, -from)
		head.Position = tail.Position
		head.Parent, tail.Parent = pathPart, pathPart
		local beam = streakBeam(cast, head, tail, rnd:NextNumber(0.25, 0.45), pathPart)
		fadeBeam(beam, 0)
		table.insert(pathStreaks, { Beam = beam, Head = head, From = from, To = math.min(distance, from + length), Offset = offset })
	end

	-- Sparkles + wisps shed behind the body.
	local shedAt = Instance.new("Attachment")
	shedAt.CFrame = behind.CFrame * CFrame.new(0, 0.6, 0)
	shedAt.Parent = carrier
	local sparkles = emitter(cast, "Sparkle", shedAt, {
		EmissionDirection = Enum.NormalId.Front,
		Rate = if cast.Low then CONFIG.SPARKLES_PER_SECOND / 2 else CONFIG.SPARKLES_PER_SECOND,
		Lifetime = NumberRange.new(CONFIG.SPARKLE_LIFETIME),
		Speed = NumberRange.new(2, 5),
		SpreadAngle = Vector2.new(50, 50),
	})
	-- No drag: a wisp that slows to a stop loses its direction and stands upright.
	local wisps = emitter(cast, "Wisp", shedAt, {
		EmissionDirection = Enum.NormalId.Front,
		Rate = if cast.Low then CONFIG.WISPS_PER_SECOND / 2 else CONFIG.WISPS_PER_SECOND,
		Speed = NumberRange.new(10, 16),
		Drag = 0,
		Lifetime = NumberRange.new(0.25, 0.35),
		SpreadAngle = Vector2.new(25, 35),
	})
	sparkles.Enabled = true
	wisps.Enabled = true

	-- Soft cyan aura wrapped round the body (moves with it).
	local auraAt = Instance.new("Attachment")
	auraAt.Position = Vector3.new(0, 0.4, 0)
	auraAt.Parent = carrier
	local aura = emitter(cast, "Glow", auraAt, {
		Rate = if cast.Low then CONFIG.AURA_PER_SECOND / 2 else CONFIG.AURA_PER_SECOND,
		LockedToPart = true,
		Color = ColorSequence.new(MAIN, EDGE),
		Size = numbers(0, 4, 1, 5),
		Transparency = numbers(0, 0.88, 1, 1), -- ~5 overlap at once: keep each one faint
		Lifetime = NumberRange.new(0.15),
		Brightness = 1,
	})
	aura.Enabled = true

	-- Glow drawn on the floor under the dash (lying flat), and pale dust skimmed off it.
	local floorDrop = root.Position.Y - groundAt(start, flat, character).Position.Y
	local floorAt = Instance.new("Attachment")
	floorAt.Position = Vector3.new(0, -floorDrop + 0.1, 0.5)
	floorAt.Parent = carrier
	-- A flat glowing ribbon (a Trail between two points side by side on the floor): one continuous
	-- streak, where particles at 100 studs/s would leave a row of separate blobs.
	local edgeL, edgeR = Instance.new("Attachment"), Instance.new("Attachment")
	edgeL.Position = floorAt.Position - Vector3.new(CONFIG.GROUND_STREAK_WIDTH / 2, 0, 0)
	edgeR.Position = floorAt.Position + Vector3.new(CONFIG.GROUND_STREAK_WIDTH / 2, 0, 0)
	edgeL.Parent, edgeR.Parent = carrier, carrier
	local groundStreak = templates():WaitForChild("Trail"):Clone() :: Trail
	groundStreak.Name = "GroundStreak"
	groundStreak.Texture = CONFIG.ASSETS.Textures.SoftGlow
	groundStreak.FaceCamera = false
	groundStreak.Attachment0, groundStreak.Attachment1 = edgeL, edgeR
	groundStreak.Lifetime = CONFIG.GROUND_STREAK_SECONDS / cast.TimeScale
	groundStreak.Color = ColorSequence.new(MAIN, EDGE)
	groundStreak.Transparency = numbers(0, 0.35, 1, 1)
	groundStreak.WidthScale = numbers(0, 1, 1, 0.5)
	groundStreak.Brightness = 1.5
	groundStreak.Enabled = true
	groundStreak.Parent = cast.Folder
	local skim: ParticleEmitter? = nil
	if not cast.Low then
		local s = emitter(cast, "Dust", floorAt, {
			EmissionDirection = Enum.NormalId.Back, -- the carrier's +Z: behind
			Rate = CONFIG.SKIM_DUST_PER_SECOND,
			Speed = NumberRange.new(2, 5),
			Size = numbers(0, 0.5, 1, 1.4),
			Transparency = numbers(0, 0.55, 1, 1),
			Lifetime = NumberRange.new(0.3),
			SpreadAngle = Vector2.new(40, 25),
			Acceleration = Vector3.new(0, 2, 0),
		})
		s.Enabled = true
		skim = s
	end

	-- Wind-tunnel rings: upright, facing the dash, bursting open where the body passes.
	local tunnelAt: { number } = {}
	local ringStep = if cast.Low then CONFIG.TUNNEL_RING_EVERY * 2 else CONFIG.TUNNEL_RING_EVERY
	local d = ringStep * 0.6
	while d < distance - 1 do
		table.insert(tunnelAt, d)
		d += ringStep
	end
	local nextTunnel = 1
	local function tunnelRing(at: number)
		local l = layer(cast, "Ring")
		local p = start + flat * at + Vector3.new(0, 0.4, 0)
		local spin = rnd:NextNumber(-1, 1)
		animate(cast, CONFIG.TUNNEL_RING_SECONDS, function(a)
			local cf = CFrame.lookAt(p, p + flat) * CFrame.Angles(math.pi / 2, spin * a, 0)
			local size = CONFIG.TUNNEL_RING_FROM + (CONFIG.TUNNEL_RING_TO - CONFIG.TUNNEL_RING_FROM) * easeOut(a)
			setLayer(l, cf, size / RING_DIAMETER, 0.85 * (1 - a))
		end)
	end

	-- Slicing crescents: peel off round the body at a random angle and drift back while fading.
	local lastSlice = -math.huge
	local function slice()
		local l = layer(cast, "CrescentA")
		local roll = rnd:NextNumber(0, math.pi * 2)
		local base = carrier.CFrame * CFrame.new(0, 0.4, 0.4) * CFrame.Angles(0, 0, roll)
		animate(cast, CONFIG.SLICE_SECONDS, function(a)
			local cf = base * CFrame.new(0, 1.6 + 0.6 * a, 2.2 * a) * CFrame.Angles(math.pi / 2, 0, 0)
			setLayer(l, cf, 1.1 + 0.4 * easeOut(a), 0.9 * (1 - a * a))
		end)
	end

	-- 2 crescents orbiting the dash line around the body.
	local orbits: { Layer } = {}
	if not cast.Low then
		for _ = 1, 2 do
			table.insert(orbits, layer(cast, "CrescentA"))
		end
	end

	local lastGhost = -math.huge
	local stopped = false
	local stoppedAt = 0 -- in this animation's own time (from when the dash began)
	local dashBegan = elapsed(cast)
	local total = seconds + 0.3
	animate(cast, total, function(a)
		local t = a * total
		local moving = not stopped
		local progress = math.clamp(flat:Dot(root.Position - start), 0, distance)
		local visible = if moving then math.min(1, t / 0.05) else math.max(0, 1 - (t - stoppedAt) / 0.25)

		if moving and t - lastGhost >= (if cast.Low then CONFIG.AFTERIMAGE_EVERY * 2 else CONFIG.AFTERIMAGE_EVERY) then
			lastGhost = t
			afterimage(cast)
		end
		if moving and t - lastSlice >= (if cast.Low then CONFIG.SLICE_EVERY * 2 else CONFIG.SLICE_EVERY) then
			lastSlice = t
			slice()
		end
		while tunnelAt[nextTunnel] and progress >= tunnelAt[nextTunnel] do
			tunnelRing(tunnelAt[nextTunnel])
			nextTunnel += 1
		end
		for _, beam in riding do
			fadeBeam(beam, visible)
		end
		for _, s in pathStreaks do
			local front = math.clamp(progress, s.From, s.To)
			s.Head.Position = Vector3.new(s.Offset.X, s.Offset.Y, -front)
			fadeBeam(s.Beam, if front > s.From + 0.5 then visible else 0)
		end
		for i, l in orbits do
			local angle = (i - 1) * math.pi + CONFIG.DASH_ORBIT_TURNS * math.pi * 2 * t
			local cf = carrier.CFrame * CFrame.new(0, 0.4, 0.6) * CFrame.Angles(0, 0, angle)
				* CFrame.new(0, 2, 0) * CFrame.Angles(math.pi / 2, 0, 0)
			setLayer(l, cf, 0.9, 0.85 * visible)
		end
	end)

	local function stop()
		if stopped then
			return
		end
		stopped = true
		stoppedAt = elapsed(cast) - dashBegan
		for _, trail in trails do
			trail.Enabled = false
		end
		sparkles.Enabled = false
		wisps.Enabled = false
		aura.Enabled = false
		groundStreak.Enabled = false
		if skim then
			skim.Enabled = false
		end
		onStop()
	end

	if cast.Moves then
		move(cast, distance, stop)
	else
		-- Someone else's dash: their own client moves them; follow along on the same clock.
		at(cast, elapsed(cast) + seconds, stop)
	end
end

-- ===== 4. Finish + 5. Fade =====

local function finish(cast: Cast)
	local root = cast.Root
	local flat = cast.Flat
	local ground = groundAt(root.Position, flat, cast.Character)
	local finishTotal = CONFIG.FINISH_SECONDS + CONFIG.FADE_SECONDS

	-- Spiral wrapping the body: 1.5 turns/s, 0.6 -> 1.2, fading in then out.
	local spiral = layer(cast, "Spiral")
	animate(cast, CONFIG.FINISH_SECONDS + 0.05, function(a)
		local t = a * (CONFIG.FINISH_SECONDS + 0.05)
		local scale = CONFIG.SPIRAL_SCALE_FROM + (CONFIG.SPIRAL_SCALE_TO - CONFIG.SPIRAL_SCALE_FROM) * easeOut(a)
		local cf = ground * CFrame.Angles(0, -CONFIG.SPIRAL_TURNS * math.pi * 2 * t, 0)
		setLayer(spiral, cf, scale, 0.95 * inOut(a, 0.2, 0.55))
	end)

	-- Swirl flipbook around the body.
	local swirlBox = anchor(cast, "Swirl", ground * CFrame.new(0, 2.6, 0), Vector3.new(2.5, 2.5, 2.5))
	-- Translucent and only a little bright: 7 big additive swirls on top of each other blow out to a
	-- white cloud that hides the body.
	emitter(cast, "Swirl", swirlBox, {
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Size = numbers(0, CONFIG.SWIRL_SIZE, 1, CONFIG.SWIRL_SIZE),
		Lifetime = NumberRange.new(CONFIG.SWIRL_LIFETIME),
		Color = ColorSequence.new(MAIN, EDGE),
		Transparency = numbers(0, 0.5, 0.6, 0.6, 1, 1),
		Brightness = CONFIG.SWIRL_BRIGHTNESS,
	}):Emit(count(cast, CONFIG.SWIRL_PARTICLES))

	-- Rings: 2 expanding at the feet (+ 2 tilted at waist/chest in full); they shrink and fade after.
	-- (from, to studs across, turns/s, tilt degrees, height, brightest alpha)
	local rings = {
		{ 3, 7, 1, 0, 0.06, 0.9 },
		{ 2, 5, -1.3, 0, 0.12, 0.7 },
	}
	if not cast.Low then
		table.insert(rings, { 3.5, 4.6, 1.8, 20, 1.4, 0.75 })
		table.insert(rings, { 3, 4, -2.2, -25, 3, 0.65 })
	end
	for _, spec in rings do
		local from, to, turns, tilt, height, bright = spec[1], spec[2], spec[3], spec[4], spec[5], spec[6]
		local l = layer(cast, "Ring")
		animate(cast, finishTotal, function(a)
			local t = a * finishTotal
			local size, alpha
			if t < CONFIG.FINISH_SECONDS then
				local g = easeOut(t / CONFIG.FINISH_SECONDS)
				size, alpha = from + (to - from) * g, bright * math.min(1, t / 0.06)
			else
				local f = (t - CONFIG.FINISH_SECONDS) / CONFIG.FADE_SECONDS
				size, alpha = to * (1 - 0.35 * easeOut(f)), bright * (1 - f)
			end
			local cf = ground * CFrame.new(0, height, 0) * CFrame.Angles(math.rad(tilt), 0, 0)
				* CFrame.Angles(0, turns * math.pi * 2 * t, 0)
			setLayer(l, cf, size / RING_DIAMETER, alpha)
		end)
	end

	-- 2 crescents circling overhead.
	if not cast.Low then
		for i = 1, 2 do
			local l = layer(cast, "CrescentB")
			animate(cast, CONFIG.FINISH_SECONDS + 0.15, function(a)
				local t = a * (CONFIG.FINISH_SECONDS + 0.15)
				local centre = ground * CFrame.new(0, 4.1 + i * 0.3, 0) * CFrame.Angles(math.rad(i == 1 and 22 or -18), 0, 0)
				local cf = centre * CFrame.Angles(0, i * math.pi - 1.2 * math.pi * 2 * t, 0) * CFrame.new(0, 0, -2.4)
				setLayer(l, cf, 1.3, 0.85 * inOut(a, 0.2, 0.5))
			end)
		end
	end

	-- Wisps and sparkles thrown outward.
	local burstAt = anchor(cast, "FinishBurst", ground * CFrame.new(0, 2.4, 0), Vector3.new(1, 1, 1))
	emitter(cast, "Wisp", burstAt, {
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
		Speed = NumberRange.new(10, 16),
		Drag = 0.5,
		Lifetime = NumberRange.new(0.3, 0.4),
		Acceleration = Vector3.new(0, 3, 0),
	}):Emit(count(cast, CONFIG.FINISH_WISPS))
	emitter(cast, "Sparkle", burstAt, {
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
		Speed = NumberRange.new(3, 5),
		Drag = 2,
	}):Emit(count(cast, CONFIG.FINISH_SPARKLES))

	-- Ground glow where the dash ended (dies out through the fade), and the light.
	local _, glowAt = anchor(cast, "EndGlow", ground * CFrame.new(0, 0.1, 0))
	emitter(cast, "Glow", glowAt, {
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(0.01),
		Color = ColorSequence.new(MAIN),
		Size = numbers(0, 5, 0.3, 7, 1, 5),
		Transparency = numbers(0, 0.5, 0.35, 0.6, 1, 1),
		Lifetime = NumberRange.new(finishTotal),
		Brightness = 1.5,
	}):Emit(1)
	if not cast.Low then
		local light = Instance.new("PointLight")
		light.Color = MAIN
		light.Range = 14
		light.Shadows = false
		light.Parent = glowAt
		animate(cast, finishTotal, function(a)
			light.Brightness = 2.5 * (1 - a) * (1 - a)
		end)
	end

	-- 5. Fade: a few sparkles slowly float up and disappear; a couple of wisps drift off.
	at(cast, elapsed(cast) + CONFIG.FINISH_SECONDS, function()
		local floatBox = anchor(cast, "Float", ground * CFrame.new(0, 2.2, 0), Vector3.new(3, 3, 3))
		emitter(cast, "Sparkle", floatBox, {
			Shape = Enum.ParticleEmitterShape.Box,
			EmissionDirection = Enum.NormalId.Top,
			Speed = NumberRange.new(1, 2),
			Acceleration = Vector3.new(0, 1.5, 0),
			Lifetime = NumberRange.new(CONFIG.FADE_SECONDS),
			Size = numbers(0, 0.2, 0.3, 0.35, 1, 0),
		}):Emit(count(cast, CONFIG.FLOAT_SPARKLES))
		emitter(cast, "Wisp", floatBox, {
			Shape = Enum.ParticleEmitterShape.Box,
			Orientation = Enum.ParticleOrientation.FacingCamera, -- too slow to point along their path
			Rotation = NumberRange.new(-40, 40),
			Speed = NumberRange.new(2, 4),
			Lifetime = NumberRange.new(CONFIG.FADE_SECONDS),
			Transparency = numbers(0, 1, 0.3, 0.5, 1, 1),
		}):Emit(count(cast, 3))
	end)

	-- Everything is faded out by now; clean up.
	at(cast, elapsed(cast) + finishTotal + 0.1, function()
		endCast(cast)
	end)
end

-- ===== playing it =====

local function step(cast: Cast)
	local now = elapsed(cast)
	local i = 1
	while i <= #cast.Anims do
		local anim = cast.Anims[i]
		local a = if anim.Duration > 0 then math.clamp((now - anim.Start) / anim.Duration, 0, 1) else 1
		anim.Update(a)
		if a >= 1 then
			table.remove(cast.Anims, i)
		else
			i += 1
		end
	end
end

local function fovKick(cast: Cast)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local base = camera.FieldOfView
	local out = TweenService:Create(camera, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = base + CONFIG.FOV_KICK })
	out:Play()
	table.insert(cast.Restore, function()
		TweenService:Create(camera, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FieldOfView = base }):Play()
	end)
end

-- Play the dash on a character. Every client runs this for every player who uses it.
-- isLocal = our own character: we play the animation (Roblox replicates it) and move it.
-- aim: the dash direction (the dasher's camera, flattened); only its X/Z are used.
function GaleStepVFX.Play(character: Model, aim: Vector3, isLocal: boolean, options: Options?)
	local timeScale = options and options.TimeScale or 1
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local flat = Vector3.new(aim.X, 0, aim.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit

	local previous = casts[character]
	if previous then
		endCast(previous)
	end
	local f = Instance.new("Folder")
	f.Name = `GaleStep_{character.Name}`
	f.Parent = folder()
	local cast: Cast = {
		Character = character,
		Root = root,
		Folder = f,
		TimeScale = timeScale,
		Low = Quality.Low,
		IsLocal = isLocal,
		Moves = isLocal or (options ~= nil and options.Move == true),
		T0 = os.clock(),
		Flat = flat,
		Anims = {},
		Layers = {},
		Extras = {},
		Connections = {},
		Carrier = nil,
		Ended = false,
		Restore = {},
	}
	casts[character] = cast
	table.insert(cast.Connections, character.Destroying:Connect(function()
		endCast(cast)
	end))
	table.insert(cast.Connections, RunService.RenderStepped:Connect(function()
		step(cast)
	end))

	-- Our own character stands still through the charge (the dash itself is the only movement).
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if isLocal and humanoid then
		local walkSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = 0
		table.insert(cast.Restore, function()
			humanoid.WalkSpeed = walkSpeed
		end)
	end

	local track: AnimationTrack? = nil
	if isLocal or (options and options.PlayAnimation) then
		track = Pose.Track(character, "GaleStep", KEYFRAMES, CONFIG.ASSETS.Animation)
		if track then
			track:Play(0.05)
			track:AdjustSpeed(timeScale)
		end
	end

	charge(cast)
	at(cast, CONFIG.BURST_AT, function()
		burst(cast)
	end)

	local started = false
	local function startDash()
		if started or cast.Ended then
			return
		end
		started = true
		local distance = GaleStepVFX.DashDistance(character, root.Position, flat)
		if isLocal and not (options and options.TimeScale) then
			fovKick(cast)
		end
		dash(cast, distance, function()
			finish(cast)
		end)
	end
	local waitFor = CONFIG.DASH_START
	if track then
		table.insert(cast.Connections, track:GetMarkerReachedSignal("DashStart"):Connect(startDash))
		waitFor += CONFIG.MARKER_GRACE
	end
	at(cast, waitFor, startDash)
end

-- The aim for a dash: where the camera looks, flattened onto the ground.
function GaleStepVFX.Aim(): Vector3?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 0.01 then flat.Unit else nil
end

GaleStepVFX.Config = CONFIG
GaleStepVFX.Keyframes = KEYFRAMES

return GaleStepVFX

--!strict
-- Frost Jab (Uncommon, Melee): an icy punch that slows briefly.
-- Look: images/abilities/frost jab.png (12 panels) + blue flash impact.png (shape only) + frost aura.png
-- + Ice shardsjpg.jpg. Palette #F2FBFF core / #A8E6FF main / #4FA3D9 deep, nothing else.
-- Every asset is made in Blender (Game/assets/frost_jab.blend, Game/assets/vfx/_src/build_frost_jab_*.py):
-- the punch (FrostJabKeyframes, uploaded), the ice meshes (templates in ReplicatedStorage.VFX.FrostJab,
-- built by Game/tools/build_frost_jab_templates.luau) and the textures (ids in CONFIG.ASSETS).
--
-- Built from 4 layers, each its own CONFIG block, in this order (times at normal speed):
--   0. STARTUP    0 – Hit       frost glow on the right fist + a tilted frost ring swirling open round it
--   1. FLASH      Hit (0.133 s) ice star flare + soft glow at the fist, one light; gone in 0.08 s
--   2. MAIN       Hit – +0.6 s  4 ice shards (one of each variant) burst forward from the fist,
--                               pop to full size fast, fly out on a cone and fade slowly
--   3. SECONDARY  on the target frost ring snaps open at its feet with a crown of ice spikes rising,
--                 (server hit)  then widens and fades; cold mist (flipbook) billows over the ring
--   4. RESIDUAL   on the target frost coat over the body (thins for the 1.5 s slow, then breaks),
--                               snowflakes drift up from the head, glints on the body, and ice crumbs
--                               fall off when the slow ends
-- Nothing pops in or out: every piece scales and/or fades.
--
-- Network: the attacker's client plays the animation + 0-2 on the key press (no waiting); everyone
-- else plays 0-2 from AbilityUsed (their animation reaches us by replication, so they run on a
-- timer). The SERVER decides the hit (AbilityService, exact 5 x 5 x 6 box + 1.5 lag margin) and
-- tells every client through AbilityImpact: 3-4 play from FrostJabVFX.Impact. That event carries
-- the server time of the hit; a client that gets it later than CONFIG.SKIP_LATE_AFTER skips it.
--
-- Positions come from the rigs' own attachments (RightGripAttachment on the fist, RootAttachment on
-- the target's HumanoidRootPart) and the ground below them; never fixed world positions.
-- Every duration goes through scaled() (seconds / TIME_SCALE), every emitter gets TimeScale and the
-- animation plays at TIME_SCALE, so /vfxtest frost runs this same code at 0.25x.
--
-- Budget per cast (full quality): 15 VFX objects (9 on the attacker's side: 3 emitters, 1 light, the
-- swirl ring, 4 shards; 6 on the target: ring, crown, 3 emitters, highlight) and at most ~25
-- particles alive (CONFIG emit counts; the limit is CONFIG.BUDGET).
-- Low quality (client/VFX/Quality): 2 shards, no crown, about half the particles.
-- Cleanup: each cast's parts live in a Folder under workspace.ClientVFX; emitters/lights/highlight
-- parented to characters are listed in the cast and destroyed with it (Debris as a backstop).

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Types = require(Shared:WaitForChild("Types"))
local Abilities = require(Config:WaitForChild("Abilities"))
local Rarities = require(Config:WaitForChild("Rarities"))

local Client = script.Parent.Parent
local Quality = require(Client:WaitForChild("VFX"):WaitForChild("Quality"))
local Pose = require(script.Parent.Pose)
local KEYFRAMES = require(script.Parent.FrostJabKeyframes)

local def: Types.AbilityDef? = nil
for _, ability in Abilities do
	if ability.Id == "FrostJab" then
		def = ability
	end
end
assert(def, "FrostJab is missing from Shared/Config/Abilities")

local CONFIG = {
	-- Gameplay: lives in Shared/Config/Abilities (the server reads it); copied here so the whole skill
	-- reads in one place. Damage shown is what a hit deals (base x Uncommon Power).
	DAMAGE = def.Damage * Rarities.Defs[def.Rarity].Power, -- 8
	COOLDOWN = def.Cooldown, -- 3 s
	DURATION = def.DurationSeconds or 0.45,
	HIT_AT = def.WindupSeconds or 4 / 30, -- "Hit" marker, frame 4
	BOX = Vector3.new(def.HitboxWidth or 5, def.HitboxHeight or 5, def.Range), -- + 1.5 lag margin on the server
	SLOW_MULTIPLIER = def.SlowMultiplier or 0.6,
	SLOW_SECONDS = def.SlowSeconds or 1.5,
	MIN_REQUEST_SECONDS = def.MinRequestSeconds or 0.25,

	-- Playback
	TIME_SCALE = 1, -- playback speed; every duration is divided by it (/vfxtest frost: 0.25)
	MARKER_GRACE = 0, -- the timer races the "Hit" marker, first one wins (stage 7: a 0.08 s grace showed the
	-- flash 2 frames late whenever the marker didn't fire, e.g. on a test rig)
	SKIP_LATE_AFTER = 2.0, -- seconds (server time) after the hit: older AbilityImpact events are skipped

	-- Palette (no other colours)
	PALETTE = {
		CORE = "#F2FBFF",
		MAIN = "#A8E6FF",
		DEEP = "#4FA3D9",
	},
	BRIGHTNESS = 1.6, -- glow particles; the place's Bloom threshold is 2

	-- 0. Startup: frost gathering on the fist during the wind-up
	STARTUP = {
		GLOW_COUNT = 2,
		GLOW_SIZE = 1.2, -- studs across at its biggest (stage 7: 1.8 read as a white blob)
		GLOW_LIFETIME = 0.2,
		-- frost swirl around the cocked fist (reference panel 2), the Ring mesh tilted round the arm
		SWIRL_FROM = 1.2, -- studs across
		SWIRL_TO = 3.4,
		SWIRL_TILT_DEG = 65, -- ring plane tilted from upright toward flat
		SWIRL_TURNS = 1.25, -- turns over the wind-up
		SWIRL_FADE_AFTER = 0.06, -- seconds after the hit it has faded out
	},

	-- 1. Flash: brightest and biggest, gone almost at once
	FLASH = {
		SECONDS = 0.1, -- flare + glow lifetime (0.05-0.1 s)
		AHEAD = 1.4, -- studs in front of the fist: the contact point (stage 7: was 0.8, sat on the fist)
		FLARE_SIZE = 6, -- studs across at its biggest: about the target's upper body, as in reference panel 3
		-- (stage 7: 7.5 sat on the fist and read small; 11 at the contact point + bloom whited out the frame)
		FLARE_START = 0.4, -- x FLARE_SIZE on the first frame (grows fast)
		FLARE_BRIGHTNESS = 1.1, -- below the glow layers' BRIGHTNESS so bloom keeps the rays visible
		GLOW_SIZE = 4, -- the star carries the flash (stage 7: glow 7 + light 5 washed the frame out white)
		GLOW_ALPHA = 0.45, -- glow transparency at its brightest
		LIGHT_BRIGHTNESS = 2.5,
		LIGHT_RANGE = 10,
		LIGHT_SECONDS = 0.2, -- fades to 0
		POP_STYLE = Enum.EasingStyle.Exponential,
	},

	-- 2. Main: a few ice shards burst forward from the fist
	MAIN = {
		COUNT = 4, -- one of each variant (ShardA-D), shuffled
		SCALE_FROM = 0.25,
		SCALE_TO = 1.8, -- x the Blender size: 2-3.6 studs long (stage 7: 1.15 was lost behind the target)
		POP_SECONDS = 0.06,
		DISTANCE_MIN = 2, -- studs flown from the contact point: they fan up round the impact and drift
		DISTANCE_MAX = 3.5, -- (stage 7: 6-9 studs threw them out of frame behind the target in 0.03 s)
		TRAVEL_SECONDS = 0.6,
		SPREAD_DEG = 55, -- yaw either side of the punch
		RISE_DEG_MIN = 20, -- pitched up: they burst up and out, like reference panels 4-6
		RISE_DEG_MAX = 50,
		SPIN_DEG = 70, -- roll about their long axis while flying
		FADE_START = 0.3, -- after the hit
		FADE_SECONDS = 0.5,
		POP_STYLE = Enum.EasingStyle.Quint,
		FADE_STYLE = Enum.EasingStyle.Sine,
	},

	-- 3. Secondary: frost ring + ice crown at the target's feet, cold mist
	SECONDARY = {
		RING_FROM = 2, -- studs across
		RING_TO = 7.5, -- stage 7: 5 was much smaller than the reference's ring
		RING_SECONDS = 0.2,
		RING_WIDEN_TO = 9.5, -- keeps widening slowly while it fades (reference panel 6 "ring expands")
		RING_FADE_START = 0.45,
		RING_FADE_SECONDS = 0.55,
		RING_LIFT = 0.06, -- studs above the ground
		RING_GLOW = 7, -- SurfaceAppearance.EmissiveStrength (template: 4)
		CROWN_SCALE = 1.45, -- x the Blender crown (5 studs across, spikes up to 0.87 tall)
		CROWN_RISE_SECONDS = 0.16,
		CROWN_FADE_START = 0.45,
		CROWN_FADE_SECONDS = 0.45,
		MIST_COUNT = 3,
		MIST_SIZE = 6,
		MIST_LIFETIME = 0.6, -- the 16-frame flipbook plays exactly once over it
		MIST_ALPHA = 0.3, -- transparency at its thickest
		POP_STYLE = Enum.EasingStyle.Quint,
		FADE_STYLE = Enum.EasingStyle.Sine,
	},

	-- 4. Residual: leftovers that linger 0.5-1.5 s (the slow's length)
	RESIDUAL = {
		COAT_IN_SECONDS = 0.06,
		COAT_FILL = 0.45, -- Highlight FillTransparency right after the hit...
		COAT_FILL_END = 0.8, -- ...thinning to this by the end of the slow
		COAT_OUTLINE = 0.35,
		COAT_BREAK_SECONDS = 0.25, -- fades out when the slow ends
		SNOWFLAKES = 3,
		SNOWFLAKE_SIZE = 0.7,
		SNOWFLAKE_LIFETIME = 1.3,
		SNOWFLAKE_RISE = 1.4, -- studs/s
		GLINTS = 10,
		GLINT_SIZE = 0.4,
		GLINT_LIFETIME_MIN = 0.5,
		GLINT_LIFETIME_MAX = 1.0,
		CRUMBS = 12, -- ice crumbs falling off when the slow ends
		CRUMB_SIZE = 0.3,
		CRUMB_LIFETIME = 0.5,
		CRUMB_GRAVITY = 30,
	},

	BUDGET = { PARTICLES = 120, INSTANCES = 15 },

	-- Asset ids (uploaded with Open Cloud; Game/assets/vfx/frost_jab_assets.json). Mesh ids are carried
	-- by the templates (they can't be set at runtime).
	ASSETS = {
		Animation = def.AnimationId or "rbxassetid://78544021138400", -- FrostJab_Punch, marker "Hit"
		Textures = {
			Flare = "rbxassetid://99043809496162", -- frost_flare.png
			Snowflake = "rbxassetid://94567728717612", -- frost_snowflake.png
			MistFlipbook = "rbxassetid://101720520240051", -- frost_mist_flipbook.png, 4x4 = 16 frames
			Sparkle = "rbxassetid://76795312198770", -- sparkle.png (Gale Step)
			Glow = "rbxassetid://134061496595746", -- soft_glow.png (Gale Step)
		},
	},
}

export type Options = {
	TimeScale: number?, -- playback speed (default CONFIG.TIME_SCALE); /vfxtest plays at 0.25
	PlayAnimation: boolean?, -- play the punch on this character (always for our own)
	LocalTarget: Model?, -- VFX test: play the on-hit VFX on this model at the hit (no server)
}

export type Impact = { Target: Model, Position: Vector3 }

type Cast = {
	Folder: Folder,
	TimeScale: number,
	Low: boolean,
	Extras: { Instance }, -- made outside the folder (on characters)
	Connections: { RBXScriptConnection },
	Count: number, -- VFX objects made (budget)
	Ended: boolean,
}

local FrostJabVFX = {}

local impactsOn: { [Model]: Cast } = setmetatable({}, { __mode = "k" }) :: any -- newest on-hit cast per target
local vfxFolder: Folder? = nil

local function color(hex: string): Color3
	return Color3.fromHex(hex)
end

local function numbers(...: number): NumberSequence
	local values = { ... }
	local points = {}
	for i = 1, #values, 2 do
		table.insert(points, NumberSequenceKeypoint.new(values[i], values[i + 1]))
	end
	return NumberSequence.new(points)
end

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

local function template(name: string): MeshPart
	return ReplicatedStorage:WaitForChild("VFX"):WaitForChild("FrostJab"):WaitForChild(name) :: MeshPart
end

local function newCast(name: string, timeScale: number): Cast
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = folder()
	return { Folder = f, TimeScale = timeScale, Low = Quality.Low, Extras = {}, Connections = {}, Count = 0, Ended = false }
end

local function scaled(cast: Cast, seconds: number): number
	return seconds / cast.TimeScale
end

-- Counts every VFX object against the budget; things parented outside the folder are kept for cleanup.
local function track(cast: Cast, instance: Instance, outside: boolean?)
	cast.Count += 1
	cast.Folder:SetAttribute("VFXObjects", cast.Count)
	if outside then
		table.insert(cast.Extras, instance)
		Debris:AddItem(instance, scaled(cast, 4)) -- backstop if the cast is never ended
	end
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
	for _, extra in cast.Extras do
		extra:Destroy()
	end
	table.clear(cast.Extras)
	cast.Folder:Destroy()
end

local function after(cast: Cast, seconds: number, fn: () -> ())
	task.delay(scaled(cast, seconds), function()
		if not cast.Ended then
			fn()
		end
	end)
end

local function tween(cast: Cast, instance: Instance, seconds: number, style: Enum.EasingStyle, direction: Enum.EasingDirection, goal: { [string]: any })
	TweenService:Create(instance, TweenInfo.new(scaled(cast, seconds), style, direction), goal):Play()
end

local function emitter(cast: Cast, parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.Rate = 0
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Brightness = CONFIG.BRIGHTNESS
	e.TimeScale = cast.TimeScale
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	track(cast, e, not parent:IsDescendantOf(cast.Folder))
	return e
end

local function count(cast: Cast, full: number): number
	return if cast.Low then math.max(1, math.floor(full / 2)) else full
end

-- A clone of a mesh template, placed so its Blender origin (shard base / ring centre) is at `origin`.
local function mesh(cast: Cast, name: string, origin: CFrame, scale: Vector3): MeshPart
	local base = template(name)
	local part = base:Clone()
	part.Size = base.Size * scale
	local offset = (base:GetAttribute("OriginFromCentre") :: Vector3?) or Vector3.zero
	part.CFrame = origin * CFrame.new(-offset * scale)
	part.Parent = cast.Folder
	track(cast, part)
	return part
end

local function groundBelow(position: Vector3, ignore: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local result = workspace:Raycast(position, Vector3.new(0, -12, 0), params)
	return if result then result.Position else position - Vector3.new(0, 3, 0)
end

local function fistAttachment(character: Model): Attachment?
	local hand = character:FindFirstChild("RightHand")
	local grip = hand and hand:FindFirstChild("RightGripAttachment")
	return if grip and grip:IsA("Attachment") then grip else nil
end

-- ===== 0. Startup =====
local function startup(cast: Cast, fist: Attachment, flat: Vector3)
	local cfg = CONFIG.STARTUP
	local glow = emitter(cast, fist, {
		Name = "FrostJabFistGlow",
		Texture = CONFIG.ASSETS.Textures.Glow,
		Color = ColorSequence.new(color(CONFIG.PALETTE.CORE), color(CONFIG.PALETTE.MAIN)),
		Size = numbers(0, cfg.GLOW_SIZE * 0.3, 0.3, cfg.GLOW_SIZE, 1, cfg.GLOW_SIZE * 0.6),
		Transparency = numbers(0, 0.6, 0.25, 0.15, 1, 1),
		Lifetime = NumberRange.new(cfg.GLOW_LIFETIME),
		Speed = NumberRange.new(0),
		LockedToPart = true, -- rides on the fist
		ZOffset = 1,
	})
	glow:Emit(cfg.GLOW_COUNT)

	-- Frost swirl: the Ring mesh round the fist, tilted, spinning and opening up through the wind-up,
	-- fading out just after the hit. It follows the fist every frame.
	local ringBase = template("Ring")
	local swirl = mesh(cast, "Ring", CFrame.new(fist.WorldPosition), Vector3.one * cfg.SWIRL_FROM / ringBase.Size.X)
	swirl.Transparency = 1
	local look = swirl:FindFirstChildOfClass("SurfaceAppearance")
	if look then
		look.EmissiveStrength = CONFIG.SECONDARY.RING_GLOW
	end
	local right = flat:Cross(Vector3.yAxis)
	local tilt = CFrame.fromAxisAngle(right, math.rad(cfg.SWIRL_TILT_DEG))
	local windup = CONFIG.HIT_AT
	local total = windup + cfg.SWIRL_FADE_AFTER
	local started = os.clock()
	table.insert(cast.Connections, RunService.RenderStepped:Connect(function()
		local t = (os.clock() - started) * cast.TimeScale -- game seconds
		if t > total or not fist.Parent then
			swirl.Transparency = 1
			return
		end
		local a = math.min(1, t / windup)
		local grow = 1 - (1 - a) ^ 3 -- fast, then easing (Cubic Out)
		local across = cfg.SWIRL_FROM + (cfg.SWIRL_TO - cfg.SWIRL_FROM) * grow
		swirl.Size = ringBase.Size * (across / ringBase.Size.X)
		local spin = CFrame.Angles(0, -math.pi * 2 * cfg.SWIRL_TURNS * a, 0)
		swirl.CFrame = CFrame.new(fist.WorldPosition) * tilt * spin
		-- fades in over the first third, holds, fades out after the hit
		swirl.Transparency = if t <= windup
			then 1 - math.min(1, t / (windup / 3)) * 0.85
			else 0.15 + 0.85 * (t - windup) / cfg.SWIRL_FADE_AFTER
	end))
end

-- ===== 1. Flash =====
local function flash(cast: Cast, fist: Attachment, flat: Vector3)
	local cfg = CONFIG.FLASH
	-- The flare and glow sit AHEAD studs in front of the fist: the attachment's offset in the hand.
	local hand = fist.Parent :: BasePart
	local at = Instance.new("Attachment")
	at.Name = "FrostJabFlash"
	at.Parent = hand -- parent first: WorldPosition on an unparented attachment becomes a local offset
	at.WorldPosition = fist.WorldPosition + flat * cfg.AHEAD
	table.insert(cast.Extras, at)
	emitter(cast, at, {
		Name = "FrostJabFlare",
		Texture = CONFIG.ASSETS.Textures.Flare,
		Color = ColorSequence.new(color(CONFIG.PALETTE.CORE), color(CONFIG.PALETTE.MAIN)),
		Size = numbers(0, cfg.FLARE_SIZE * cfg.FLARE_START, 0.3, cfg.FLARE_SIZE, 1, cfg.FLARE_SIZE * 0.9),
		Transparency = numbers(0, 0, 0.5, 0.1, 1, 1),
		Lifetime = NumberRange.new(cfg.SECONDS),
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(-15, 15),
		Brightness = cfg.FLARE_BRIGHTNESS,
		ZOffset = 3,
	}):Emit(1)
	emitter(cast, at, {
		Name = "FrostJabFlashGlow",
		Texture = CONFIG.ASSETS.Textures.Glow,
		Color = ColorSequence.new(color(CONFIG.PALETTE.CORE), color(CONFIG.PALETTE.MAIN)),
		Size = numbers(0, cfg.GLOW_SIZE * 0.5, 0.3, cfg.GLOW_SIZE, 1, cfg.GLOW_SIZE * 1.1),
		Transparency = numbers(0, cfg.GLOW_ALPHA, 0.4, cfg.GLOW_ALPHA + 0.2, 1, 1),
		Lifetime = NumberRange.new(cfg.SECONDS * 1.25),
		Speed = NumberRange.new(0),
		ZOffset = 2,
	}):Emit(1)
	local light = Instance.new("PointLight")
	light.Color = color(CONFIG.PALETTE.MAIN)
	light.Brightness = cfg.LIGHT_BRIGHTNESS
	light.Range = cfg.LIGHT_RANGE
	light.Shadows = false
	light.Parent = at
	track(cast, light, true)
	tween(cast, light, cfg.LIGHT_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Brightness = 0 })
end

-- ===== 2. Main: shards =====
local function shards(cast: Cast, from: Vector3, flat: Vector3)
	local cfg = CONFIG.MAIN
	local names = { "ShardA", "ShardB", "ShardC", "ShardD" }
	for i = #names, 2, -1 do
		local j = math.random(i)
		names[i], names[j] = names[j], names[i]
	end
	local right = flat:Cross(Vector3.yAxis)
	local n = if cast.Low then 2 else cfg.COUNT
	for i = 1, n do
		-- spread evenly across the cone (+ a little jitter) so they don't clump
		local yaw = math.rad(-cfg.SPREAD_DEG + 2 * cfg.SPREAD_DEG * (i - 0.5) / n + (math.random() - 0.5) * 8)
		local rise = math.rad(cfg.RISE_DEG_MIN + math.random() * (cfg.RISE_DEG_MAX - cfg.RISE_DEG_MIN))
		local dir = (CFrame.fromAxisAngle(Vector3.yAxis, yaw) * CFrame.fromAxisAngle(right, rise)):VectorToWorldSpace(flat)
		-- the shard's long axis (+Y in the mesh) points along its flight
		local function along(position: Vector3, roll: number): CFrame
			return CFrame.lookAt(position, position + dir) * CFrame.Angles(-math.pi / 2, roll, 0)
		end
		local roll0 = math.random() * math.pi * 2
		local part = mesh(cast, names[(i - 1) % #names + 1], along(from, roll0), Vector3.one * cfg.SCALE_FROM)
		local full = template(part.Name).Size * cfg.SCALE_TO
		local distance = cfg.DISTANCE_MIN + math.random() * (cfg.DISTANCE_MAX - cfg.DISTANCE_MIN)
		tween(cast, part, cfg.POP_SECONDS, cfg.POP_STYLE, Enum.EasingDirection.Out, { Size = full })
		tween(cast, part, cfg.TRAVEL_SECONDS, cfg.POP_STYLE, Enum.EasingDirection.Out,
			{ CFrame = along(from + dir * distance, roll0 + math.rad(cfg.SPIN_DEG)) * CFrame.new(0, full.Y / 2, 0) })
		after(cast, cfg.FADE_START, function()
			tween(cast, part, cfg.FADE_SECONDS, cfg.FADE_STYLE, Enum.EasingDirection.In, { Transparency = 1 })
		end)
	end
end

-- Play the punch on a character. Every client runs this for every player who uses it.
-- isLocal = our own character: we play the animation (Roblox replicates it to everyone else).
function FrostJabVFX.Play(character: Model, aim: Vector3, isLocal: boolean, options: Options?)
	local timeScale = options and options.TimeScale or CONFIG.TIME_SCALE
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local fist = fistAttachment(character)
	if not root or not fist then
		return
	end
	local flat = Vector3.new(aim.X, 0, aim.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit

	local cast = newCast(`FrostJab_{character.Name}`, timeScale)
	local destroying = character.Destroying:Connect(function()
		endCast(cast)
	end)

	local track: AnimationTrack? = nil
	if isLocal or (options and options.PlayAnimation) then
		track = Pose.Track(character, "FrostJab", KEYFRAMES, CONFIG.ASSETS.Animation)
		if track then
			track:Play(0.05)
			track:AdjustSpeed(timeScale)
		end
	end

	startup(cast, fist, flat)

	local hit = false
	local function onHit()
		if hit or cast.Ended or not fist.Parent then
			return
		end
		hit = true
		flash(cast, fist, flat)
		shards(cast, fist.WorldPosition + flat * CONFIG.FLASH.AHEAD, flat) -- from the contact point
		local target = options and options.LocalTarget
		local targetRoot = target and target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if target and targetRoot then
			FrostJabVFX.Impact(character, { { Target = target, Position = targetRoot.Position } }, nil, { TimeScale = timeScale })
		end
		local main = CONFIG.MAIN
		after(cast, math.max(main.FADE_START + main.FADE_SECONDS, main.TRAVEL_SECONDS, CONFIG.FLASH.LIGHT_SECONDS) + 0.1, function()
			destroying:Disconnect()
			endCast(cast)
		end)
	end
	local waitFor = CONFIG.HIT_AT
	if track then
		local marker: RBXScriptConnection
		marker = track:GetMarkerReachedSignal("Hit"):Connect(function()
			marker:Disconnect()
			onHit()
		end)
		waitFor += CONFIG.MARKER_GRACE
	end
	after(cast, waitFor, onHit)
end

-- ===== 3 + 4. On the target (the server decided the hit) =====
local function onTarget(attacker: Model, target: Model, timeScale: number, age: number)
	local root = target:FindFirstChild("HumanoidRootPart") :: BasePart?
	local rootAttachment = root and root:FindFirstChild("RootAttachment")
	if not root or not rootAttachment or not rootAttachment:IsA("Attachment") then
		return
	end
	local previous = impactsOn[target]
	if previous then
		endCast(previous) -- a new hit refreshes the frost (the slow doesn't stack either)
	end
	local cast = newCast(`FrostJabHit_{target.Name}`, timeScale)
	impactsOn[target] = cast
	local destroying = target.Destroying:Connect(function()
		endCast(cast)
	end)
	local sec, res = CONFIG.SECONDARY, CONFIG.RESIDUAL
	local slowLeft = math.max(0.2, CONFIG.SLOW_SECONDS - age)

	-- 3. Secondary: ring + crown on the ground below the target's root, mist over them
	local feet = groundBelow(rootAttachment.WorldPosition, { target, attacker, folder() }) + Vector3.new(0, sec.RING_LIFT, 0)
	local ground = CFrame.new(feet)
	local ringBase = template("Ring").Size.X
	local ring = mesh(cast, "Ring", ground, Vector3.new(1, 1, 1) * sec.RING_FROM / ringBase)
	ring.Transparency = 0.6
	local ringLook = ring:FindFirstChildOfClass("SurfaceAppearance")
	if ringLook then
		ringLook.EmissiveStrength = sec.RING_GLOW
	end
	tween(cast, ring, sec.RING_SECONDS, sec.POP_STYLE, Enum.EasingDirection.Out,
		{ Size = template("Ring").Size * (sec.RING_TO / ringBase), Transparency = 0 })
	after(cast, sec.RING_SECONDS, function()
		tween(cast, ring, sec.RING_FADE_START + sec.RING_FADE_SECONDS - sec.RING_SECONDS, sec.FADE_STYLE, Enum.EasingDirection.Out,
			{ Size = template("Ring").Size * (sec.RING_WIDEN_TO / ringBase) })
	end)
	after(cast, sec.RING_FADE_START, function()
		tween(cast, ring, sec.RING_FADE_SECONDS, sec.FADE_STYLE, Enum.EasingDirection.In, { Transparency = 1 })
	end)

	if not cast.Low then
		-- spikes rise out of the ground: height grows from ~0 with the base kept on the ground
		local crownBase = template("Crown")
		local flatScale = Vector3.new(sec.CROWN_SCALE, 0.05, sec.CROWN_SCALE)
		local fullScale = Vector3.one * sec.CROWN_SCALE
		local offset = (crownBase:GetAttribute("OriginFromCentre") :: Vector3?) or Vector3.zero
		local crown = mesh(cast, "Crown", ground, flatScale)
		tween(cast, crown, sec.CROWN_RISE_SECONDS, sec.POP_STYLE, Enum.EasingDirection.Out,
			{ Size = crownBase.Size * fullScale, CFrame = ground * CFrame.new(-offset * fullScale) })
		after(cast, sec.CROWN_FADE_START, function()
			tween(cast, crown, sec.CROWN_FADE_SECONDS, sec.FADE_STYLE, Enum.EasingDirection.In, { Transparency = 1 })
		end)
	end

	-- cold mist: emitted from the ring's own volume, so it billows across the ring
	emitter(cast, ring, {
		Name = "FrostJabMist",
		Texture = CONFIG.ASSETS.Textures.MistFlipbook,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		FlipbookFramerate = NumberRange.new(16 / sec.MIST_LIFETIME), -- ends exactly when the particle dies
		FlipbookStartRandom = false,
		Color = ColorSequence.new(color(CONFIG.PALETTE.CORE), color(CONFIG.PALETTE.MAIN)),
		LightEmission = 0.6,
		Size = numbers(0, sec.MIST_SIZE * 0.7, 0.5, sec.MIST_SIZE, 1, sec.MIST_SIZE * 1.15),
		Transparency = numbers(0, sec.MIST_ALPHA, 0.6, sec.MIST_ALPHA + 0.15, 1, 1),
		Lifetime = NumberRange.new(sec.MIST_LIFETIME),
		Speed = NumberRange.new(0.5, 1.5),
		EmissionDirection = Enum.NormalId.Top,
		Rotation = NumberRange.new(0, 360),
		ZOffset = 0,
	}):Emit(count(cast, sec.MIST_COUNT))

	-- 4. Residual: frost coat over the body, thinning for the rest of the slow, then breaking
	local coat = Instance.new("Highlight")
	coat.Name = "FrostJabCoat"
	coat.Adornee = target
	coat.FillColor = color(CONFIG.PALETTE.MAIN)
	coat.OutlineColor = color(CONFIG.PALETTE.CORE)
	coat.FillTransparency = 1
	coat.OutlineTransparency = 1
	coat.DepthMode = Enum.HighlightDepthMode.Occluded
	coat.Parent = target
	track(cast, coat, true)
	tween(cast, coat, res.COAT_IN_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out,
		{ FillTransparency = res.COAT_FILL, OutlineTransparency = res.COAT_OUTLINE })
	after(cast, res.COAT_IN_SECONDS, function()
		tween(cast, coat, slowLeft - res.COAT_IN_SECONDS, Enum.EasingStyle.Linear, Enum.EasingDirection.In,
			{ FillTransparency = res.COAT_FILL_END })
	end)

	local head = target:FindFirstChild("Head")
	local torso = target:FindFirstChild("UpperTorso") or root
	if head and head:IsA("BasePart") then
		emitter(cast, head, {
			Name = "FrostJabSnowflakes",
			Texture = CONFIG.ASSETS.Textures.Snowflake,
			Color = ColorSequence.new(color(CONFIG.PALETTE.CORE), color(CONFIG.PALETTE.MAIN)),
			Size = numbers(0, 0, 0.2, res.SNOWFLAKE_SIZE, 1, res.SNOWFLAKE_SIZE * 0.6),
			Transparency = numbers(0, 1, 0.15, 0.1, 0.7, 0.3, 1, 1),
			Lifetime = NumberRange.new(res.SNOWFLAKE_LIFETIME),
			Speed = NumberRange.new(res.SNOWFLAKE_RISE),
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(35, 35),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-40, 40),
			ZOffset = 1,
		}):Emit(count(cast, res.SNOWFLAKES))
	end
	local glints = emitter(cast, torso, {
		Name = "FrostJabGlints",
		Texture = CONFIG.ASSETS.Textures.Sparkle,
		Color = ColorSequence.new(color(CONFIG.PALETTE.CORE), color(CONFIG.PALETTE.MAIN)),
		Size = numbers(0, 0, 0.25, res.GLINT_SIZE, 1, 0),
		Transparency = numbers(0, 0.3, 0.5, 0.1, 1, 1),
		Lifetime = NumberRange.new(res.GLINT_LIFETIME_MIN, res.GLINT_LIFETIME_MAX),
		Speed = NumberRange.new(0.3, 1),
		SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(-20, 20),
		ZOffset = 1.5,
	})
	glints:Emit(count(cast, res.GLINTS))

	-- The slow ends: the coat breaks, ice crumbs fall off (the glint emitter, re-shaped: its own
	-- glints are long gone by now).
	after(cast, slowLeft, function()
		tween(cast, coat, res.COAT_BREAK_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In,
			{ FillTransparency = 1, OutlineTransparency = 1 })
		glints.Size = numbers(0, res.CRUMB_SIZE, 0.7, res.CRUMB_SIZE, 1, 0)
		glints.Transparency = numbers(0, 0.1, 0.6, 0.2, 1, 1)
		glints.Squash = numbers(0, -0.6, 1, -0.6) -- a little stretched along their fall
		glints.Lifetime = NumberRange.new(res.CRUMB_LIFETIME)
		glints.Speed = NumberRange.new(1, 3)
		glints.Acceleration = Vector3.new(0, -res.CRUMB_GRAVITY, 0)
		glints:Emit(count(cast, res.CRUMBS))
		after(cast, math.max(res.COAT_BREAK_SECONDS, res.CRUMB_LIFETIME) + 0.05, function()
			destroying:Disconnect()
			if impactsOn[target] == cast then
				impactsOn[target] = nil
			end
			endCast(cast)
		end)
	end)
end

-- The server says this attacker's punch hit these targets at serverTime (workspace:GetServerTimeNow()).
-- serverTime = nil: a local test hit, play it now.
function FrostJabVFX.Impact(attacker: Model, hits: { Impact }, serverTime: number?, options: Options?)
	local timeScale = options and options.TimeScale or CONFIG.TIME_SCALE
	local age = if serverTime then math.max(0, workspace:GetServerTimeNow() - serverTime) else 0
	if age > CONFIG.SKIP_LATE_AFTER then
		return -- already over for everyone else: don't start it late
	end
	for _, hit in hits do
		if typeof(hit) == "table" and typeof(hit.Target) == "Instance" and hit.Target:IsA("Model") and hit.Target.Parent then
			onTarget(attacker, hit.Target, timeScale, age)
		end
	end
end

FrostJabVFX.Config = CONFIG
FrostJabVFX.Keyframes = KEYFRAMES

return FrostJabVFX

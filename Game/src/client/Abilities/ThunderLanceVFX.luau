--!strict
-- Thunder Lance (Rare, Projectile): a fast lightning spear.
-- Look: images/abilities/thunder_lance_blueprint.png + Prompts/thunder_lance_prompt (sections 0 and 5).
-- Palette #FFFDF0 white / #FFE14D yellow / #FFB000 deep gold; #9FD8FF ONLY on small sparks; #4A3200
-- (a dark tint of the gold) ONLY as the trail bolt's afterimage (Vault: one dark layer per bright stack).
-- Every asset is made in Blender (Game/assets/thunder_lance.blend, Game/assets/vfx/_src/build_thunder_lance_*.py):
-- the throw (ThunderLanceKeyframes, uploaded), the meshes (templates in ReplicatedStorage.VFX.ThunderLance,
-- built by Game/tools/build_thunder_lance_templates.luau) and the textures (ids in CONFIG.ASSETS).
--
-- Layers (times at normal speed; frames @ 30 fps), each its own CONFIG block:
--   CRACKLE    SECONDARY  F4-F8 ("Summon")  2-3 short procedural bolts + 4 tiny sparks round the right hand
--   FORM       MAIN       F8-F12            the spear grows from the grip, length 0 -> 6 over 4 frames
--                                           (Quint Out); held in the hand, aimed (CONFIG.HOLD) until F15
--   SPEAR      MAIN       F8 - flight       Neon core + inner glow Beam + crossed ribbons spinning 4 turns/s
--   RELEASE    FLASH      F15 ("Release")   8-point star 5 studs at the hand, gone in 0.08 s; the light
--                                           flashes; a small camera shake for the thrower only
--   LIGHT      SECONDARY  flight            ONE PointLight per shot (Vault): the release flash, then the
--                                           spear's glow (range 12, brightness 2), then the impact pulse
--   CRACKLE TRAIL MAIN    flight            a bolt from the spear's tail back 10-14 studs, 10 segments,
--                                           riding on the spear, redrawn every 2 frames; the old one
--                                           stays put and fades over 0.1 s as a dark-gold afterimage
--                                           + a Trail (streak.png, 0.15 s, 0.6 -> 0)
--   SHED       RESIDUAL   flight            ~40 sparks/s (yellow, a few blue) streaking off the spear
--   IMPACT     FLASH      hit + 1 frame     star 5 studs, 0.08 s (1 frame late, so the contact is seen)
--              MAIN                         40 sparks (speed 30-50, drag 6) + 5-6 bolts 2-4 studs outward
--              SECONDARY                    shock ring flat on the surface hit, 1 -> 6 studs in 0.2 s, fading
--              RESIDUAL   +0-0.6 s          2-3 arcs jumping between neighbouring limbs (outside the
--                                           body) every 3 frames
--              RESIDUAL   +0-2 s            scorch (6 studs) on the floor below (if within 6 studs), fades the last 1 s
--   STRIKE (stage 7B, Prompts/thunder_lance_lighting_strike_prompt): after a CHARACTER hit only, a
--   lightning strike comes down on the target (times after the spear's impact):
--              SECONDARY  0-0.15 s          charge: 3-4 bolts crawling on a 6-stud circle 40 studs up, a
--                                           dim gold light, small crackles on the target's head
--              MAIN       0.15-0.44 s       the bolt from 45 studs up to the ground below the target: 18
--                                           segments x 3 layers (outer gold, yellow, white core) + 4-6
--                                           branches (2 layers); 3 strokes, each redrawn and weaker,
--                                           dipping to 35% between them, the last fading (Vault: < 0.3 s)
--              FLASH      0.15 s            the light jumps to the ground (range 60), a 16-stud star, a
--                                           local screen flash within 80 studs (max 3 a second)
--              SECONDARY  0.15-0.45 s       shock ring on the ground 2 -> 16 studs + a dust ring (floor colour)
--              MAIN       0.15-1.2 s        10-14 rock chunks thrown up and out, landing, fading
--                         0.15-0.5 s        camera shake, strongest at the target, none past 80 studs
--              RESIDUAL   0.2-1.5 s         a column of dark smoke
--              RESIDUAL   0.45-1.0 s        small arcs jumping along the ground, shrinking
--              RESIDUAL   0.15-3.15 s       a 10-stud crater (instead of the scorch) with glowing gold
--                                           cracks that cool over 1.5 s; the crater fades the last 1 s
-- Nothing pops in or out: every piece scales and/or fades.
--
-- Network (AbilityService.useClockProjectile; Vault: Replicating VFX - server validates, clients render):
--   * The thrower's client plays the animation and every layer at once, and launches its own spear on
--     the "Release" marker (the timer races it). Its flight stops where its own sweep (shared/Projectile,
--     the same as the server's) first touches something; the impact plays when the server says so.
--   * Everyone else gets AbilityUsed (animation by replication, the spear forming in the hand on a timer)
--     and AbilityLaunch (origin, direction, server start time, seed): their spear flies on the SERVER
--     clock, so a late client starts it further along instead of stuttering. The server never sends the
--     launch back to the thrower.
--   * The server decides the hit and sends AbilityHit to everyone (point, normal, target, server time,
--     seed): the impact plays at that exact point, and the seed makes its bolts the same everywhere.
--     Older than CONFIG.SKIP_LATE_AFTER: skipped. At full range there is no hit: the spear fades out.
--   * A character hit is followed at once by AbilityStrike (target, ground position, server time, seed):
--     every client plays the strike at that ground position, even if the target is already gone.
--
-- Every duration goes through scaled() (seconds / TIME_SCALE), every emitter gets TimeScale, the
-- animation plays at TIME_SCALE and bolts take it, so /vfxtest lance runs this same code at 0.25x.
-- Budget per cast (CONFIG.BUDGET): 150 particles alive, 30 Beams, 20 other VFX objects; the count is
-- kept on each cast's Folder (attributes VFXObjects, BeamsPeak). Bolts further than 200 studs from the
-- camera aren't drawn (LightningBolt).
-- Cleanup: each cast's parts live in a Folder under workspace.ClientVFX and go with it; the bolts' Beams
-- are pooled on one holder (workspace.ClientVFX.LightningBolts), which stays and stops growing once warm.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Projectile = require(Shared:WaitForChild("Projectile"))
local Types = require(Shared:WaitForChild("Types"))
local Abilities = require(Config:WaitForChild("Abilities"))
local Rarities = require(Config:WaitForChild("Rarities"))

local Client = script.Parent.Parent
local VFX = Client:WaitForChild("VFX")
local Quality = require(VFX:WaitForChild("Quality"))
local LightningBolt = require(VFX:WaitForChild("LightningBolt"))
local Pose = require(script.Parent.Pose)
local KEYFRAMES = require(script.Parent.ThunderLanceKeyframes)

local def: Types.AbilityDef? = nil
for _, ability in Abilities do
	if ability.Id == "ThunderLance" then
		def = ability
	end
end
assert(def, "ThunderLance is missing from Shared/Config/Abilities")

local CONFIG = {
	-- Gameplay: lives in Shared/Config/Abilities (the server reads it); copied here so the whole skill
	-- reads in one place. Damage shown is what a hit deals (base x Rare Power).
	DAMAGE = def.Damage * Rarities.Defs[def.Rarity].Power, -- 18 (balance number)
	COOLDOWN = def.Cooldown, -- 6 s (balance number)
	SPEED = def.ProjectileSpeed or 160, -- studs/s (balance number)
	RANGE = def.Range, -- 120 studs (balance number)
	HITBOX_RADIUS = def.HitboxRadius or 2.5, -- studs (balance number); bigger than the spear on purpose
	BODY_RADIUS = def.ProjectileRadius or 0.175, -- the spear itself: walls and the ground
	MIN_REQUEST_SECONDS = def.MinRequestSeconds or 0.25,
	SUMMON_AT = 4 / 30, -- "Summon" marker, frame 4
	FORM_AT = 8 / 30, -- the spear starts to grow, frame 8
	RELEASE_AT = def.WindupSeconds or 15 / 30, -- "Release" marker, frame 15 (= the server's wind-up)
	LEAD = def.ProjectileLead or 4, -- the tip is this far ahead of the grip; the flight tracks the tip

	-- Sky strike (stage 7B): gameplay + the switches players and tuning need
	SKY_STRIKE = def.SkyStrike == true, -- a character hit calls the strike down (Shared/Config/Abilities)
	STRIKE_DAMAGE = def.StrikeDamage or 0, -- balance number (Shared/Config/Abilities): 0 = visual only
	SHAKE_MAX = 2.2, -- degrees of camera shake at the strike's target; 0 at STRIKE.SHAKE_RADIUS
	SCREEN_FLASH_ENABLED = true, -- the local screen flash (ColorCorrectionEffect on this client's camera)
	REDUCE_FLASHING = false, -- true: no dips between strokes, the star and screen flash much dimmer
	STRIKE_SOUND_ID = "", -- played at the ground position when set (a close thunder crack)

	-- Playback
	TIME_SCALE = 1, -- playback speed; every duration is divided by it (/vfxtest lance: 0.25)
	SKIP_LATE_AFTER = 2.0, -- seconds (server time) after the hit: older AbilityHit events are skipped
	SERVER_HIT_WAIT = 1.0, -- our spear stopped on something: wait this long for the server's hit
	LAUNCH_WAIT = 1.5, -- another player's spear: no AbilityLaunch this long after the cast = rejected

	-- Palette (no other colours)
	PALETTE = {
		WHITE = "#FFFDF0",
		YELLOW = "#FFE14D",
		GOLD = "#FFB000",
		SPARK_BLUE = "#9FD8FF", -- small sparks only
		AFTERIMAGE = "#4A3200", -- the trail bolt's afterimage only
	},
	BRIGHTNESS = 1.6, -- glow particles; the place's Bloom threshold is 2

	-- CRACKLE (SECONDARY): electricity gathering in the hand, Summon -> spear formed
	CRACKLE = {
		BOLTS_MIN = 2,
		BOLTS_MAX = 3,
		LENGTH = 0.6, -- studs
		SEGMENTS = 4,
		OFFSET = 0.15,
		THICKNESS = 0.07,
		EVERY_FRAMES = 2, -- redrawn
		SPARKS = 4,
		SPARK_SIZE = 0.25,
		SPARK_LIFETIME = 0.25,
	},

	-- FORM + held in the hand (MAIN)
	FORM = {
		GROW_FRAMES = 4, -- length 0 -> 6 studs
		GROW_STYLE = Enum.EasingStyle.Quint, -- Out
		-- the spear's pitch above level while held (deg, by frame): level at F8, tip at eye level F12-F13
		-- (thunder_lance_blueprint panel 1, F12 "tip at eye level"), straight at the target from F14
		PITCH = { { 8, 0 }, { 12, 10 }, { 13, 10 }, { 14, 0 } },
	},

	-- SPEAR (MAIN)
	SPEAR = {
		GLOW_WIDTH = 0.7, -- inner glow Beam along the core
		GLOW_ALPHA = 0.35,
		RIBBON_TURNS_PER_SECOND = 4,
		RIBBON_ALPHA = 0.2,
	},

	-- RELEASE (FLASH)
	RELEASE = {
		STAR_SIZE = 5, -- studs
		STAR_SECONDS = 0.08,
		SHAKE_STRENGTH = 0.8, -- degrees, thrower only
		SHAKE_SECONDS = 0.12,
	},

	-- LIGHT (SECONDARY): one PointLight per shot
	LIGHT = {
		RELEASE_BRIGHTNESS = 4,
		RELEASE_RANGE = 14,
		RELEASE_SECONDS = 0.15, -- the flash fades into the glow
		GLOW_BRIGHTNESS = 2,
		GLOW_RANGE = 12,
		IMPACT_BRIGHTNESS = 4,
		IMPACT_RANGE = 20,
		IMPACT_SECONDS = 0.2,
	},

	-- CRACKLE TRAIL (MAIN) + Trail
	TRAIL = {
		LENGTH_MIN = 10,
		LENGTH_MAX = 14,
		SEGMENTS = 10,
		OFFSET = 0.6,
		THICKNESS = 0.14,
		EVERY_FRAMES = 2,
		FADE_SECONDS = 0.1,
		AFTERIMAGE_WIDTH = 1.6, -- x the bolt's width, dark gold, while it fades
		STREAK_LIFETIME = 0.15,
		STREAK_WIDTH = 0.6,
	},

	-- SHED (RESIDUAL)
	SHED = {
		YELLOW_PER_SECOND = 34,
		BLUE_PER_SECOND = 6,
		SPEED_MIN = 2,
		SPEED_MAX = 6,
		LIFETIME = 0.25,
		SIZE = 0.25,
	},

	-- IMPACT
	IMPACT = {
		FLASH_DELAY_FRAMES = 1, -- the contact frame is seen first (Vault)
		STAR_SIZE = 5, -- studs (Vault ~0.6x body; prompt 8: ~5 agreed at stage 0)
		STAR_SECONDS = 0.08,
		SPARKS = 40, -- of them, SPARKS_BLUE are blue
		SPARKS_BLUE = 6,
		SPARK_SPEED_MIN = 30,
		SPARK_SPEED_MAX = 50,
		SPARK_DRAG = 6,
		SPARK_GRAVITY = 12,
		SPARK_LIFETIME_MIN = 0.3,
		SPARK_LIFETIME_MAX = 0.5,
		SPARK_SPREAD_DEG = 70, -- round the surface normal
		BOLTS_MIN = 5,
		BOLTS_MAX = 6,
		BOLT_LENGTH_MIN = 2,
		BOLT_LENGTH_MAX = 4,
		BOLT_SECONDS = 0.12,
		RING_FROM = 1, -- studs across
		RING_TO = 6,
		RING_SECONDS = 0.2,
		RING_LIFT = 0.05,
		ARC_SECONDS = 0.6,
		ARCS_MIN = 2,
		ARCS_MAX = 3,
		ARC_EVERY_FRAMES = 3,
		ARC_OUTSIDE = 0.7, -- studs: arc ends sit this far out from the limb, away from the body's centre
		ARC_SEGMENTS = 4,
		ARC_OFFSET = 0.45,
		ARC_THICKNESS = 0.12,
		SCORCH_SIZE = 6, -- studs across (stage 7: 4 hid under the target's own shadow)
		SCORCH_LAYERS = 2, -- the soft scorch decal stacked: one alone read too faint on the grey floor
		SCORCH_MAX_DROP = 6, -- no floor within this: no scorch
		SCORCH_SECONDS = 2,
		SCORCH_FADE_SECONDS = 1, -- the last second
	},

	BUDGET = { PARTICLES = 150, BEAMS = 30, INSTANCES = 20 },
	-- the shared bolt pool is filled to this on the first cast (the most seen at once: the spear's bolts +
	-- the strike = 120), so later casts never add instances
	BOLT_POOL = 130,

	-- STRIKE (stage 7B): all times are game seconds after the spear's impact
	STRIKE = {
		AT = 0.15, -- the bolt lands (the server uses the same delay for STRIKE_DAMAGE)
		HEIGHT = 45, -- studs above the ground where the bolt starts
		CHARGE = {
			HEIGHT = 40,
			RADIUS = 3, -- the 6-stud circle the charge bolts crawl on
			BOLTS_MIN = 3,
			BOLTS_MAX = 4,
			SEGMENTS = 4,
			OFFSET = 0.5,
			THICKNESS = 0.3, -- thin next to the 3-stud bolt, but still seen from 40 studs away
			EVERY_FRAMES = 2,
			LIGHT_RANGE = 30,
			LIGHT_BRIGHTNESS = 1,
			HEAD_BOLTS = 2,
			HEAD_LENGTH = 0.8,
		},
		BOLT = {
			SEGMENTS = 18,
			OFFSET = 2.5,
			-- outer glow, middle, core (widths in studs); branches draw only the middle and the core.
			-- EMISSION < 1 blends the outer layers instead of adding them, so the gold doesn't wash to white
			LAYERS = {
				{ WIDTH = 3.0, COLOR = "#FFB000", ALPHA = 0.6, EMISSION = 0.25 },
				{ WIDTH = 1.4, COLOR = "#FFE14D", ALPHA = 0, EMISSION = 0.7 },
				{ WIDTH = 0.5, COLOR = "#FFFDF0", ALPHA = 0, EMISSION = 1 },
			},
			BRANCHES_MIN = 4,
			BRANCHES_MAX = 6,
			BRANCH_LENGTH_MIN = 6,
			BRANCH_LENGTH_MAX = 15,
			BRANCH_ANGLE_MIN = 25, -- degrees off the bolt, so they still head down
			BRANCH_ANGLE_MAX = 50,
			BRANCH_SEGMENTS = 3,
			BRANCH_LAYERS = { 2, 3 },
		},
		-- the strokes (Vault: under ~0.3 s, later strokes weaker): on for ON s, then dipped for DIP s
		STROKES = {
			{ ON = 0.05, DIP = 0.03, POWER = 1 },
			{ ON = 0.04, DIP = 0.03, POWER = 0.8 },
			{ ON = 0.06, DIP = 0, POWER = 0.65 },
		},
		DIP = 0.35, -- intensity between strokes
		FADE = 0.08, -- the last stroke fades out
		FLASH = {
			LIGHT_RANGE = 60, -- the most a PointLight allows
			LIGHT_BRIGHTNESS = 8,
			LIGHT_SECONDS = 0.25,
			STAR_SIZE = 16,
			STAR_SECONDS = 0.1,
			SCREEN_RADIUS = 80, -- studs: players further away get no screen flash
			SCREEN_BRIGHTNESS = 0.35,
			SCREEN_CONTRAST = 0.25,
			SCREEN_HOLD = 0.06,
			SCREEN_FADE = 0.2,
			MAX_PER_SECOND = 3, -- screen flashes per rolling second on one client (Vault: WCAG 2.3.1)
			REDUCED = 0.3, -- REDUCE_FLASHING: the star and the screen flash at this strength
		},
		SHOCKWAVE = {
			FROM = 2,
			TO = 16,
			SECONDS = 0.3,
			LIFT = 0.06,
			DUST = 30,
			DUST_SPEED_MIN = 25,
			DUST_SPEED_MAX = 35,
			DUST_LIFETIME = 0.6,
			DUST_COLOR = "#8A7F70", -- blended 50% with the floor's colour
			DUST_FLOOR_MIX = 0.5,
		},
		DEBRIS = {
			MIN = 10,
			MAX = 14,
			SCALE_MIN = 1, -- x Pebble Toss's chip size in play (its ChipScale 2.5): 0.4-1.9 studs
			SCALE_MAX = 2.5,
			SPEED_MIN = 30,
			SPEED_MAX = 55,
			UP_MIN = 0.45, -- the share of the speed that goes up (the rest outward)
			UP_MAX = 0.8,
			GRAVITY = 140,
			SPIN_MAX = 18, -- radians/s
			FADE_FROM = 0.8, -- seconds after the strike
			GONE_AT = 1.2,
		},
		SHAKE_SECONDS = 0.35,
		SHAKE_RADIUS = 80,
		SMOKE = {
			AT = 0.2,
			COUNT_MIN = 6,
			COUNT_MAX = 8,
			SPEED_MIN = 4,
			SPEED_MAX = 8,
			COLOR = "#3A3632",
			ALPHA = 0.4,
			LIFETIME_MIN = 1.0, -- gone by 1.5 s
			LIFETIME_MAX = 1.3,
			SIZE = 5,
		},
		GROUND_ARCS = {
			FROM = 0.45, -- after the bolt, so the strike never passes 90 Beams
			TO = 1.0,
			MIN = 4,
			MAX = 6,
			RADIUS = 4.5,
			LENGTH_MIN = 1.5,
			LENGTH_MAX = 3,
			SEGMENTS = 3,
			THICKNESS = 0.14,
			EVERY_FRAMES = 3,
		},
		CRATER = {
			SIZE = 10,
			SECONDS = 3, -- from the strike: gone at 3.15 s
			FADE_SECONDS = 1, -- the last second
			GLOW_SECONDS = 1.5, -- the gold cracks cool
			GLOW_BRIGHTNESS = 3,
		},
		BUDGET = { PARTICLES = 120, BEAMS = 90, INSTANCES = 30 },
		CLEANUP_AT = 3.4, -- everything gone (prompt: by 3.5 s)
	},

	-- Asset ids (uploaded with Open Cloud; Game/assets/vfx/thunder_lance_assets.json). Mesh ids are carried
	-- by the templates (they can't be set at runtime).
	ASSETS = {
		Animation = def.AnimationId or "rbxassetid://71580696171096", -- ThunderLance_Throw, markers Summon / Release
		Textures = {
			Star = "rbxassetid://102941673848579", -- star_flash.png
			Spark = "rbxassetid://93020102460287", -- spark.png
			GlowLine = "rbxassetid://77325461611512", -- glow_line.png
			Streak = "rbxassetid://118515517236816", -- streak.png
			Scorch = "rbxassetid://74859395701291", -- scorch.png
			Crater = "rbxassetid://95185080474814", -- crater.png (stage 7B)
			CraterGlow = "rbxassetid://110544073335580", -- crater_glow.png (stage 7B)
			Dust = "rbxassetid://119015403999595", -- dust_puff.png (Pebble Toss): the dust ring and smoke
		},
	},
}

export type Options = {
	TimeScale: number?, -- playback speed (default CONFIG.TIME_SCALE); /vfxtest plays at 0.25
	PlayAnimation: boolean?, -- play the throw on this character (always for our own)
	LocalHits: boolean?, -- VFX test: no server; this client launches, decides the hit and plays the impact
}

type Cast = {
	Folder: Folder,
	Character: Model,
	TimeScale: number,
	Low: boolean,
	Rng: Random,
	Extras: { Instance }, -- made outside the folder (on characters)
	Connections: { RBXScriptConnection },
	Count: number, -- VFX objects made (budget)
	Bolts: { LightningBolt.Bolt }, -- this cast's bolts (its own Beam count: attribute OwnBeamsPeak)
	Particles: number, -- particles emitted (attribute ParticlesEmitted)
	Ended: boolean,
	LocalHits: boolean,
	-- the spear (nil until it forms)
	Spear: MeshPart?,
	Ribbons: MeshPart?,
	Carrier: Part?, -- invisible anchored part at the grip: glow Beam + Trail attachments, sparks
	Glow: Beam?,
	Streak: Trail?,
	SparksYellow: ParticleEmitter?,
	SparksBlue: ParticleEmitter?,
	Light: PointLight?,
	LightPart: Part?,
	Launched: boolean,
	Flying: boolean,
	Tip: Vector3, -- where the spear's tip is (flight)
	Direction: Vector3,
	Trail: LightningBolt.Bolt?,
	Afterimage: LightningBolt.Bolt?, -- the previous trail bolt, fading dark
}

local ThunderLanceVFX = {}

local casts: { [Model]: Cast } = setmetatable({}, { __mode = "k" }) :: any -- newest cast per thrower
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
	return ReplicatedStorage:WaitForChild("VFX"):WaitForChild("ThunderLance"):WaitForChild(name) :: MeshPart
end

local function newCast(name: string, character: Model, timeScale: number, seed: number?): Cast
	LightningBolt.Prewarm(CONFIG.BOLT_POOL)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = folder()
	return {
		Folder = f,
		Character = character,
		TimeScale = timeScale,
		Low = Quality.Low,
		Rng = if seed then Random.new(seed) else Random.new(),
		Extras = {},
		Connections = {},
		Count = 0,
		Bolts = {},
		Particles = 0,
		Ended = false,
		LocalHits = false,
		Launched = false,
		Flying = false,
		Tip = Vector3.zero,
		Direction = Vector3.zAxis,
	}
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
	cast.Flying = false
	LightningBolt.Release(cast.Trail)
	LightningBolt.Release(cast.Afterimage)
	for _, connection in cast.Connections do
		connection:Disconnect()
	end
	table.clear(cast.Connections)
	for _, extra in cast.Extras do
		extra:Destroy()
	end
	table.clear(cast.Extras)
	cast.Folder:Destroy()
	if casts[cast.Character] == cast then
		casts[cast.Character] = nil
	end
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

local function emitted(cast: Cast, n: number)
	cast.Particles += n
	cast.Folder:SetAttribute("ParticlesEmitted", cast.Particles)
end

local function count(cast: Cast, full: number): number
	return if cast.Low then math.max(1, math.floor(full / 2)) else full
end

local function helperPart(cast: Cast, name: string, cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.CFrame = cframe
	part.Parent = cast.Folder
	track(cast, part)
	return part
end

-- One bolt (Segments Beams + a 3-segment branch). The cast's Folder keeps the peak number of bolt
-- Beams alive at once (attribute BeamsPeak; it counts every bolt on screen, so test one cast at a time).
local function bolt(cast: Cast, params: LightningBolt.Params): LightningBolt.Bolt?
	params.TimeScale = cast.TimeScale
	local drawn = LightningBolt.Draw(params)
	if drawn then
		cast.Folder:SetAttribute("BeamsPeak", math.max(cast.Folder:GetAttribute("BeamsPeak") or 0, LightningBolt.InUse()))
		-- this cast's own Beams alive right now (the strike's budget is for the strike alone)
		local own = 0
		for i = #cast.Bolts, 1, -1 do
			if cast.Bolts[i].Done then
				table.remove(cast.Bolts, i)
			else
				own += #cast.Bolts[i].Links
			end
		end
		table.insert(cast.Bolts, drawn)
		own += #drawn.Links
		cast.Folder:SetAttribute("OwnBeamsPeak", math.max(cast.Folder:GetAttribute("OwnBeamsPeak") or 0, own))
	end
	return drawn
end

local function rightHand(character: Model): BasePart?
	local hand = character:FindFirstChild("RightHand")
	return if hand and hand:IsA("BasePart") then hand else nil
end

local function shakeCamera(cast: Cast)
	local camera = workspace.CurrentCamera
	local started = os.clock()
	local seconds = scaled(cast, CONFIG.RELEASE.SHAKE_SECONDS)
	local strength = CONFIG.RELEASE.SHAKE_STRENGTH
	local name = "ThunderLanceShake"
	RunService:UnbindFromRenderStep(name)
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function()
		local t = os.clock() - started
		if t >= seconds then
			RunService:UnbindFromRenderStep(name)
			return
		end
		local r = strength * (1 - t / seconds)
		camera.CFrame *= CFrame.Angles(math.rad((math.random() - 0.5) * r), math.rad((math.random() - 0.5) * r), 0)
	end)
end

-- Pitch of the held spear (deg) at a frame of the throw.
local function holdPitch(frame: number): number
	local keys = CONFIG.FORM.PITCH
	if frame <= keys[1][1] then
		return keys[1][2]
	end
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if frame <= b[1] then
			local t = (frame - a[1]) / (b[1] - a[1])
			return a[2] + (b[2] - a[2]) * t
		end
	end
	return keys[#keys][2]
end

-- ===== the spear (MAIN) =====
local function makeSpear(cast: Cast)
	local carrier = helperPart(cast, "Carrier", CFrame.identity)
	cast.Carrier = carrier
	local spear = template("SpearCore"):Clone()
	spear.Parent = cast.Folder
	track(cast, spear)
	cast.Spear = spear
	local ribbons = template("Ribbons"):Clone()
	ribbons.Transparency = CONFIG.SPEAR.RIBBON_ALPHA
	ribbons.Parent = cast.Folder
	track(cast, ribbons)
	cast.Ribbons = ribbons

	-- inner glow Beam along the core: glow_line.png gives the soft white-to-transparent edge
	local tail = Instance.new("Attachment")
	tail.Name = "GlowTail"
	tail.Parent = carrier
	local tip = Instance.new("Attachment")
	tip.Name = "GlowTip"
	tip.Parent = carrier
	local glow = Instance.new("Beam")
	glow.Attachment0 = tail
	glow.Attachment1 = tip
	glow.Texture = CONFIG.ASSETS.Textures.GlowLine
	glow.TextureMode = Enum.TextureMode.Stretch
	glow.FaceCamera = true
	glow.Segments = 1
	glow.Width0 = CONFIG.SPEAR.GLOW_WIDTH
	glow.Width1 = CONFIG.SPEAR.GLOW_WIDTH * 0.6
	glow.Color = ColorSequence.new(color(CONFIG.PALETTE.WHITE))
	glow.Transparency = numbers(0, 1, 0.15, CONFIG.SPEAR.GLOW_ALPHA, 0.85, CONFIG.SPEAR.GLOW_ALPHA, 1, 1)
	glow.LightEmission = 1
	glow.LightInfluence = 0
	glow.ZOffset = 1
	glow.Parent = carrier
	track(cast, glow)
	cast.Glow = glow

	-- Trail off the spear's tail (enabled at the release): wind streaks, 0.6 -> 0 wide
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailTop"
	a0.Parent = carrier
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailBottom"
	a1.Parent = carrier
	local streak = Instance.new("Trail")
	streak.Attachment0 = a0
	streak.Attachment1 = a1
	streak.Texture = CONFIG.ASSETS.Textures.Streak
	streak.TextureMode = Enum.TextureMode.Stretch
	streak.FaceCamera = true
	streak.Lifetime = scaled(cast, CONFIG.TRAIL.STREAK_LIFETIME)
	streak.WidthScale = numbers(0, 1, 0.5, 0.5, 1, 0)
	streak.Color = ColorSequence.new(color(CONFIG.PALETTE.YELLOW))
	streak.Transparency = numbers(0, 0.1, 0.6, 0.5, 1, 1)
	streak.LightEmission = 1
	streak.LightInfluence = 0
	streak.Enabled = false
	streak.Parent = carrier
	track(cast, streak)
	cast.Streak = streak

	-- shed sparks: from the spear's volume, streaking along their velocity (Squash)
	local function sparks(hex: string): ParticleEmitter
		return emitter(cast, spear, {
			Texture = CONFIG.ASSETS.Textures.Spark,
			Color = ColorSequence.new(color(hex)),
			Size = numbers(0, CONFIG.SHED.SIZE, 0.5, CONFIG.SHED.SIZE * 0.7, 1, 0),
			Transparency = numbers(0, 0, 0.6, 0.3, 1, 1),
			Squash = numbers(0, 1.2, 0.5, 0.8, 1, 0.4),
			Orientation = Enum.ParticleOrientation.VelocityParallel,
			Lifetime = NumberRange.new(CONFIG.SHED.LIFETIME * 0.8, CONFIG.SHED.LIFETIME),
			Speed = NumberRange.new(CONFIG.SHED.SPEED_MIN, CONFIG.SHED.SPEED_MAX),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 2,
			ZOffset = 0.5,
		})
	end
	cast.SparksYellow = sparks(CONFIG.PALETTE.YELLOW)
	cast.SparksBlue = sparks(CONFIG.PALETTE.SPARK_BLUE)
end

-- Place the spear with its grip at `grip`, pointing along `dir`, `length` (0..1) of its full length.
local function placeSpear(cast: Cast, grip: Vector3, dir: Vector3, length: number, spin: number)
	local spear, ribbons, carrier = cast.Spear, cast.Ribbons, cast.Carrier
	if not spear or not ribbons or not carrier then
		return
	end
	local s = math.max(length, 0.02)
	local gripCF = CFrame.lookAt(grip, grip + dir)
	for _, part in { spear, ribbons } do
		local base = template(part.Name == spear.Name and "SpearCore" or "Ribbons")
		local stretch = Vector3.new(1, 1, s)
		part.Size = base.Size * stretch
		local offset = ((base:GetAttribute("OriginFromCentre") :: Vector3?) or Vector3.zero) * stretch
		local turn = if part == ribbons then CFrame.Angles(0, 0, spin) else CFrame.identity
		part.CFrame = gripCF * turn * CFrame.new(-offset)
	end
	carrier.CFrame = gripCF
	local tail = carrier:FindFirstChild("GlowTail") :: Attachment
	local tip = carrier:FindFirstChild("GlowTip") :: Attachment
	tail.Position = Vector3.new(0, 0, 1.6 * s) -- local -Z is forward
	tip.Position = Vector3.new(0, 0, -(CONFIG.LEAD - 0.4) * s)
	local top = carrier:FindFirstChild("TrailTop") :: Attachment
	local bottom = carrier:FindFirstChild("TrailBottom") :: Attachment
	local half = CONFIG.TRAIL.STREAK_WIDTH / 2
	top.Position = Vector3.new(0, half, 2 * s)
	bottom.Position = Vector3.new(0, -half, 2 * s)
end

local function makeLight(cast: Cast, at: Vector3)
	local part = helperPart(cast, "Light", CFrame.new(at))
	local light = Instance.new("PointLight")
	light.Color = color(CONFIG.PALETTE.YELLOW)
	light.Shadows = false
	light.Brightness = 0
	light.Range = CONFIG.LIGHT.GLOW_RANGE
	light.Parent = part
	track(cast, light)
	cast.LightPart = part
	cast.Light = light
end

-- An emitter on its own attachment at `cframe`, for one-shot bursts.
local function burstAt(cast: Cast, name: string, cframe: CFrame, props: { [string]: any }): ParticleEmitter
	local part = helperPart(cast, name, cframe)
	return emitter(cast, part, props)
end

local function star(cast: Cast, name: string, at: Vector3, size: number, seconds: number)
	local e = burstAt(cast, name, CFrame.new(at), {
		Texture = CONFIG.ASSETS.Textures.Star,
		Color = ColorSequence.new(color(CONFIG.PALETTE.WHITE)),
		Size = numbers(0, size * 0.5, 0.25, size, 1, size * 0.8),
		Transparency = numbers(0, 0, 0.5, 0.2, 1, 1),
		Lifetime = NumberRange.new(seconds),
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(-12, 12),
		LockedToPart = true,
		Brightness = 1.1, -- below the glow layers so bloom keeps the rays (Frost Jab lesson)
		ZOffset = 3,
	})
	e:Emit(1)
end

-- ===== flight (MAIN) =====
local function stopSpear(cast: Cast, fadeSeconds: number)
	cast.Flying = false
	-- both trail bolts go at once, so the impact's bolts and arcs have the Beam budget to themselves
	LightningBolt.Release(cast.Trail)
	LightningBolt.Release(cast.Afterimage)
	cast.Trail = nil
	cast.Afterimage = nil
	for _, part in { cast.Spear, cast.Ribbons } do
		if part then
			tween(cast, part, fadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Transparency = 1 })
		end
	end
	if cast.Glow then
		cast.Glow.Enabled = false
	end
	if cast.Streak then
		cast.Streak.Enabled = false
	end
end

local function fly(cast: Cast, origin: Vector3, dir: Vector3, elapsed: () -> number)
	cast.Launched = true
	cast.Flying = true
	cast.Direction = dir
	cast.Tip = origin
	if cast.Streak then
		cast.Streak.Enabled = true
	end
	if cast.Glow then
		cast.Glow.Enabled = true
	end
	local filters = Projectile.Filters(cast.Character)
	if cast.LocalHits then
		-- VFX test: the thrower is a copy of our character; our real one isn't a target (stage 6: it stood
		-- in the throw line and took the hit) and doesn't stop the spear
		local me = Players.LocalPlayer.Character
		if me then
			local targets = {}
			for _, model in filters.Characters.FilterDescendantsInstances do
				if model ~= me then
					table.insert(targets, model)
				end
			end
			filters.Characters.FilterDescendantsInstances = targets
			filters.World:AddToFilter(me)
		end
	end
	local spin = 0
	local sinceBolt = math.huge -- game seconds since the trail bolt was last drawn (draw one at once)
	local owed = { yellow = 0, blue = 0 }
	local flight: RBXScriptConnection
	flight = RunService.RenderStepped:Connect(function(dt)
		if not cast.Flying or cast.Ended then
			flight:Disconnect()
			return
		end
		local gameDt = dt * cast.TimeScale
		local travelled = math.min(CONFIG.SPEED * elapsed(), CONFIG.RANGE)
		local tip = origin + dir * travelled
		local step = tip - cast.Tip
		-- our own copy of the server's sweep: where our spear stops (the server decides the real hit)
		local hit = if step.Magnitude > 0 then Projectile.Step(cast.Tip, step, CONFIG.HITBOX_RADIUS, CONFIG.BODY_RADIUS, filters) else nil
		if hit then
			tip = hit.Position
		end
		-- the live trail bolt rides on the spear's tail between redraws (stage 7: at 160 studs/s it was
		-- left up to 10 studs behind); only the fading afterimage stays where it was drawn
		LightningBolt.Shift(cast.Trail, tip - cast.Tip)
		cast.Tip = tip
		spin += math.pi * 2 * CONFIG.SPEAR.RIBBON_TURNS_PER_SECOND * gameDt
		placeSpear(cast, tip - dir * CONFIG.LEAD, dir, 1, spin)
		if cast.LightPart then
			cast.LightPart.CFrame = CFrame.new(tip - dir * 1.5)
		end

		-- crackling trail: a new bolt every 2 frames of the 30 fps animation (GAME time, not render
		-- frames: at 60 fps or 0.25x a render-frame count piled up 20 bolts); the old one stays as a
		-- fading dark afterimage
		sinceBolt += gameDt
		if sinceBolt >= CONFIG.TRAIL.EVERY_FRAMES / 30 then
			sinceBolt = 0
			local tr = CONFIG.TRAIL
			LightningBolt.Release(cast.Afterimage) -- by now it has all but faded
			LightningBolt.Recolour(cast.Trail, color(CONFIG.PALETTE.AFTERIMAGE), tr.AFTERIMAGE_WIDTH)
			cast.Afterimage = cast.Trail
			local tail = tip - dir * (CONFIG.LEAD + 2)
			local length = math.min(cast.Rng:NextNumber(tr.LENGTH_MIN, tr.LENGTH_MAX), math.max(travelled - 2, 0.5))
			cast.Trail = bolt(cast, {
				From = tail,
				To = tail - dir * length,
				Segments = tr.SEGMENTS,
				MaxOffset = tr.OFFSET,
				Thickness = tr.THICKNESS,
				Color = color(CONFIG.PALETTE.YELLOW),
				Lifetime = tr.FADE_SECONDS + tr.EVERY_FRAMES / 30,
				Rng = cast.Rng,
				Branch = not cast.Low,
			})
		end

		-- shed sparks (~40/s) with :Emit, never a running emitter
		owed.yellow += count(cast, CONFIG.SHED.YELLOW_PER_SECOND) * gameDt
		owed.blue += count(cast, CONFIG.SHED.BLUE_PER_SECOND) * gameDt
		if cast.SparksYellow and owed.yellow >= 1 then
			cast.SparksYellow:Emit(math.floor(owed.yellow))
			owed.yellow -= math.floor(owed.yellow)
		end
		if cast.SparksBlue and owed.blue >= 1 then
			cast.SparksBlue:Emit(math.floor(owed.blue))
			owed.blue -= math.floor(owed.blue)
		end

		if hit then
			stopSpear(cast, 0.06)
			if cast.LocalHits then
				local model = hit.Humanoid and hit.Humanoid.Parent :: Model?
				ThunderLanceVFX.Hit(cast.Character, hit.Position, hit.Normal, model, nil, nil, { TimeScale = cast.TimeScale })
				if CONFIG.SKY_STRIKE and model then
					-- the server's ground pick, done here (VFX test: no server)
					local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
					local from = if root then root.Position else model:GetPivot().Position
					local ground = workspace:Raycast(from, Vector3.new(0, -20, 0), filters.World)
					ThunderLanceVFX.Strike(cast.Character, model, if ground then ground.Position else from, nil,
						cast.Rng:NextInteger(1, 2147483646), { TimeScale = cast.TimeScale })
				end
			end
			-- the server's AbilityHit plays the impact; if it never comes, clean up
			after(cast, CONFIG.SERVER_HIT_WAIT, function()
				endCast(cast)
			end)
		elseif travelled >= CONFIG.RANGE then
			-- full range: no impact, it just fades out (with its light)
			stopSpear(cast, 0.15)
			if cast.Light then
				tween(cast, cast.Light, 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Brightness = 0 })
			end
			after(cast, 0.3, function()
				endCast(cast)
			end)
		end
	end)
	table.insert(cast.Connections, flight)
end

-- The spear leaves the hand (RELEASE flash + light + shake), then flies.
local function release(cast: Cast, origin: Vector3, dir: Vector3, elapsed: () -> number, isLocal: boolean)
	if cast.Launched or cast.Ended then
		return
	end
	local hand = rightHand(cast.Character)
	local at = if hand then hand.Position else origin - dir * CONFIG.LEAD
	star(cast, "ReleaseFlash", at, CONFIG.RELEASE.STAR_SIZE, CONFIG.RELEASE.STAR_SECONDS)
	if not cast.Light then
		makeLight(cast, at)
	end
	local light = cast.Light :: PointLight
	light.Brightness = CONFIG.LIGHT.RELEASE_BRIGHTNESS
	light.Range = CONFIG.LIGHT.RELEASE_RANGE
	tween(cast, light, CONFIG.LIGHT.RELEASE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out,
		{ Brightness = CONFIG.LIGHT.GLOW_BRIGHTNESS, Range = CONFIG.LIGHT.GLOW_RANGE })
	if isLocal then
		shakeCamera(cast)
	end
	if not cast.Spear then
		makeSpear(cast)
	end
	fly(cast, origin, dir, elapsed)
end

-- ===== CRACKLE + FORM: from the Summon marker to the release, in the hand =====
local function crackle(cast: Cast, hand: BasePart)
	local c = CONFIG.CRACKLE
	local sparks = emitter(cast, hand, {
		Texture = CONFIG.ASSETS.Textures.Spark,
		Color = ColorSequence.new(color(CONFIG.PALETTE.SPARK_BLUE)),
		Size = numbers(0, c.SPARK_SIZE, 0.5, c.SPARK_SIZE * 0.6, 1, 0),
		Transparency = numbers(0, 0, 0.5, 0.3, 1, 1),
		Lifetime = NumberRange.new(c.SPARK_LIFETIME * 0.6, c.SPARK_LIFETIME),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180),
		ZOffset = 1,
	})
	sparks:Emit(c.SPARKS)
	local started = os.clock()
	local drawn = -1 -- the last 2-frame slot (game time) a set of bolts was drawn in
	local set: { LightningBolt.Bolt? } = {}
	local crackling: RBXScriptConnection
	crackling = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - started) * cast.TimeScale + CONFIG.SUMMON_AT
		if cast.Ended or cast.Launched or t >= CONFIG.FORM_AT + 0.05 or not hand.Parent then
			crackling:Disconnect()
			return
		end
		local slot = math.floor((t - CONFIG.SUMMON_AT) * 30 / c.EVERY_FRAMES)
		if slot == drawn then
			return
		end
		drawn = slot
		for _, old in set do -- each set replaces the last (no frame where both are drawn)
			LightningBolt.Release(old)
		end
		table.clear(set)
		for _ = 1, cast.Rng:NextInteger(c.BOLTS_MIN, if cast.Low then c.BOLTS_MIN else c.BOLTS_MAX) do
			local a = hand.Position + cast.Rng:NextUnitVector() * 0.25
			set[#set + 1] = bolt(cast, {
				From = a,
				To = a + cast.Rng:NextUnitVector() * c.LENGTH,
				Segments = c.SEGMENTS,
				MaxOffset = c.OFFSET,
				Thickness = c.THICKNESS,
				Color = color(CONFIG.PALETTE.YELLOW),
				Lifetime = c.EVERY_FRAMES / 30,
				Rng = cast.Rng,
			})
		end
	end)
	table.insert(cast.Connections, crackling)
end

-- The spear grows from the grip (F8, 4 frames, Quint Out) and is held, aimed, until the release.
local function hold(cast: Cast, hand: BasePart, flat: Vector3, started: number)
	makeSpear(cast)
	local glow = cast.Glow :: Beam
	glow.Enabled = true
	local holding: RBXScriptConnection
	holding = RunService.RenderStepped:Connect(function()
		if cast.Ended or cast.Launched or not hand.Parent then
			holding:Disconnect()
			return
		end
		local t = (os.clock() - started) * cast.TimeScale -- game seconds since the cast
		local frame = t * 30
		local grow = math.clamp((frame - 8) / CONFIG.FORM.GROW_FRAMES, 0, 1)
		local length = TweenService:GetValue(grow, CONFIG.FORM.GROW_STYLE, Enum.EasingDirection.Out)
		local pitch = math.rad(holdPitch(frame))
		local dir = (flat * math.cos(pitch) + Vector3.yAxis * math.sin(pitch)).Unit
		placeSpear(cast, hand.Position, dir, length, 0)
	end)
	table.insert(cast.Connections, holding)
end

-- Play the throw on a character. Every client runs this for every player who uses it.
-- isLocal = our own character: we play the animation (Roblox replicates it) and launch our own spear.
function ThunderLanceVFX.Play(character: Model, aim: Vector3, isLocal: boolean, options: Options?)
	local timeScale = options and options.TimeScale or CONFIG.TIME_SCALE
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hand = rightHand(character)
	if not root or not hand then
		return
	end
	local flat = Vector3.new(aim.X, 0, aim.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit

	local old = casts[character]
	if old and not old.Launched then
		endCast(old) -- a new cast before the last one left the hand
	end
	local cast = newCast(`ThunderLance_{character.Name}`, character, timeScale)
	cast.LocalHits = options ~= nil and options.LocalHits == true
	casts[character] = cast
	table.insert(cast.Connections, character.Destroying:Connect(function()
		endCast(cast)
	end))

	local track: AnimationTrack? = nil
	if isLocal or (options and options.PlayAnimation) then
		track = Pose.Track(character, "ThunderLance", KEYFRAMES, CONFIG.ASSETS.Animation)
		if track then
			track:Play(0.05)
			track:AdjustSpeed(timeScale)
		end
	end

	local started = os.clock()
	local summoned = false
	local function onSummon()
		if summoned or cast.Ended then
			return
		end
		summoned = true
		crackle(cast, hand)
	end
	after(cast, CONFIG.SUMMON_AT, onSummon)
	after(cast, CONFIG.FORM_AT, function()
		hold(cast, hand, flat, started)
	end)

	local launchesHere = isLocal or cast.LocalHits
	if launchesHere then
		local function onRelease()
			if cast.Launched or cast.Ended then
				return
			end
			local origin = hand.Position + flat * CONFIG.LEAD
			local released = os.clock()
			release(cast, origin, flat, function()
				return (os.clock() - released) * cast.TimeScale
			end, isLocal)
		end
		if track then
			table.insert(cast.Connections, track:GetMarkerReachedSignal("Summon"):Connect(onSummon))
			table.insert(cast.Connections, track:GetMarkerReachedSignal("Release"):Connect(onRelease))
		end
		after(cast, CONFIG.RELEASE_AT, onRelease) -- the timer races the marker; the first one wins
	else
		-- another player: their spear flies when AbilityLaunch arrives; none = the server rejected it
		after(cast, CONFIG.LAUNCH_WAIT, function()
			if not cast.Launched then
				endCast(cast)
			end
		end)
	end
end

-- Another player's spear left their hand (AbilityLaunch): fly it on the server clock.
function ThunderLanceVFX.Launch(character: Model, origin: Vector3, direction: Vector3, startServerTime: number, seed: number)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" or typeof(startServerTime) ~= "number" then
		return
	end
	local dir = if direction.Magnitude > 0.01 then direction.Unit else Vector3.zAxis
	local cast = casts[character]
	if not cast or cast.Launched or cast.Ended then
		cast = newCast(`ThunderLance_{character.Name}`, character, CONFIG.TIME_SCALE, seed)
		casts[character] = cast
	else
		cast.Rng = Random.new(seed)
	end
	local c = cast :: Cast
	release(c, origin, dir, function()
		return workspace:GetServerTimeNow() - startServerTime
	end, false)
end

-- ===== IMPACT: the server decided the hit (or the VFX test's own sweep) =====
-- Arcs jump between NEIGHBOURING limbs, so they run along the body's outline instead of through it.
local ARC_PAIRS = {
	{ "Head", "LeftUpperArm" }, { "Head", "RightUpperArm" }, { "LeftUpperArm", "LeftHand" },
	{ "RightUpperArm", "RightHand" }, { "LeftHand", "LeftFoot" }, { "RightHand", "RightFoot" },
	{ "LeftFoot", "RightFoot" }, { "UpperTorso", "LeftHand" }, { "UpperTorso", "RightHand" },
}

local function arcs(cast: Cast, target: Model)
	local limbPairs: { { BasePart } } = {}
	for _, names in ARC_PAIRS do
		local a, b = target:FindFirstChild(names[1]), target:FindFirstChild(names[2])
		if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
			table.insert(limbPairs, { a, b })
		end
	end
	if #limbPairs == 0 then
		return
	end
	local i = CONFIG.IMPACT
	local rootPart = target:FindFirstChild("HumanoidRootPart")
	-- an arc end just outside a limb, away from the body's centre: drawn between limb centres the arcs
	-- ran inside the body and were never seen (stage 7)
	local function outside(limb: BasePart): Vector3
		local centre = if rootPart and rootPart:IsA("BasePart") then rootPart.Position else target:GetPivot().Position
		local out = limb.Position - centre
		out = if out.Magnitude > 0.3 then out.Unit else cast.Rng:NextUnitVector()
		return limb.Position + (out + cast.Rng:NextUnitVector() * 0.4).Unit * (limb.Size.Magnitude / 2 * 0.6 + i.ARC_OUTSIDE)
	end
	local started = os.clock()
	local drawn = -1 -- the last 3-frame slot (game time) a set of arcs was drawn in
	local set: { LightningBolt.Bolt? } = {}
	local arcing: RBXScriptConnection
	arcing = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - started) * cast.TimeScale
		if cast.Ended or t >= i.ARC_SECONDS or not target.Parent then
			arcing:Disconnect()
			return
		end
		local slot = math.floor(t * 30 / i.ARC_EVERY_FRAMES)
		if slot == drawn then
			return
		end
		drawn = slot
		for _, old in set do -- each set of arcs replaces the last
			LightningBolt.Release(old)
		end
		table.clear(set)
		for _ = 1, cast.Rng:NextInteger(i.ARCS_MIN, if cast.Low then i.ARCS_MIN else i.ARCS_MAX) do
			local pair = limbPairs[cast.Rng:NextInteger(1, #limbPairs)]
			set[#set + 1] = bolt(cast, {
				From = outside(pair[1]),
				To = outside(pair[2]),
				Segments = i.ARC_SEGMENTS,
				MaxOffset = i.ARC_OFFSET,
				Thickness = i.ARC_THICKNESS,
				Color = color(CONFIG.PALETTE.YELLOW),
				Lifetime = i.ARC_EVERY_FRAMES / 30,
				Rng = cast.Rng,
			})
		end
	end)
	table.insert(cast.Connections, arcing)
end

local function scorch(cast: Cast, position: Vector3, ignore: { Instance })
	local i = CONFIG.IMPACT
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local floor = workspace:Raycast(position + Vector3.new(0, 0.2, 0), Vector3.new(0, -i.SCORCH_MAX_DROP, 0), params)
	if not floor then
		return -- no floor within 6 studs: no scorch
	end
	-- a thin plate lying on the floor (its Top face up the floor's normal), the decal on top
	local across = floor.Normal:Cross(Vector3.zAxis)
	across = if across.Magnitude > 0.01 then across.Unit else Vector3.xAxis
	local part = helperPart(cast, "Scorch", CFrame.fromMatrix(floor.Position + floor.Normal * 0.03, across, floor.Normal))
	part.Size = Vector3.new(i.SCORCH_SIZE, 0.05, i.SCORCH_SIZE)
	for _ = 1, i.SCORCH_LAYERS do
		local decal = Instance.new("Decal")
		decal.Texture = CONFIG.ASSETS.Textures.Scorch
		decal.Face = Enum.NormalId.Top
		decal.Transparency = 0
		decal.Parent = part
		track(cast, decal)
		after(cast, i.SCORCH_SECONDS - i.SCORCH_FADE_SECONDS, function()
			tween(cast, decal, i.SCORCH_FADE_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.In, { Transparency = 1 })
		end)
	end
end

-- Play the impact at `position` (the server's exact point), facing `normal`.
function ThunderLanceVFX.Hit(character: Model, position: Vector3, normal: Vector3, target: Model?, serverTime: number?,
	seed: number?, options: Options?)
	if typeof(position) ~= "Vector3" or typeof(normal) ~= "Vector3" then
		return
	end
	if serverTime and workspace:GetServerTimeNow() - serverTime > CONFIG.SKIP_LATE_AFTER then
		return -- arrived too late: it would play long after the hit
	end
	local timeScale = options and options.TimeScale or CONFIG.TIME_SCALE
	local up = if normal.Magnitude > 0.01 then normal.Unit else Vector3.yAxis
	local i = CONFIG.IMPACT

	-- our flying spear (if any) stops where the server says
	local flight = casts[character]
	local light: PointLight? = nil
	if flight and flight.Launched and not flight.Ended then
		if flight.Flying then
			flight.Tip = position
			placeSpear(flight, position - flight.Direction * CONFIG.LEAD, flight.Direction, 1, 0)
			stopSpear(flight, 0.06)
		end
		-- the shot's one light moves to the hit for the pulse
		light = flight.Light
		if flight.LightPart then
			flight.LightPart.CFrame = CFrame.new(position + up * 1.5)
		end
		after(flight, CONFIG.LIGHT.IMPACT_SECONDS + 0.2, function()
			endCast(flight)
		end)
	end

	local cast = newCast(`ThunderLanceHit_{character.Name}`, character, timeScale, seed)
	local right = up:Cross(Vector3.zAxis)
	right = if right.Magnitude > 0.01 then right.Unit else Vector3.xAxis
	local surface = CFrame.fromMatrix(position, right, up) -- Y = the surface normal

	-- light pulse (the flight's light, or a new one if we never saw the flight)
	if not light then
		makeLight(cast, position + up * 1.5)
		light = cast.Light
	end
	local l = light :: PointLight
	l.Brightness = CONFIG.LIGHT.IMPACT_BRIGHTNESS
	l.Range = CONFIG.LIGHT.IMPACT_RANGE
	TweenService:Create(l, TweenInfo.new(scaled(cast, CONFIG.LIGHT.IMPACT_SECONDS), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Brightness = 0 }):Play()

	-- FLASH, one frame after contact
	after(cast, i.FLASH_DELAY_FRAMES / 30, function()
		star(cast, "ImpactFlash", position + up * 0.3, i.STAR_SIZE, i.STAR_SECONDS)
	end)

	-- MAIN: spark burst round the normal + short bolts shooting outward
	local sparkPart = helperPart(cast, "Sparks", surface) -- both colours share it (instance budget)
	local function burst(hex: string, n: number)
		local e = emitter(cast, sparkPart, {
			Texture = CONFIG.ASSETS.Textures.Spark,
			Color = ColorSequence.new(color(hex)),
			EmissionDirection = Enum.NormalId.Top,
			Size = numbers(0, 0.45, 0.4, 0.35, 1, 0),
			Transparency = numbers(0, 0, 0.6, 0.25, 1, 1),
			Squash = numbers(0, 2, 0.5, 1.2, 1, 0.5),
			Orientation = Enum.ParticleOrientation.VelocityParallel,
			Lifetime = NumberRange.new(i.SPARK_LIFETIME_MIN, i.SPARK_LIFETIME_MAX),
			Speed = NumberRange.new(i.SPARK_SPEED_MIN, i.SPARK_SPEED_MAX),
			SpreadAngle = Vector2.new(i.SPARK_SPREAD_DEG, i.SPARK_SPREAD_DEG),
			Drag = i.SPARK_DRAG,
			Acceleration = Vector3.new(0, -i.SPARK_GRAVITY, 0),
			ZOffset = 2,
		})
		e:Emit(n)
	end
	burst(CONFIG.PALETTE.YELLOW, count(cast, i.SPARKS - i.SPARKS_BLUE))
	burst(CONFIG.PALETTE.SPARK_BLUE, count(cast, i.SPARKS_BLUE))
	for _ = 1, if cast.Low then 3 else cast.Rng:NextInteger(i.BOLTS_MIN, i.BOLTS_MAX) do
		local out = (up + cast.Rng:NextUnitVector() * 0.9).Unit
		bolt(cast, {
			From = position,
			To = position + out * cast.Rng:NextNumber(i.BOLT_LENGTH_MIN, i.BOLT_LENGTH_MAX),
			Segments = 3,
			MaxOffset = 0.35,
			Thickness = 0.1,
			Color = color(CONFIG.PALETTE.YELLOW),
			Lifetime = i.BOLT_SECONDS,
			Rng = cast.Rng,
		})
	end

	-- SECONDARY: shock ring flat on the surface hit, 1 -> 6 studs while fading
	local base = template("Ring")
	local ring = base:Clone()
	ring.Size = base.Size * i.RING_FROM
	ring.CFrame = surface + up * i.RING_LIFT
	ring.Parent = cast.Folder
	track(cast, ring)
	tween(cast, ring, i.RING_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out,
		{ Size = base.Size * i.RING_TO, Transparency = 1 })

	-- RESIDUAL: arcs on the target, scorch on the floor
	if target and target:IsA("Model") then
		arcs(cast, target)
	end
	if not (CONFIG.SKY_STRIKE and target) then
		scorch(cast, position, { character, folder(), target or cast.Folder }) -- a strike brings its crater
	end

	after(cast, math.max(i.SCORCH_SECONDS, i.ARC_SECONDS, i.RING_SECONDS) + 0.1, function()
		endCast(cast)
	end)
end

-- ===== STRIKE (stage 7B): lightning from the sky onto a character the spear hit =====
local flashTimes: { number } = {} -- this client's recent screen flashes (os.clock), max 3 a second

-- The floor at `at` (straight down), for the dust and debris colour. nil: nothing within 4 studs.
local function floorBelow(at: Vector3, ignore: { Instance }): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	return workspace:Raycast(at + Vector3.new(0, 1, 0), Vector3.new(0, -4, 0), params)
end

local function floorColour(floor: RaycastResult?): (Color3, Enum.Material)
	if not floor then
		return color(CONFIG.STRIKE.SHOCKWAVE.DUST_COLOR), Enum.Material.Slate
	end
	local instance = floor.Instance
	if instance:IsA("Terrain") then
		return instance:GetMaterialColor(floor.Material), floor.Material
	elseif instance:IsA("BasePart") then
		return instance.Color, instance.Material
	end
	return color(CONFIG.STRIKE.SHOCKWAVE.DUST_COLOR), floor.Material
end

-- The local screen flash: a ColorCorrectionEffect on THIS client's camera (never Lighting), capped
-- at MAX_PER_SECOND a rolling second (Vault: Lightning Strikes and Thunder - photosensitivity).
local function screenFlash(cast: Cast, strength: number)
	local f = CONFIG.STRIKE.FLASH
	local now = os.clock()
	for i = #flashTimes, 1, -1 do
		if now - flashTimes[i] > 1 then
			table.remove(flashTimes, i)
		end
	end
	local camera = workspace.CurrentCamera
	if not CONFIG.SCREEN_FLASH_ENABLED or #flashTimes >= f.MAX_PER_SECOND or not camera then
		return
	end
	table.insert(flashTimes, now)
	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = "ThunderLanceStrikeFlash"
	effect.Brightness = f.SCREEN_BRIGHTNESS * strength
	effect.Contrast = f.SCREEN_CONTRAST * strength
	effect.Parent = camera
	track(cast, effect, true)
	after(cast, f.SCREEN_HOLD, function()
		tween(cast, effect, f.SCREEN_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Brightness = 0, Contrast = 0 })
	end)
end

-- Where this player is: their character, else the camera.
local function listener(fallback: Vector3): Vector3
	local me = Players.LocalPlayer.Character
	if me then
		return me:GetPivot().Position
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.Position else fallback
end

-- Camera shake by distance: SHAKE_MAX at the target (or right at the strike), 0 at SHAKE_RADIUS.
-- Smooth noise, not per-frame random jitter, bound just after the camera (Vault: Camera Shake).
local function strikeShake(cast: Cast, groundPos: Vector3, target: Model?)
	local me = Players.LocalPlayer.Character
	local k = if me and me == target then 1 else math.clamp(1 - (listener(groundPos) - groundPos).Magnitude / CONFIG.STRIKE.SHAKE_RADIUS, 0, 1)
	local strength = CONFIG.SHAKE_MAX * k
	if strength <= 0 then
		return
	end
	local camera = workspace.CurrentCamera
	local started = os.clock()
	local seconds = scaled(cast, CONFIG.STRIKE.SHAKE_SECONDS)
	local name = "ThunderLanceStrikeShake"
	RunService:UnbindFromRenderStep(name)
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function()
		local t = os.clock() - started
		if t >= seconds or cast.Ended then
			RunService:UnbindFromRenderStep(name)
			return
		end
		local r = math.rad(strength) * (1 - t / seconds) ^ 2
		local n = t * 22 * cast.TimeScale -- noise frequency in game time
		camera.CFrame *= CFrame.Angles(math.noise(n, 1.7) * r, math.noise(n, 7.3) * r, math.noise(n, 3.1) * r * 0.5)
	end)
end

-- 10-14 rock chunks (Pebble Toss chips, floor coloured): anchored, moved here (no physics objects to
-- clean up and the same arc at any TIME_SCALE), landing on the floor, fading out by GONE_AT.
local function debris(cast: Cast, groundPos: Vector3, up: Vector3, tint: Color3, material: Enum.Material, rng: Random)
	local d = CONFIG.STRIKE.DEBRIS
	local chips = ReplicatedStorage:WaitForChild("VFX"):WaitForChild("PebbleToss")
	local rocks = {}
	for _ = 1, count(cast, rng:NextInteger(d.MIN, d.MAX)) do
		local chip = (chips:FindFirstChild(`Chip{rng:NextInteger(1, 5)}`) :: BasePart):Clone()
		chip.Size *= 2.5 * rng:NextNumber(d.SCALE_MIN, d.SCALE_MAX)
		chip.Anchored = true
		chip.CanCollide = false
		chip.CanQuery = false
		chip.CanTouch = false
		chip.CastShadow = false
		if chip:IsA("UnionOperation") then
			chip.UsePartColor = true
		end
		chip.Color = tint
		chip.Material = material
		local yaw = rng:NextNumber(0, math.pi * 2)
		local out = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
		local share = rng:NextNumber(d.UP_MIN, d.UP_MAX)
		local speed = rng:NextNumber(d.SPEED_MIN, d.SPEED_MAX)
		local spin = rng:NextUnitVector() * rng:NextNumber(d.SPIN_MAX * 0.4, d.SPIN_MAX)
		local start = groundPos + up * 0.5 + out * rng:NextNumber(0.3, 1.5)
		chip.CFrame = CFrame.new(start) * CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), 0)
		chip.Parent = cast.Folder
		track(cast, chip)
		table.insert(rocks, {
			Part = chip,
			Position = start,
			Velocity = (out * (1 - share) + up * share).Unit * speed,
			Spin = spin,
			Landed = false,
			Floor = groundPos.Y + chip.Size.Y * 0.3,
		})
	end
	local age = 0
	local moving: RBXScriptConnection
	moving = RunService.RenderStepped:Connect(function(dt)
		if cast.Ended then
			moving:Disconnect()
			return
		end
		local gameDt = math.min(dt, 0.1) * cast.TimeScale
		age += gameDt
		local fade = math.clamp((age - d.FADE_FROM) / (d.GONE_AT - d.FADE_FROM), 0, 1)
		for _, rock in rocks do
			if not rock.Landed then
				rock.Velocity -= Vector3.new(0, d.GRAVITY * gameDt, 0)
				rock.Position += rock.Velocity * gameDt
				if rock.Position.Y <= rock.Floor and rock.Velocity.Y < 0 then
					rock.Position = Vector3.new(rock.Position.X, rock.Floor, rock.Position.Z)
					rock.Landed = true
				end
				local turn = rock.Spin * gameDt
				rock.Part.CFrame = CFrame.new(rock.Position) * CFrame.fromAxisAngle(turn.Unit, turn.Magnitude) * rock.Part.CFrame.Rotation
			end
			rock.Part.Transparency = fade
		end
		if age >= d.GONE_AT then
			moving:Disconnect()
			for _, rock in rocks do
				rock.Part:Destroy()
			end
		end
	end)
	table.insert(cast.Connections, moving)
end

-- The strike, `lead` game seconds already late (a client that heard about the hit late).
function ThunderLanceVFX.Strike(character: Model, target: Model?, groundPos: Vector3, serverTime: number?, seed: number?,
	options: Options?)
	if typeof(groundPos) ~= "Vector3" then
		return
	end
	if serverTime and workspace:GetServerTimeNow() - serverTime > CONFIG.SKIP_LATE_AFTER then
		return -- arrived too late
	end
	local timeScale = options and options.TimeScale or CONFIG.TIME_SCALE
	local cast = newCast(`ThunderLanceStrike_{character.Name}`, character, timeScale, seed)
	local S = CONFIG.STRIKE
	local up = Vector3.yAxis
	local base = seed or cast.Rng:NextInteger(1, 2147483646)
	-- one Random per layer: the charge redraws per render frame, so it must not shift the others
	local rngCharge, rngBolt, rngDebris, rngArcs = Random.new(base + 1), Random.new(base + 2), Random.new(base + 3), Random.new(base + 4)
	local lead = if serverTime then math.clamp(workspace:GetServerTimeNow() - serverTime, 0, S.AT) else 0
	local function at(seconds: number, fn: () -> ())
		after(cast, math.max(seconds - lead, 0), fn)
	end
	local reduce = CONFIG.REDUCE_FLASHING
	local head = target and target:FindFirstChild("Head") :: BasePart?
	local root = target and target:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hitPoint = if root and root.Parent then root.Position else groundPos + up * 3
	local ignore: { Instance } = { character, folder() }
	if target then
		table.insert(ignore, target)
	end
	local floor = floorBelow(groundPos, ignore)
	local floorTint, floorMaterial = floorColour(floor)
	local floorUp = if floor then floor.Normal else up

	-- CHARGE (SECONDARY): bolts crawling on a circle high above, a dim gold light, crackles on the head
	local sky = groundPos + up * S.CHARGE.HEIGHT
	makeLight(cast, sky)
	local light = cast.Light :: PointLight
	light.Color = color(CONFIG.PALETTE.GOLD)
	light.Range = S.CHARGE.LIGHT_RANGE
	light.Brightness = S.CHARGE.LIGHT_BRIGHTNESS
	local set: { LightningBolt.Bolt? } = {} -- the charge bolts on screen (stroke 1 clears them)
	do
		local c = S.CHARGE
		local started = os.clock()
		local drawn = -1
		local charging: RBXScriptConnection
		charging = RunService.RenderStepped:Connect(function()
			local t = (os.clock() - started) * cast.TimeScale + lead
			if cast.Ended or t >= S.AT then
				charging:Disconnect()
				for _, old in set do
					LightningBolt.Release(old)
				end
				return
			end
			local slot = math.floor(t * 30 / c.EVERY_FRAMES)
			if slot == drawn then
				return
			end
			drawn = slot
			for _, old in set do
				LightningBolt.Release(old)
			end
			table.clear(set)
			for _ = 1, rngCharge:NextInteger(c.BOLTS_MIN, if cast.Low then c.BOLTS_MIN else c.BOLTS_MAX) do
				local a0 = rngCharge:NextNumber(0, math.pi * 2)
				local a1 = a0 + rngCharge:NextNumber(0.6, 1.6)
				set[#set + 1] = bolt(cast, {
					From = sky + Vector3.new(math.cos(a0), 0, math.sin(a0)) * c.RADIUS,
					To = sky + Vector3.new(math.cos(a1), rngCharge:NextNumber(-0.5, 0.5), math.sin(a1)) * c.RADIUS,
					Segments = c.SEGMENTS,
					MaxOffset = c.OFFSET,
					Thickness = c.THICKNESS,
					Color = color(CONFIG.PALETTE.YELLOW),
					Lifetime = c.EVERY_FRAMES / 30,
					Rng = rngCharge,
				})
			end
			if head and head.Parent then
				for _ = 1, c.HEAD_BOLTS do
					local a = head.Position + rngCharge:NextUnitVector() * 0.6
					set[#set + 1] = bolt(cast, {
						From = a,
						To = a + rngCharge:NextUnitVector() * c.HEAD_LENGTH,
						Segments = 3,
						MaxOffset = 0.15,
						Thickness = 0.07,
						Color = color(CONFIG.PALETTE.YELLOW),
						Lifetime = c.EVERY_FRAMES / 30,
						Rng = rngCharge,
					})
				end
			end
		end)
		table.insert(cast.Connections, charging)
	end

	-- the BOLT (MAIN): 3 strokes, each a new shape and weaker, dipping between them, the last fading
	local layers = {}
	for i, layer in S.BOLT.LAYERS do
		layers[i] = { Width = layer.WIDTH, Color = color(layer.COLOR), Transparency = layer.ALPHA, ZOffset = i, LightEmission = layer.EMISSION }
	end
	local current: LightningBolt.Bolt? = nil
	local clock = S.AT
	for index, stroke in S.STROKES do
		local last = index == #S.STROKES
		at(clock, function()
			for _, old in set do
				LightningBolt.Release(old)
			end
			LightningBolt.Release(current)
			local b = S.BOLT
			current = bolt(cast, {
				From = groundPos + up * S.HEIGHT,
				To = groundPos,
				Segments = b.SEGMENTS,
				MaxOffset = b.OFFSET,
				Thickness = 0,
				Color = color(CONFIG.PALETTE.WHITE),
				Layers = layers,
				Branches = {
					Count = rngBolt:NextInteger(b.BRANCHES_MIN, if cast.Low then b.BRANCHES_MIN else b.BRANCHES_MAX),
					LengthMin = b.BRANCH_LENGTH_MIN,
					LengthMax = b.BRANCH_LENGTH_MAX,
					AngleMin = b.BRANCH_ANGLE_MIN,
					AngleMax = b.BRANCH_ANGLE_MAX,
					Segments = b.BRANCH_SEGMENTS,
					Layers = b.BRANCH_LAYERS,
				},
				Hold = if last then stroke.ON else 10, -- earlier strokes are replaced by the next one
				Lifetime = if last then S.FADE else 0.01,
				Intensity = stroke.POWER,
				Rng = rngBolt,
			})
		end)
		if stroke.DIP > 0 and not reduce then
			at(clock + stroke.ON, function()
				LightningBolt.Dim(current, S.DIP)
			end)
		end
		clock += stroke.ON + stroke.DIP
	end
	at(clock + S.FADE + 0.02, function()
		LightningBolt.Release(current)
	end)

	-- FLASH + SHOCKWAVE + DEBRIS + SHAKE, the moment it lands
	at(S.AT, function()
		local f = S.FLASH
		local strength = if reduce then f.REDUCED else 1
		local lightPart = cast.LightPart :: Part
		lightPart.CFrame = CFrame.new(groundPos + up * 3)
		light.Color = color(CONFIG.PALETTE.YELLOW)
		light.Range = f.LIGHT_RANGE
		light.Brightness = f.LIGHT_BRIGHTNESS * strength
		tween(cast, light, f.LIGHT_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Brightness = 0 })
		star(cast, "StrikeFlash", hitPoint, f.STAR_SIZE * (if reduce then 0.6 else 1), f.STAR_SECONDS)
		emitted(cast, 1)
		if (listener(groundPos) - groundPos).Magnitude <= f.SCREEN_RADIUS then
			screenFlash(cast, strength)
		end
		strikeShake(cast, groundPos, target)
		if CONFIG.STRIKE_SOUND_ID ~= "" then
			local sound = Instance.new("Sound")
			sound.SoundId = CONFIG.STRIKE_SOUND_ID
			sound.RollOffMaxDistance = 400
			sound.PlaybackSpeed = math.max(cast.TimeScale, 0.25)
			sound.Parent = lightPart
			track(cast, sound)
			sound:Play()
		end

		-- shock ring flat on the ground + a dust ring rolling outward along it
		local w = S.SHOCKWAVE
		local right = floorUp:Cross(Vector3.zAxis)
		right = if right.Magnitude > 0.01 then right.Unit else Vector3.xAxis
		local flat = CFrame.fromMatrix(groundPos + floorUp * w.LIFT, right, floorUp)
		local ringBase = template("Ring")
		local ring = ringBase:Clone()
		ring.Size = ringBase.Size * w.FROM
		ring.CFrame = flat
		ring.Parent = cast.Folder
		track(cast, ring)
		tween(cast, ring, w.SECONDS, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, { Size = ringBase.Size * w.TO, Transparency = 1 })
		local dustColour = floorTint:Lerp(color(w.DUST_COLOR), 1 - w.DUST_FLOOR_MIX)
		local dustPart = helperPart(cast, "Dust", flat + floorUp * 0.4)
		local dust = emitter(cast, dustPart, {
			Texture = CONFIG.ASSETS.Textures.Dust,
			Color = ColorSequence.new(dustColour),
			LightEmission = 0,
			LightInfluence = 1,
			Brightness = 1,
			EmissionDirection = Enum.NormalId.Front,
			SpreadAngle = Vector2.new(6, 3),
			Size = numbers(0, 1.2, 0.3, 3, 1, 4.5),
			Transparency = numbers(0, 0.3, 0.5, 0.55, 1, 1),
			Lifetime = NumberRange.new(w.DUST_LIFETIME * 0.8, w.DUST_LIFETIME),
			Speed = NumberRange.new(w.DUST_SPEED_MIN, w.DUST_SPEED_MAX),
			Drag = 3,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-60, 60),
			ZOffset = -1,
		})
		local n = count(cast, w.DUST)
		for i = 1, n do -- one particle per direction: a ring along the ground
			dustPart.CFrame = flat * CFrame.Angles(0, (i + rngDebris:NextNumber(-0.4, 0.4)) / n * math.pi * 2, 0) + floorUp * 0.4
			dust:Emit(1)
		end
		emitted(cast, n)

		debris(cast, groundPos, floorUp, floorTint, floorMaterial, rngDebris)

		-- the crater (replaces the spear's scorch): dark decal + glowing gold cracks that cool
		local c = S.CRATER
		local plate = helperPart(cast, "Crater", flat + floorUp * (0.03 - w.LIFT))
		plate.Size = Vector3.new(c.SIZE, 0.05, c.SIZE)
		local crater = Instance.new("Decal")
		crater.Texture = CONFIG.ASSETS.Textures.Crater
		crater.Face = Enum.NormalId.Top
		crater.Parent = plate
		track(cast, crater)
		local gui = Instance.new("SurfaceGui") -- the glow: a SurfaceGui lights itself (LightInfluence 0)
		gui.Face = Enum.NormalId.Top
		gui.LightInfluence = 0
		gui.Brightness = c.GLOW_BRIGHTNESS
		gui.CanvasSize = Vector2.new(256, 256)
		gui.Parent = plate
		track(cast, gui)
		local glow = Instance.new("ImageLabel")
		glow.BackgroundTransparency = 1
		glow.Size = UDim2.fromScale(1, 1)
		glow.Image = CONFIG.ASSETS.Textures.CraterGlow
		glow.ImageColor3 = color(CONFIG.PALETTE.GOLD)
		glow.Parent = gui
		track(cast, glow)
		tween(cast, glow, c.GLOW_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In, { ImageTransparency = 1 })
		after(cast, c.SECONDS - c.FADE_SECONDS, function()
			tween(cast, crater, c.FADE_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.In, { Transparency = 1 })
		end)
	end)

	-- SMOKE (RESIDUAL): a dark column rising from the crater
	at(S.SMOKE.AT, function()
		local m = S.SMOKE
		local smoke = burstAt(cast, "Smoke", CFrame.new(groundPos + up * 1), {
			Texture = CONFIG.ASSETS.Textures.Dust,
			Color = ColorSequence.new(color(m.COLOR)),
			LightEmission = 0,
			LightInfluence = 0.6,
			Brightness = 1,
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(12, 12),
			Size = numbers(0, m.SIZE * 0.7, 0.4, m.SIZE * 1.3, 1, m.SIZE * 1.8),
			Transparency = numbers(0, 1, 0.12, m.ALPHA, 0.6, m.ALPHA + 0.15, 1, 1),
			Lifetime = NumberRange.new(m.LIFETIME_MIN, m.LIFETIME_MAX),
			Speed = NumberRange.new(m.SPEED_MIN, m.SPEED_MAX),
			Drag = 0.8,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-25, 25),
			ZOffset = -2,
		})
		local n = rngDebris:NextInteger(m.COUNT_MIN, m.COUNT_MAX)
		smoke:Emit(n)
		emitted(cast, n)
	end)

	-- GROUND ARCS (RESIDUAL): small bolts jumping along the ground round the crater, shrinking
	do
		local g = S.GROUND_ARCS
		local drawn = -1
		local set: { LightningBolt.Bolt? } = {}
		at(g.FROM, function()
			-- the bolt has faded by now; at full speed its last frame can still be up when the arcs start
			-- (stage 7B test: 102 Beams for a frame), so take it away first: the strike stays within 90
			LightningBolt.Release(current)
			local started = os.clock()
			local arcing: RBXScriptConnection
			arcing = RunService.RenderStepped:Connect(function()
				local t = (os.clock() - started) * cast.TimeScale
				if cast.Ended or t >= g.TO - g.FROM then
					arcing:Disconnect()
					return
				end
				local slot = math.floor(t * 30 / g.EVERY_FRAMES)
				if slot == drawn then
					return
				end
				drawn = slot
				for _, old in set do
					LightningBolt.Release(old)
				end
				table.clear(set)
				local shrink = 1 - 0.7 * t / (g.TO - g.FROM)
				for _ = 1, rngArcs:NextInteger(g.MIN, if cast.Low then g.MIN else g.MAX) do
					local yaw = rngArcs:NextNumber(0, math.pi * 2)
					local a = groundPos + Vector3.new(math.cos(yaw), 0, math.sin(yaw)) * rngArcs:NextNumber(0.8, g.RADIUS) + floorUp * 0.15
					local turn = yaw + rngArcs:NextNumber(-1.2, 1.2)
					set[#set + 1] = bolt(cast, {
						From = a,
						To = a + Vector3.new(math.cos(turn), 0, math.sin(turn)) * rngArcs:NextNumber(g.LENGTH_MIN, g.LENGTH_MAX) * shrink,
						Segments = g.SEGMENTS,
						MaxOffset = 0.3 * shrink,
						Thickness = g.THICKNESS * (0.5 + 0.5 * shrink),
						Color = color(CONFIG.PALETTE.YELLOW),
						Lifetime = g.EVERY_FRAMES / 30,
						Rng = rngArcs,
					})
				end
			end)
			table.insert(cast.Connections, arcing)
		end)
	end

	after(cast, S.CLEANUP_AT, function()
		endCast(cast)
	end)
end

ThunderLanceVFX.Config = CONFIG
ThunderLanceVFX.Keyframes = KEYFRAMES

return ThunderLanceVFX

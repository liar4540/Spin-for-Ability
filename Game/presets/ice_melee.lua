-- Preset: ice melee. The final CONFIG of Frost Jab (Game/src/client/Abilities/FrostJabVFX.luau),
-- saved 2026-11-06 as a starting point for future ice / melee-impact skills. Plain values only (easing
-- styles as names: use Enum.EasingStyle[name]). FrostJabVFX reads the gameplay block from
-- Shared/Config/Abilities (the server needs it too), so a new skill copies those values into its own
-- ability entry: Damage (base, before the rarity's Power), Cooldown, Range, WindupSeconds, HitboxWidth,
-- HitboxHeight, SlowMultiplier, SlowSeconds, MinRequestSeconds, DurationSeconds, AnimationId.
--
-- How to use: copy this table into the new skill's CONFIG, change the palette and asset ids, keep the
-- layer order (STARTUP, FLASH, MAIN, SECONDARY, RESIDUAL) and the timeline proportions. Not in the Rojo
-- tree (Game/presets is not synced), so it never ships.
--
-- Looks (Stage 7 vs images/abilities/frost jab.png): the flare must sit at the CONTACT point, not on
-- the fist, and stay about the target's upper-body size (6 studs) at brightness ~1.1 or bloom whites
-- the frame out; shards must fly short (2-3.5 studs) and UP (20-50 deg) or they leave the frame behind
-- the target; the ground ring has to be big (7.5 -> 9.5 studs) with a strong emissive (7) to read.
-- See Game/docs/vfx_notes.md.

return {
	-- Gameplay (Shared/Config/Abilities entry "FrostJab")
	DAMAGE = 8, -- dealt; the ability's base Damage is 8 / 1.35 (Uncommon Power x1.35)
	COOLDOWN = 3,
	DURATION = 0.45,
	HIT_AT = 4 / 30, -- "Hit" marker, frame 4 of 13 @ 30 fps (0.133 s)
	BOX = { WIDTH = 5, HEIGHT = 5, LENGTH = 6, LAG_MARGIN = 1.5 }, -- from the HumanoidRootPart, along the aim
	SLOW_MULTIPLIER = 0.6,
	SLOW_SECONDS = 1.5, -- refreshes on a new hit, never stacks
	MIN_REQUEST_SECONDS = 0.25,

	-- Playback
	TIME_SCALE = 1, -- playback speed; durations are divided by it
	MARKER_GRACE = 0, -- timer races the "Hit" marker, first wins
	SKIP_LATE_AFTER = 2.0, -- server-time age after which an on-hit event is skipped

	PALETTE = { CORE = "#F2FBFF", MAIN = "#A8E6FF", DEEP = "#4FA3D9" },
	BRIGHTNESS = 1.6, -- glow particles; the place's Bloom threshold is 2

	STARTUP = {
		GLOW_COUNT = 2,
		GLOW_SIZE = 1.2,
		GLOW_LIFETIME = 0.2,
		SWIRL_FROM = 1.2, -- Ring mesh round the fist, studs across
		SWIRL_TO = 3.4,
		SWIRL_TILT_DEG = 65,
		SWIRL_TURNS = 1.25,
		SWIRL_FADE_AFTER = 0.06,
	},

	FLASH = {
		SECONDS = 0.1,
		AHEAD = 1.4, -- studs in front of the fist: the contact point
		FLARE_SIZE = 6,
		FLARE_START = 0.4,
		FLARE_BRIGHTNESS = 1.1,
		GLOW_SIZE = 4,
		GLOW_ALPHA = 0.45,
		LIGHT_BRIGHTNESS = 2.5,
		LIGHT_RANGE = 10,
		LIGHT_SECONDS = 0.2,
		POP_STYLE = "Exponential",
	},

	MAIN = {
		COUNT = 4, -- one of each shard variant
		SCALE_FROM = 0.25,
		SCALE_TO = 1.8,
		POP_SECONDS = 0.06,
		DISTANCE_MIN = 2,
		DISTANCE_MAX = 3.5,
		TRAVEL_SECONDS = 0.6,
		SPREAD_DEG = 55,
		RISE_DEG_MIN = 20,
		RISE_DEG_MAX = 50,
		SPIN_DEG = 70,
		FADE_START = 0.3,
		FADE_SECONDS = 0.5,
		POP_STYLE = "Quint",
		FADE_STYLE = "Sine",
	},

	SECONDARY = {
		RING_FROM = 2,
		RING_TO = 7.5,
		RING_SECONDS = 0.2,
		RING_WIDEN_TO = 9.5,
		RING_FADE_START = 0.45,
		RING_FADE_SECONDS = 0.55,
		RING_LIFT = 0.06,
		RING_GLOW = 7,
		CROWN_SCALE = 1.45,
		CROWN_RISE_SECONDS = 0.16,
		CROWN_FADE_START = 0.45,
		CROWN_FADE_SECONDS = 0.45,
		MIST_COUNT = 3,
		MIST_SIZE = 6,
		MIST_LIFETIME = 0.6, -- flipbook framerate = 16 / MIST_LIFETIME
		MIST_ALPHA = 0.3,
		POP_STYLE = "Quint",
		FADE_STYLE = "Sine",
	},

	RESIDUAL = {
		COAT_IN_SECONDS = 0.06,
		COAT_FILL = 0.45,
		COAT_FILL_END = 0.8,
		COAT_OUTLINE = 0.35,
		COAT_BREAK_SECONDS = 0.25,
		SNOWFLAKES = 3,
		SNOWFLAKE_SIZE = 0.7,
		SNOWFLAKE_LIFETIME = 1.3,
		SNOWFLAKE_RISE = 1.4,
		GLINTS = 10,
		GLINT_SIZE = 0.4,
		GLINT_LIFETIME_MIN = 0.5,
		GLINT_LIFETIME_MAX = 1.0,
		CRUMBS = 12,
		CRUMB_SIZE = 0.3,
		CRUMB_LIFETIME = 0.5,
		CRUMB_GRAVITY = 30,
	},

	BUDGET = { PARTICLES = 120, INSTANCES = 15 }, -- measured: 15 VFX objects, ~25 particles max

	-- Asset ids (owned by the game owner, user 202024761; full record: Game/assets/vfx/frost_jab_assets.json)
	ASSETS = {
		Animation = "rbxassetid://78544021138400", -- FrostJab_Punch, marker "Hit"
		Textures = {
			Flare = "rbxassetid://99043809496162",
			Snowflake = "rbxassetid://94567728717612",
			MistFlipbook = "rbxassetid://101720520240051", -- 4x4 grid, 16 frames
			Shard = "rbxassetid://110622299282904", -- on the shard / crown templates
			Ring = "rbxassetid://77037636668101", -- on the ring template
			Sparkle = "rbxassetid://76795312198770", -- Gale Step
			Glow = "rbxassetid://134061496595746", -- Gale Step
		},
		Meshes = { -- mesh id, then the FBX model package it came from
			ShardA = "rbxassetid://74767379733751", -- 112314398617647
			ShardB = "rbxassetid://83748209218763", -- 79627289175874
			ShardC = "rbxassetid://131712182637805", -- 131645774114461
			ShardD = "rbxassetid://124088321679540", -- 102612579066322
			Ring = "rbxassetid://101229161717226", -- 95960061456193
			Crown = "rbxassetid://128961005325770", -- 87164687000244
		},
	},
}

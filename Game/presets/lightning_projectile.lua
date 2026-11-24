-- Preset: lightning projectile. The final CONFIG of Thunder Lance (Game/src/client/Abilities/ThunderLanceVFX.luau),
-- saved 2026-11-10 as a starting point for future lightning / fast-projectile skills, with the sky strike
-- from stage 7B (Prompts/thunder_lance_lighting_strike_prompt). Plain values only (easing styles as names:
-- use Enum.EasingStyle[name]). ThunderLanceVFX reads the gameplay block from Shared/Config/Abilities (the
-- server needs it too), so a new skill copies those values into its own ability entry: Damage (base, before
-- the rarity's Power), Cooldown, Range, WindupSeconds, ProjectileSpeed, ProjectileRadius, HitboxRadius,
-- ThrowOffset, ProjectileLead, ServerClock, MinRequestSeconds, SkyStrike, StrikeDamage, AnimationId.
-- Palette in hex (#FFFDF0 white, #FFE14D yellow, #FFB000 deep gold; #3A3632 smoke, #8A7F70 dust).
--
-- How to use: copy this table into the new skill's CONFIG, change the palette and asset ids, keep the
-- layer order (CRACKLE, FORM, SPEAR, RELEASE, LIGHT, TRAIL, SHED, IMPACT, STRIKE) and the timeline
-- proportions. Not in the Rojo tree (Game/presets is not synced), so it never ships.
--
-- Looks (stage 7 vs images/abilities/thunder_lance_blueprint.png, stage 7B): the trail bolt must ride
-- the spear (LightningBolt.Shift) or it lags behind like a separate streak; arcs on the target jump
-- between NEIGHBOURING limbs, outside the body, or they hide inside it; the scorch needs 6 studs and 2
-- stacked decals to read past the target's own shadow. Strike: keep it under ~0.3 s with weaker later
-- strokes (Vault), give the coloured outer layers LightEmission < 1 or they wash to white, and start the
-- ground arcs only after the bolt is released (90-Beam budget). See Game/docs/vfx_notes.md.

return {
	-- Gameplay (Shared/Config/Abilities entry "ThunderLance"); all balance numbers
	DAMAGE = 18, -- dealt; the ability's base Damage is 18 / 1.35^2 (Rare Power x1.8225)
	COOLDOWN = 6,
	SPEED = 160, -- studs/s, full speed from the first frame of flight
	RANGE = 120, -- studs; at the end the spear fades out with no impact
	HITBOX_RADIUS = 2.5, -- finds characters; much bigger than the spear on purpose (Pebble Toss lesson)
	BODY_RADIUS = 0.175, -- the spear itself (0.35 thick): what stops it at walls and the ground
	MIN_REQUEST_SECONDS = 0.25,
	SUMMON_AT = 4 / 30, -- "Summon" marker, frame 4
	FORM_AT = 8 / 30, -- the spear starts to grow, frame 8
	RELEASE_AT = 15 / 30, -- "Release" marker, frame 15 (= the server's WindupSeconds)
	THROW_OFFSET = { 0.85, 1.33, 2.97 }, -- the hand on the Release frame, from the root (thunder_lance.blend F15)
	LEAD = 4, -- the tip is this far ahead of the grip; the flight tracks the tip

	-- Sky strike (stage 7B): gameplay + the switches players and tuning need
	SKY_STRIKE = true, -- a character hit calls the strike down (Shared/Config/Abilities)
	STRIKE_DAMAGE = 0, -- balance number (Shared/Config/Abilities): 0 = visual only
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
		GROW_STYLE = "Quint", -- Out
		-- the spear's pitch above level while held (deg, by frame): level at F8, tip at eye level F12-F13,
		-- straight at the target from F14
		PITCH = { { 8, 0 }, { 12, 10 }, { 13, 10 }, { 14, 0 } },
	},

	-- SPEAR (MAIN): Neon core 6 x 0.35 studs + inner glow Beam + crossed ribbons (emissive, not Neon)
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

	-- LIGHT (SECONDARY): one PointLight per shot, moved release -> spear glow -> impact
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

	-- Asset ids (Open Cloud; Game/assets/vfx/thunder_lance_assets.json). Meshes are carried by the templates
	-- in ReplicatedStorage.VFX.ThunderLance (mesh ids can't be set at runtime).
	ASSETS = {
		Animation = "rbxassetid://71580696171096", -- ThunderLance_Throw, markers Summon / Release
		Meshes = {
			SpearCore = "rbxassetid://74205448858788", -- spear_core.fbx, 48 tris
			Ribbons = "rbxassetid://137288918407462", -- ribbon_helix.fbx, 96 tris
			Ring = "rbxassetid://108495321187592", -- shock_ring.fbx, 64 tris
		},
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

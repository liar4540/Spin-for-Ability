-- Preset: lightning projectile (stage 7B keys only, 2026-11-08). The sky lightning strike that follows a
-- character hit, from Thunder Lance (Game/src/client/Abilities/ThunderLanceVFX.luau, Prompts/
-- thunder_lance_lighting_strike_prompt). The spear's own CONFIG is added here with section 9.
-- Plain values only. ThunderLanceVFX reads SKY_STRIKE / STRIKE_DAMAGE from Shared/Config/Abilities
-- (SkyStrike, StrikeDamage: the server needs them), so a new skill sets those in its ability entry.
-- Palette in hex (#FFFDF0 white, #FFE14D yellow, #FFB000 deep gold; #3A3632 smoke, #8A7F70 dust).
-- Not in the Rojo tree (Game/presets is not synced), so it never ships.
--
-- Looks (stage 7B, thunder_lance_stage7b_strike.png): keep the strike under ~0.3 s with weaker later
-- strokes (Vault), give the coloured outer layers LightEmission < 1 or they wash to white, and start the
-- ground arcs only after the bolt is released (90-Beam budget). See Game/docs/vfx_notes.md.

return {
	-- Sky strike (stage 7B): gameplay + the switches players and tuning need
	SKY_STRIKE = true, -- a character hit calls the strike down (Shared/Config/Abilities)
	STRIKE_DAMAGE = 0, -- balance number (Shared/Config/Abilities): 0 = visual only
	SHAKE_MAX = 2.2, -- degrees of camera shake at the strike's target; 0 at STRIKE.SHAKE_RADIUS
	SCREEN_FLASH_ENABLED = true, -- the local screen flash (ColorCorrectionEffect on this client's camera)
	REDUCE_FLASHING = false, -- true: no dips between strokes, the star and screen flash much dimmer
	STRIKE_SOUND_ID = "", -- played at the ground position when set (a close thunder crack)

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
}

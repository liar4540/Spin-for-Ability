-- Preset: wind dash. The final CONFIG of Gale Step (Game/src/client/Abilities/GaleStepVFX.luau),
-- saved 2026-11-04 as a starting point for future wind skills. Plain values only: GaleStepVFX reads
-- COOLDOWN / DASH_STUDS / MAX_DASH_STUDS / DASH_START from Shared/Config/Abilities (the server needs
-- them too), so a new skill copies those four into its own ability entry.
--
-- How to use: copy this table into the new skill's CONFIG, change the palette and asset ids, and keep
-- the timeline proportions. Not in the Rojo tree (Game/presets is not synced), so it never ships.
--
-- Looks (Stage 6 vs images/abilities/gale step.png): cyan carries every shape, white is only a thin
-- core line; big additive particles stay translucent (SWIRL_BRIGHTNESS < 1) or they blow out to white;
-- speed-line beams use the bold wind_gradient texture, not the hair-thin wind_streaks.

return {
	-- Movement (studs, seconds)
	COOLDOWN = 4,
	DASH_STUDS = 30,
	DASH_SECONDS = 0.3,
	MAX_DASH_STUDS = 32, -- server pulls back anything further
	WALL_CLEARANCE = 2, -- the front of the body stops this far before a wall
	BODY_RADIUS = 1.2, -- sphere swept ahead to find walls
	BODY_REACH = 2.55, -- body reach ahead of the root at the brake (arm swung out)
	DASH_START = 0.2, -- "DashStart" animation marker, frame 6 @ 30 fps
	MARKER_GRACE = 0.08,
	FOV_KICK = 8, -- degrees, dasher's camera only

	-- Timeline (seconds at normal speed)
	CHARGE_SECONDS = 0.15,
	BURST_AT = 0.15,
	FINISH_SECONDS = 0.25,
	FADE_SECONDS = 0.45,

	-- Palette (hex)
	CORE = "#E9FBFF",
	MAIN = "#7FE6FF",
	EDGE = "#2FA8D8",
	BRIGHTNESS = 1.8, -- particles/beams/trails; the place's Bloom threshold is 2

	-- 1. Charge
	CHARGE_RING_FROM = 2, -- studs across
	CHARGE_RING_TO = 5,
	CHARGE_RING_TURNS = 2, -- turns per second
	CHARGE_RING_ALPHA = 0.8,
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
	TRAIL_WIDTH = 0.8,
	TRAIL_LIFETIME = 0.25,
	AFTERIMAGE_EVERY = 0.05,
	AFTERIMAGE_FROM = 0.4,
	AFTERIMAGE_SECONDS = 0.3,
	RIDING_STREAKS = 10,
	RIDING_STREAK_MIN = 9,
	RIDING_STREAK_MAX = 15,
	PATH_STREAKS = 4,
	PATH_STREAK_MIN = 6,
	PATH_STREAK_MAX = 10,
	SPARKLES_PER_SECOND = 20,
	SPARKLE_LIFETIME = 0.4,
	WISPS_PER_SECOND = 30,
	DASH_ORBIT_TURNS = 2.5,
	TUNNEL_RING_EVERY = 6,
	TUNNEL_RING_FROM = 2.5,
	TUNNEL_RING_TO = 6.5,
	TUNNEL_RING_SECONDS = 0.3,
	SLICE_EVERY = 0.075,
	SLICE_SECONDS = 0.22,
	AURA_PER_SECOND = 30,
	GROUND_STREAK_WIDTH = 2,
	GROUND_STREAK_SECONDS = 0.35,
	SKIM_DUST_PER_SECOND = 15,

	-- 4. Finish
	SPIRAL_TURNS = 1.5,
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

	-- Asset ids (owned by the game owner, user 202024761; full record: Game/assets/vfx/gale_step_assets.json)
	ASSETS = {
		Animation = "rbxassetid://130755455737261", -- GaleStep_Dash, markers DashStart / DashEnd
		Textures = {
			WindGradient = "rbxassetid://115854320689894",
			WindStreaks = "rbxassetid://83090249483866",
			Sparkle = "rbxassetid://76795312198770",
			SoftGlow = "rbxassetid://134061496595746",
			WindWisp = "rbxassetid://115689752915482",
			SwirlFlipbook = "rbxassetid://76836933588665", -- 4x4 grid, 16 frames
			Dust = "rbxassetid://119015403999595", -- dust_puff (Pebble Toss)
		},
		Meshes = { -- mesh id, then the FBX model package it came from
			CrescentA = "rbxassetid://81358747084401", -- 97251964717099
			CrescentB = "rbxassetid://73019651433783", -- 139020940779892
			Ring = "rbxassetid://90664669742250", -- 71169891453451
			Spiral = "rbxassetid://115628997654552", -- 85431287904931
		},
	},
}

--!strict
-- Uploaded asset ids: textures, icons, sounds. The one place to change an id.
-- Every texture + icon is made in Blender (Game/assets/vfx/_src/build_ember_fist.py → assets/vfx/textures)
-- and is white/grey, recoloured in Studio (vault: 11 Abilities → Rules).
-- The *Sprite textures are the shared kit meshes rendered from Blender (ring, spike burst, crescent):
-- they're played on oriented particles, so no MeshPart upload is needed.

local Assets = {
	Textures = {
		Flame = "rbxassetid://140649091076074", -- 2x2 flipbook, 4 flame frames
		Glow = "rbxassetid://100239935846783",
		Spark = "rbxassetid://136293881571055",
		Ember = "rbxassetid://110353874213807",
		Smoke = "rbxassetid://75683646724956",
		RingSprite = "rbxassetid://115453507528445", -- shock_ring from above
		BurstSprite = "rbxassetid://130992288543502", -- spike_burst head-on
		ArcSprite = "rbxassetid://89864997764366", -- crescent_thin from above (circle centre below the middle)
		-- Pebble Toss (Game/assets/vfx/_src/build_pebble_toss_textures.py)
		PebbleDust = "rbxassetid://119015403999595", -- dust_puff: soft cloudy blob
		PebbleFlare = "rbxassetid://131269676715023", -- impact_flare: 8-point star, bright centre
		PebbleSpeedLines = "rbxassetid://79833122077124", -- speed_lines: solid left, fading right (Beam)
	},

	Icons = {
		EmberFist = "rbxassetid://136390253489761",
	},

	-- Roblox-licensed library sounds (Pro Sound Effects).
	Sounds = {
		EmberFistWindup = "rbxassetid://9114446852", -- Fire Whoosh 15
		EmberFistImpact = "rbxassetid://9114442751", -- Fire Whoosh 2 (short punchy bursts)
	},
}

return Assets

--!strict
-- Every ability's stats. Starter set from the vault's Ideas Inbox (original names).
-- Placeholder set until ability design: Ascended and Divine have none yet, so the
-- odds screen leaves them out and their chance is shared by the other tiers.
-- Damage here is BASE damage; the rarity's Power (x1.35 per tier) and level are applied on top.
-- Numbers are placeholders: tune them in playtests.

local Types = require(script.Parent.Parent.Types)
local Assets = require(script.Parent.Assets)

type AbilityDef = Types.AbilityDef

local Abilities: { AbilityDef } = {
	{
		Id = "EmberFist",
		Name = "Ember Fist",
		Rarity = "Common",
		Type = "Melee",
		Damage = 12,
		Cooldown = 5,
		Range = 6,
		WindupSeconds = 0.27,
		HitboxWidth = 5,
		Knockback = 22, -- "small knockback" (vault): about 4 studs on a dummy
		AnimationId = nil, -- uploaded animation id; nil plays the Studio test animation (client/Abilities/Pose)
		Icon = Assets.Icons.EmberFist,
		Description = "A fiery punch with a small knockback.",
	},
	{
		Id = "PebbleToss",
		Name = "Pebble Toss",
		Rarity = "Common",
		Type = "Projectile",
		Damage = 8,
		Cooldown = 4,
		Range = 60, -- about 1.1 s of flight; shatters at the end if it hits nothing
		WindupSeconds = 0.4, -- the animation's "Release" marker (frame 12 @ 30 fps)
		ProjectileSpeed = 55,
		ProjectileRadius = 0.6, -- the rock (1.2 across): what stops it at walls and the ground
		HitboxRadius = 2.5, -- the sphere that finds characters; much bigger than the rock, so near misses hit
		Knockback = 8,
		AnimationId = nil, -- uploaded animation id; nil plays the Studio test animation (client/Abilities/Pose)
		Description = "Throws a quick rock that shatters into chips on hit.",
	},
	{
		Id = "GaleStep",
		Name = "Gale Step",
		Rarity = "Uncommon",
		Type = "Movement",
		Damage = 0,
		Cooldown = 4, -- the server checks this one (client/Abilities/GaleStepVFX CONFIG.COOLDOWN reads it)
		Range = 30, -- studs dashed, toward where the camera faces; stops 2 studs short of walls
		WindupSeconds = 0.2, -- the animation's "DashStart" marker (frame 6 @ 30 fps)
		MaxDashStuds = 32, -- the server pulls a player back if one dash moves them further than this
		DashWindowSeconds = 1, -- how long after the key press the server watches the dash
		AnimationId = "rbxassetid://130755455737261", -- GaleStep_Dash (Game/assets/gale_step.blend)
		Description = "An extremely fast dash with wind trails.",
	},
	{
		-- Numbers from Prompts/frost_jab_prompt.md; client/Abilities/FrostJabVFX CONFIG reads them.
		Id = "FrostJab",
		Name = "Frost Jab",
		Rarity = "Uncommon",
		Type = "Melee",
		Damage = 8 / 1.35, -- the hit deals exactly 8 after Uncommon's Power (x1.35)
		Cooldown = 3,
		Range = 6, -- box length in front of the HumanoidRootPart (HitboxService adds its 1.5-stud lag margin)
		WindupSeconds = 4 / 30, -- the animation's "Hit" marker: frame 4, where the fist is furthest out
		HitboxWidth = 5,
		HitboxHeight = 5,
		SlowMultiplier = 0.6, -- WalkSpeed x 0.6...
		SlowSeconds = 1.5, -- ...for 1.5 s; a new hit refreshes it
		MinRequestSeconds = 0.25, -- at most 1 request per 0.25 s
		DurationSeconds = 0.45,
		AnimationId = "rbxassetid://78544021138400", -- FrostJab_Punch (Game/assets/frost_jab.blend)
		Description = "An icy punch that slows briefly.",
	},
	{
		-- Numbers from Prompts/thunder_lance_prompt; client/Abilities/ThunderLanceVFX CONFIG reads them.
		Id = "ThunderLance",
		Name = "Thunder Lance",
		Rarity = "Rare",
		Type = "Projectile",
		Damage = 18 / 1.35 ^ 2, -- the hit deals exactly 18 after Rare's Power (x1.35 per tier above Common)
		Cooldown = 6,
		Range = 120, -- studs of flight; at the end it fades out with no impact
		WindupSeconds = 15 / 30, -- the animation's "Release" marker: frame 15, the hand's fastest frame
		ProjectileSpeed = 160,
		ProjectileRadius = 0.175, -- the spear (0.35 thick): what stops it at walls and the ground
		HitboxRadius = 2.5, -- finds characters; deliberately much bigger than the spear (Pebble Toss lesson)
		ThrowOffset = Vector3.new(0.85, 1.33, 2.97), -- the hand on the Release frame (thunder_lance.blend F15)
		ProjectileLead = 4, -- the spear's tip is 4 studs ahead of the grip; the flight tracks the tip
		ServerClock = true, -- flown on the server clock and announced with AbilityLaunch (AbilityService)
		MinRequestSeconds = 0.25, -- at most 1 request per 0.25 s
		SkyStrike = true, -- stage 7B: a character hit calls a lightning strike down onto the target (AbilityStrike)
		StrikeDamage = 0, -- balance number: the strike is visual only for now (dealt 0.15 s after the hit)
		AnimationId = "rbxassetid://71580696171096", -- ThunderLance_Throw (Game/assets/thunder_lance.blend); markers Summon F4, Release F15
		Description = "A fast lightning spear that flies in a straight line.",
	},
	{
		Id = "FrostBloom",
		Name = "Frost Bloom",
		Rarity = "Epic",
		Type = "AoE",
		Damage = 15,
		Cooldown = 12,
		Range = 14,
		Description = "An ice flower that slows everyone nearby.",
	},
	{
		Id = "BloodMoonSlash",
		Name = "Blood Moon Slash",
		Rarity = "Legendary",
		Type = "Melee",
		Damage = 28,
		Cooldown = 14,
		Range = 12,
		Description = "A wide crescent slash with a red glow.",
	},
	{
		Id = "VoidEclipse",
		Name = "Void Eclipse",
		Rarity = "Mythic",
		Type = "AoE",
		Damage = 30,
		Cooldown = 20,
		Range = 18,
		Description = "A black sphere that pulls players in.",
	},
	{
		Id = "ZeroHour",
		Name = "Zero Hour",
		Rarity = "Secret",
		Type = "AoE",
		Damage = 20,
		Cooldown = 25,
		Range = 24,
		Description = "Freezes time around you for 1.5 seconds.",
	},
}

return Abilities

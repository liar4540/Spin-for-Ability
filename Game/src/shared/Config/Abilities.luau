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
		Id = "ThunderLance",
		Name = "Thunder Lance",
		Rarity = "Rare",
		Type = "Projectile",
		Damage = 18,
		Cooldown = 8,
		Range = 60,
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

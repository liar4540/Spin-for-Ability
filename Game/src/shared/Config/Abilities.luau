--!strict
-- Every ability's stats. Starter set from the vault's Ideas Inbox (original names).
-- Placeholder set until ability design: Ascended and Divine have none yet, so the
-- odds screen leaves them out and their chance is shared by the other tiers.
-- Damage here is BASE damage; the rarity's Power (x1.35 per tier) and level are applied on top.
-- Numbers are placeholders: tune them in playtests.

local Types = require(script.Parent.Parent.Types)

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
		Description = "A fiery punch with a small knockback.",
	},
	{
		Id = "GaleStep",
		Name = "Gale Step",
		Rarity = "Uncommon",
		Type = "Movement",
		Damage = 0,
		Cooldown = 6,
		Range = 20,
		Description = "A quick dash with a wind trail.",
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

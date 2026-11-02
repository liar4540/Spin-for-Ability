--!strict
-- Rarity tiers. The ONLY place the "1 in N" numbers live.
-- Never type odds anywhere else: the Odds module turns these into real chances
-- for both the server roll and the odds screen (vault: 03 Systems → Spin / RNG Roll).
--
--   OneIn   "1 in N" check (rarest first). Luck turns it into "luck in N" if Lucky.
--   Power   damage/healing/shield multiplier: x1.35 per tier (Secret ≈ 11x Common).
--   Shards  what skipping a result of this tier gives.

local Types = require(script.Parent.Parent.Types)

type Rarity = Types.Rarity
type RarityDef = Types.RarityDef

local Rarities = {}

-- How much stronger each tier is than the one below (vault: 03 Systems → Ability power by rarity).
-- Lower it here (e.g. 1.25) if PvP feels unfair; every ability follows.
Rarities.PowerPerTier = 1.35

-- Rarest first. The roll checks tiers in this order; Common is the fallback.
local ORDER: { Rarity } = { "Secret", "Divine", "Mythic", "Ascended", "Legendary", "Epic", "Rare", "Uncommon", "Common" }
Rarities.Order = ORDER

local function power(rank: number): number
	return Rarities.PowerPerTier ^ (rank - 1)
end

local DEFS: { [Rarity]: RarityDef } = {
	Secret = {
		Name = "Secret",
		Rank = 9,
		OneIn = 250000,
		Lucky = true,
		Color = Color3.fromHex("#000000"), -- shown with an animated rainbow UIGradient
		RevealSeconds = 5,
		Power = power(9),
		Shards = 10000,
	},
	Divine = {
		Name = "Divine",
		Rank = 8,
		OneIn = 50000,
		Lucky = true,
		Color = Color3.fromHex("#FFF1C4"), -- white-gold, shown with a glow
		RevealSeconds = 5,
		Power = power(8),
		Shards = 2000,
	},
	Mythic = {
		Name = "Mythic",
		Rank = 7,
		OneIn = 10000,
		Lucky = true,
		Color = Color3.fromHex("#FF3B3B"),
		RevealSeconds = 4,
		Power = power(7),
		Shards = 500,
	},
	Ascended = {
		Name = "Ascended",
		Rank = 6,
		OneIn = 1000,
		Lucky = true,
		Color = Color3.fromHex("#FF4FD8"),
		RevealSeconds = 3.5,
		Power = power(6),
		Shards = 100,
	},
	Legendary = {
		Name = "Legendary",
		Rank = 5,
		OneIn = 100,
		Lucky = true,
		Color = Color3.fromHex("#FF9F1C"),
		RevealSeconds = 3,
		Power = power(5),
		Shards = 30,
	},
	Epic = {
		Name = "Epic",
		Rank = 4,
		OneIn = 25,
		Lucky = true,
		Color = Color3.fromHex("#A64DFF"),
		RevealSeconds = 2,
		Power = power(4),
		Shards = 10,
	},
	Rare = {
		Name = "Rare",
		Rank = 3,
		OneIn = 8,
		Lucky = false, -- luck never boosts Rare and below, so luck can't wipe out Common
		Color = Color3.fromHex("#3D8BFF"),
		RevealSeconds = 1.5,
		Power = power(3),
		Shards = 4,
	},
	Uncommon = {
		Name = "Uncommon",
		Rank = 2,
		OneIn = 3,
		Lucky = false,
		Color = Color3.fromHex("#7BD65A"),
		RevealSeconds = 1.5,
		Power = power(2),
		Shards = 2,
	},
	Common = {
		Name = "Common",
		Rank = 1,
		OneIn = nil, -- fallback: whatever is left
		Lucky = false,
		Color = Color3.fromHex("#B0B4BE"),
		RevealSeconds = 1.5,
		Power = power(1),
		Shards = 1,
	},
}
Rarities.Defs = DEFS

-- Luck rules (vault: 03 Systems → Luck).
Rarities.BaseLuck = 1
Rarities.LuckCap = 5

-- Pity (two counters, both saved). Legendary pity is checked first.
--   The 300th spin in a row without Legendary+ is guaranteed Legendary+.
--   The 50th spin in a row without Epic+ is guaranteed Epic+.
Rarities.LegendaryPitySpins = 300
Rarities.LegendaryPityMinRarity = "Legendary" :: Rarity
Rarities.PitySpins = 50
Rarities.PityMinRarity = "Epic" :: Rarity

-- First spin: the very first spin is guaranteed Rare+ (the tutorial's "wow" moment).
Rarities.FirstGuaranteedSpins = 1
Rarities.FirstSpinsMinRarity = "Rare" :: Rarity

return Rarities

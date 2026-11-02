--!strict
-- Odds: the ONE place spin chances are worked out.
--
-- The server rolls with Odds.RollFrom(Odds.Build(...)) and the odds screen shows
-- Odds.AbilityChances(...), and both come from the same table, so what players see
-- is exactly what the server rolls. Roblox requires this for paid random items
-- (paid luck counts). Vault: 03 Systems → Spin / RNG Roll, 04 Monetization.
--
-- How a spin works:
--   1. Check tiers rarest first (Secret → Rare). Each has a "1 in N" check; the first hit wins.
--      Luck turns "1 in N" into "luck in N" for Epic and rarer only. Nothing hit → Common.
--   2. Tiers with no abilities, or below a guarantee (pity / first spin), get 0
--      and the rest are scaled back up to 100%.
--   3. Pick an ability in that tier, each equally likely.

local Types = require(script.Parent.Types)
local Rarities = require(script.Parent.Config.Rarities)

type Rarity = Types.Rarity
type AbilityDef = Types.AbilityDef
type AbilityChance = Types.AbilityChance
type LuckSources = Types.LuckSources

-- A ready-to-roll table. Build it once, roll from it many times.
export type OddsTable = {
	Luck: number,
	MinRarity: Rarity?,
	TierChance: { [Rarity]: number }, -- 0..1, adds up to 1
	ByTier: { [Rarity]: { AbilityDef } },
}

local Odds = {}

-- Total luck from every source: added together, then capped (1x..5x).
function Odds.EffectiveLuck(sources: LuckSources): number
	local luck = Rarities.BaseLuck
	if sources.HasLuckPass then
		luck += 1
	end
	luck += math.max(0, sources.PotionBonus)
	luck += math.max(0, sources.AreaBonus)
	if sources.ServerLuck then
		luck += 1
	end
	return math.clamp(luck, Rarities.BaseLuck, Rarities.LuckCap)
end

-- Which guarantee applies to the NEXT spin, if any. The highest one wins.
--   pityCounter:          spins in a row without Epic+ (saved in the profile)
--   legendaryPityCounter: spins in a row without Legendary+ (saved in the profile)
--   totalSpins:           spins done so far
function Odds.MinRarityFor(pityCounter: number, legendaryPityCounter: number, totalSpins: number): Rarity?
	if legendaryPityCounter >= Rarities.LegendaryPitySpins - 1 then
		return Rarities.LegendaryPityMinRarity -- this is the 300th spin without Legendary+
	end
	if pityCounter >= Rarities.PitySpins - 1 then
		return Rarities.PityMinRarity -- this is the 50th spin without Epic+
	end
	if totalSpins < Rarities.FirstGuaranteedSpins then
		return Rarities.FirstSpinsMinRarity
	end
	return nil
end

-- Real chance of each tier (0..1, adds up to 1).
--   minRarity: tiers below it get 0 (pity / first-spin guarantee)
--   hasAbilities: if given, tiers missing from it get 0 (no ability to give)
function Odds.TierChances(luck: number, minRarity: Rarity?, hasAbilities: { [Rarity]: boolean }?): { [Rarity]: number }
	luck = math.clamp(luck, Rarities.BaseLuck, Rarities.LuckCap)
	local minRank = if minRarity then Rarities.Defs[minRarity].Rank else 1

	-- Step 1: rarest-first checks.
	local raw: { [Rarity]: number } = {}
	local rest = 1 -- chance that no rarer tier hit yet
	for _, rarity in Rarities.Order do
		local def = Rarities.Defs[rarity]
		local oneIn = def.OneIn
		if oneIn then
			local hit = math.min(1, (if def.Lucky then luck else 1) / oneIn)
			raw[rarity] = hit * rest
			rest *= 1 - hit
		else
			raw[rarity] = rest -- Common: nothing rarer hit
		end
	end

	-- Step 2: drop tiers that can't be given, scale the rest back up to 100%.
	local total = 0
	local allowed: { [Rarity]: boolean } = {}
	for _, rarity in Rarities.Order do
		local ok = Rarities.Defs[rarity].Rank >= minRank and (hasAbilities == nil or hasAbilities[rarity] == true)
		allowed[rarity] = ok
		if ok then
			total += raw[rarity]
		end
	end
	assert(total > 0, "Odds.TierChances: no tier can be rolled (check abilities and guarantees)")

	local chances: { [Rarity]: number } = {}
	for _, rarity in Rarities.Order do
		chances[rarity] = if allowed[rarity] then raw[rarity] / total else 0
	end
	return chances
end

-- Build a roll table for one player's next spin.
function Odds.Build(luck: number, minRarity: Rarity?, abilities: { AbilityDef }): OddsTable
	local byTier: { [Rarity]: { AbilityDef } } = {}
	local hasAbilities: { [Rarity]: boolean } = {}
	for _, ability in abilities do
		local list = byTier[ability.Rarity]
		if not list then
			list = {}
			byTier[ability.Rarity] = list
		end
		table.insert(list, ability)
		hasAbilities[ability.Rarity] = true
	end

	return {
		Luck = math.clamp(luck, Rarities.BaseLuck, Rarities.LuckCap),
		MinRarity = minRarity,
		TierChance = Odds.TierChances(luck, minRarity, hasAbilities),
		ByTier = byTier,
	}
end

-- Server: roll one ability from a built table.
function Odds.RollFrom(oddsTable: OddsTable, rng: Random): AbilityDef
	local x = rng:NextNumber() -- 0 <= x < 1
	local cumulative = 0
	local picked: Rarity? = nil
	local lastAllowed: Rarity? = nil
	for _, rarity in Rarities.Order do
		local chance = oddsTable.TierChance[rarity]
		if chance > 0 then
			lastAllowed = rarity
			cumulative += chance
			if x < cumulative then
				picked = rarity
				break
			end
		end
	end
	-- Rounding can leave the sum a hair under 1; land on the last allowed tier.
	local tier = (picked or lastAllowed) :: Rarity
	local list = oddsTable.ByTier[tier]
	return list[rng:NextInteger(1, #list)]
end

-- Odds screen: the real chance of every ability, rarest first. Adds up to 1.
function Odds.AbilityChances(oddsTable: OddsTable): { AbilityChance }
	local rows: { AbilityChance } = {}
	for _, rarity in Rarities.Order do
		local list = oddsTable.ByTier[rarity]
		local tierChance = oddsTable.TierChance[rarity]
		if list and tierChance > 0 then
			for _, ability in list do
				table.insert(rows, {
					AbilityId = ability.Id,
					Rarity = rarity,
					Chance = tierChance / #list,
				})
			end
		end
	end
	return rows
end

-- Format a chance (0..1) as a percentage the way Roblox's odds rules allow:
-- at least 4 digits from the first non-zero digit, and never "0%" for a real chance.
--   0.752322 → "75.2322%", 0.00009999 → "0.009999%", 0.000004 → "0.0004000%"
function Odds.FormatPercent(chance: number): string
	local pct = chance * 100
	if pct <= 0 then
		return "0%"
	end
	if pct >= 100 then
		return "100%"
	end
	local decimals = if pct >= 1 then 4 else math.ceil(-math.log10(pct)) + 3
	decimals = math.min(decimals, 12)
	return string.format("%." .. decimals .. "f%%", pct)
end

-- Optional extra next to the %: "about 1 in 10,000".
function Odds.FormatOneIn(chance: number): string
	if chance <= 0 then
		return "never"
	end
	local n = math.floor(1 / chance + 0.5)
	local text = tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if text:sub(1, 1) == "," then
		text = text:sub(2)
	end
	return "about 1 in " .. text
end

return Odds

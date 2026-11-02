--!strict
-- Tests for the shared Odds module. Runs in Studio only (see init.server.luau).
-- Checks the math against hand-worked numbers (vault: 03 Systems odds table)
-- and rolls 1,000,000 times to prove the server roll matches the odds screen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Odds = require(Shared:WaitForChild("Odds"))
local Abilities = require(Config:WaitForChild("Abilities"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Types = require(Shared:WaitForChild("Types"))

type Rarity = Types.Rarity
type AbilityDef = Types.AbilityDef

local OddsTest = {}

local passed = 0
local failed = 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		warn(`[OddsTest] FAIL: {name}{if detail then " → " .. detail else ""}`)
	end
end

local function near(a: number, b: number, tolerance: number): boolean
	return math.abs(a - b) <= tolerance
end

local function sum(chances: { [Rarity]: number }): number
	local total = 0
	for _, chance in chances do
		total += chance
	end
	return total
end

-- Chi-square critical values at p = 0.001 (so a correct roll fails only 1 run in 1,000).
local CHI_CRITICAL = { 10.828, 13.816, 16.266, 18.467, 20.515, 22.458, 24.322, 26.124, 27.877, 29.588 }

local function chiSquareRolls(label: string, luck: number, minRarity: Rarity?, abilities: { AbilityDef }, rolls: number)
	local oddsTable = Odds.Build(luck, minRarity, abilities)
	local rows = Odds.AbilityChances(oddsTable)
	local rng = Random.new(20261102)

	local counts: { [string]: number } = {}
	for _ = 1, rolls do
		local id = Odds.RollFrom(oddsTable, rng).Id
		counts[id] = (counts[id] or 0) + 1
	end

	-- Every rolled ability must be on the odds screen (nothing hidden, nothing impossible).
	local shown: { [string]: boolean } = {}
	for _, row in rows do
		shown[row.AbilityId] = true
	end
	for id in counts do
		check(`{label}: rolled {id} is on the odds screen`, shown[id] == true)
	end

	-- Group rows (rarest first) into buckets with at least 5 expected hits each.
	local buckets: { { expected: number, observed: number } } = {}
	local current = { expected = 0, observed = 0 }
	for _, row in rows do
		current.expected += row.Chance * rolls
		current.observed += counts[row.AbilityId] or 0
		if current.expected >= 5 then
			table.insert(buckets, current)
			current = { expected = 0, observed = 0 }
		end
	end
	if current.expected > 0 then
		if #buckets > 0 then
			buckets[#buckets].expected += current.expected
			buckets[#buckets].observed += current.observed
		else
			table.insert(buckets, current)
		end
	end

	local chi = 0
	for _, bucket in buckets do
		chi += (bucket.observed - bucket.expected) ^ 2 / bucket.expected
	end
	local df = #buckets - 1
	if df < 1 then
		check(`{label}: only one possible result`, #rows >= 1)
		return
	end
	local critical = CHI_CRITICAL[math.min(df, #CHI_CRITICAL)]
	check(
		`{label}: {rolls} rolls match the odds screen (chi² {string.format("%.2f", chi)} < {critical}, df {df})`,
		chi < critical,
		`chi² = {chi}`
	)
end

function OddsTest.Run()
	passed, failed = 0, 0
	local started = os.clock()

	-- Luck adds up and is capped at 5x.
	check("luck: nothing = 1x", Odds.EffectiveLuck({ HasLuckPass = false, PotionBonus = 0, AreaBonus = 0, ServerLuck = false }) == 1)
	check(
		"luck: pass + potion + Area 2 = 3.2x",
		near(Odds.EffectiveLuck({ HasLuckPass = true, PotionBonus = 1, AreaBonus = 0.2, ServerLuck = false }), 3.2, 1e-9)
	)
	check(
		"luck: everything is capped at 5x",
		Odds.EffectiveLuck({ HasLuckPass = true, PotionBonus = 2, AreaBonus = 0.5, ServerLuck = true }) == 5
	)

	-- Real tier chances at 1x match the vault table.
	local base = Odds.TierChances(1, nil, nil)
	local expected1x: { [Rarity]: number } = {
		Common = 0.553776925,
		Uncommon = 0.276888462,
		Rare = 0.118666484,
		Epic = 0.039555495,
		Legendary = 0.009988761,
		Ascended = 0.000999876,
		Mythic = 0.000099998,
		Divine = 0.000020000,
		Secret = 0.000004000,
	}
	for rarity, value in expected1x do
		check(`1x {rarity} ≈ {value}`, near(base[rarity], value, 1e-8), tostring(base[rarity]))
	end

	-- At max luck Common still exists, Rare and below are not boosted, and every case adds up to 100%.
	local max = Odds.TierChances(5, nil, nil)
	check("5x: Common is still ~44%", near(max.Common, 0.440843202, 1e-8), tostring(max.Common))
	check("5x: Ascended ≈ 0.4997%", near(max.Ascended, 0.004996900, 1e-8), tostring(max.Ascended))
	check("5x: Divine ≈ 0.0100%", near(max.Divine, 0.000099998, 1e-8), tostring(max.Divine))

	-- Power: x1.35 per tier, Secret ≈ 11x Common.
	check("power: Common = 1", Rarities.Defs.Common.Power == 1)
	check("power: Uncommon = 1.35", near(Rarities.Defs.Uncommon.Power, 1.35, 1e-9))
	check("power: Secret ≈ 11.03", near(Rarities.Defs.Secret.Power, 1.35 ^ 8, 1e-9), tostring(Rarities.Defs.Secret.Power))
	check("9 tiers in order", #Rarities.Order == 9 and Rarities.Order[1] == "Secret" and Rarities.Order[9] == "Common")

	local guarantees: { Rarity? } = { "Rare", "Epic", "Legendary" }
	for _, luck in { 1, 2, 3.2, 5 } do
		-- Index 0 = no guarantee (a list can't hold nil, so it's handled separately).
		for i = 0, #guarantees do
			local minRarity: Rarity? = if i == 0 then nil else guarantees[i]
			local chances = Odds.TierChances(luck, minRarity, nil)
			check(`sum = 100% (luck {luck}, min {minRarity or "none"})`, near(sum(chances), 1, 1e-12), tostring(sum(chances)))
		end
	end
	check("luck above the cap is treated as 5x", Odds.TierChances(30, nil, nil).Secret == Odds.TierChances(5, nil, nil).Secret)

	-- Guarantees.
	local pity = Odds.TierChances(1, "Epic", nil)
	check("pity: no Common", pity.Common == 0)
	check("pity: no Rare", pity.Rare == 0)
	check("pity: no Uncommon", pity.Uncommon == 0)
	local legendaryPity = Odds.TierChances(1, "Legendary", nil)
	check("legendary pity: no Epic", legendaryPity.Epic == 0)
	check("legendary pity: sum 100%", near(sum(legendaryPity), 1, 1e-12))
	-- MinRarityFor(epicPity, legendaryPity, totalSpins)
	check("epic pity 49 → Epic+", Odds.MinRarityFor(49, 100, 500) == "Epic")
	check("epic pity 48 → nothing", Odds.MinRarityFor(48, 100, 500) == nil)
	check("legendary pity 299 → Legendary+", Odds.MinRarityFor(10, 299, 500) == "Legendary")
	check("legendary pity 298 → nothing", Odds.MinRarityFor(10, 298, 500) == nil)
	check("both due → Legendary+ wins", Odds.MinRarityFor(49, 299, 500) == "Legendary")
	check("first spin → Rare+", Odds.MinRarityFor(0, 0, 0) == "Rare")
	check("second spin → nothing", Odds.MinRarityFor(1, 1, 1) == nil)

	-- Empty tiers get 0 and the rest scale up.
	local noSecret: { AbilityDef } = {}
	for _, ability in Abilities do
		if ability.Rarity ~= "Secret" then
			table.insert(noSecret, ability)
		end
	end
	local rows = Odds.AbilityChances(Odds.Build(1, nil, noSecret))
	local total = 0
	for _, row in rows do
		total += row.Chance
		check(`no-Secret table has no Secret rows ({row.AbilityId})`, row.Rarity ~= "Secret")
	end
	check("ability rows add up to 100%", near(total, 1, 1e-12), tostring(total))

	-- Percent formatting (Roblox rounding rule, never 0% for a real chance).
	check("format 75.2322%", Odds.FormatPercent(0.752322) == "75.2322%", Odds.FormatPercent(0.752322))
	check("format Mythic", Odds.FormatPercent(0.00009999) == "0.009999%", Odds.FormatPercent(0.00009999))
	check("format Secret", Odds.FormatPercent(0.000004) == "0.0004000%", Odds.FormatPercent(0.000004))
	check("format tiny chance is not 0%", Odds.FormatPercent(1e-9) ~= "0%", Odds.FormatPercent(1e-9))
	check("format 1 in 10,000", Odds.FormatOneIn(0.0001) == "about 1 in 10,000", Odds.FormatOneIn(0.0001))
	check("format 1 in 250,000", Odds.FormatOneIn(0.000004) == "about 1 in 250,000", Odds.FormatOneIn(0.000004))

	-- The big one: the server roll matches the odds screen.
	chiSquareRolls("luck 1x", 1, nil, Abilities, 1_000_000)
	chiSquareRolls("luck 5x", 5, nil, Abilities, 1_000_000)
	chiSquareRolls("pity spin", 1, "Epic", Abilities, 200_000)
	chiSquareRolls("legendary pity spin", 1, "Legendary", Abilities, 200_000)
	-- Secret/Mythic are too rare to see in a normal run, so test them with only top tiers allowed.
	chiSquareRolls("top tiers only", 5, "Mythic", Abilities, 200_000)

	local seconds = os.clock() - started
	local summary = `[OddsTest] {passed} passed, {failed} failed ({string.format("%.1f", seconds)} s)`
	if failed > 0 then
		warn(summary)
	else
		print(summary)
	end
	return failed == 0
end

return OddsTest

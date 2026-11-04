--!strict
-- SpinService: free, unlimited spins (vault: 03 Systems → Spin / RNG Roll, 07 Tech Plan → Spin logic).
--
--   RequestSpin (RemoteFunction) → checks → luck → guarantee → roll with the shared Odds module
--   → the result WAITS for the player's choice (it is not stored automatically)
--   ChooseResult (RemoteFunction) → "Keep" / "Equip" / "Skip", answers Ok or why not
--
-- Rules:
--   * Spinning is free. The next spin unlocks when the reveal (+ a short gap) is over.
--   * Spinning again skips a waiting Common/Rare result. An Epic+ result must be chosen
--     first, so a Mythic is never thrown away by mashing SPIN.
--   * Leaving with an Epic+ result waiting keeps it if there's room.
--   * The server decides which machine you're at, the luck, and the roll. Never the client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Odds = require(Shared:WaitForChild("Odds"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Abilities = require(Config:WaitForChild("Abilities"))
local Areas = require(Config:WaitForChild("Areas"))
local Economy = require(Config:WaitForChild("Economy"))

local DataService = require(script.Parent.DataService)
local RemoteGuard = require(script.Parent.RemoteGuard)
local ZoneService = require(script.Parent.ZoneService)
local AbilityService = require(script.Parent.AbilityService)
local MonetizationService = require(script.Parent.MonetizationService)
local PotionService = require(script.Parent.PotionService)
local PolicyGate = require(script.Parent.PolicyService)

type Rarity = Types.Rarity
type AbilityDef = Types.AbilityDef

type Pending = {
	AbilityId: string,
	Rarity: Rarity,
}

export type SpinResponse = {
	Ok: boolean,
	Reason: string?, -- when Ok is false: "NotLoaded", "TooSoon", "ChooseFirst", "NotAtMachine", "AreaLocked", ...
	AbilityId: string?,
	Rarity: Rarity?,
	Chance: number?, -- real chance of this exact ability on this spin (0..1)
	IsNew: boolean?, -- first time ever rolled → "NEW!" sticker
	RevealSeconds: number?,
	Luck: number?,
}

-- Small allowance so a spin sent the moment the reveal ends isn't rejected because of ping.
local LATENCY_ALLOWANCE = 0.25

local EPIC_RANK = Rarities.Defs.Epic.Rank
local LEGENDARY_RANK = Rarities.Defs.Legendary.Rank

local CHOICES: { [string]: boolean } = { Keep = true, Equip = true, Skip = true }

local SpinService = {}

local rng = Random.new()
local pendingByPlayer: { [Player]: Pending } = {}
local nextSpinAt: { [Player]: number } = {}
local announcement: RemoteEvent
local areaUnlocked: RemoteEvent

-- Total luck for this player's next spin at this area's machine.
local function luckFor(player: Player, areaBonus: number): number
	local restricted = PolicyGate.IsRandomItemsRestricted(player)
	return Odds.EffectiveLuck({
		HasLuckPass = MonetizationService.HasPass(player, "X2Luck"),
		PotionBonus = PotionService.GetLuckBonus(player),
		AreaBonus = areaBonus,
		-- Server Luck is bought with Robux by someone else: it never applies to restricted players.
		ServerLuck = PotionService.IsServerLuckActive() and not restricted,
	})
end

local function isAreaOpen(player: Player, area: Areas.AreaDef, totalSpins: number): boolean
	if area.RequiresVip then
		return MonetizationService.HasPass(player, "VIP")
	end
	return totalSpins >= area.SpinsNeeded
end

local function revealSeconds(player: Player, rarity: Rarity): number
	local def = Rarities.Defs[rarity]
	if def.Rank < LEGENDARY_RANK and MonetizationService.HasPass(player, "QuickSpin") then
		return Economy.QuickSpinRevealSeconds
	end
	return def.RevealSeconds
end

local function chanceOf(oddsTable: Odds.OddsTable, abilityId: string): number
	for _, row in Odds.AbilityChances(oddsTable) do
		if row.AbilityId == abilityId then
			return row.Chance
		end
	end
	return 0
end

local function onRequestSpin(player: Player): SpinResponse
	local data = DataService.Get(player)
	if not data then
		return { Ok = false, Reason = "NotLoaded" }
	end

	local now = os.clock()
	if now < (nextSpinAt[player] or 0) then
		return { Ok = false, Reason = "TooSoon" }
	end

	local pending = pendingByPlayer[player]
	if pending and Rarities.Defs[pending.Rarity].Rank >= EPIC_RANK then
		return { Ok = false, Reason = "ChooseFirst" }
	end

	local area = ZoneService.GetSpinMachineArea(player)
	if not area then
		return { Ok = false, Reason = "NotAtMachine" }
	end
	if not isAreaOpen(player, area, data.TotalSpins) then
		return { Ok = false, Reason = "AreaLocked" }
	end

	-- Spinning again = Skip for a waiting Common/Uncommon/Rare.
	pendingByPlayer[player] = nil

	-- Roll. The same Odds table also gives the exact chance shown on the result card.
	local luck = luckFor(player, area.LuckBonus)
	local minRarity = Odds.MinRarityFor(data.PityCounter, data.LegendaryPityCounter, data.TotalSpins)
	local oddsTable = Odds.Build(luck, minRarity, Abilities)
	local ability: AbilityDef = Odds.RollFrom(oddsTable, rng)
	local rarity = ability.Rarity

	pendingByPlayer[player] = { AbilityId = ability.Id, Rarity = rarity }

	-- Pity: each counter resets on its tier or better, otherwise counts up.
	-- Saved, so it survives rejoining.
	local rank = Rarities.Defs[rarity].Rank
	if rank >= EPIC_RANK then
		data.PityCounter = 0
	else
		data.PityCounter += 1
	end
	if rank >= LEGENDARY_RANK then
		data.LegendaryPityCounter = 0
	else
		data.LegendaryPityCounter += 1
	end

	local isNew = not data.Discovered[ability.Id]
	data.Discovered[ability.Id] = true

	-- Area unlocks: fire once when TotalSpins reaches an area's number.
	local before = data.TotalSpins
	data.TotalSpins += 1
	for _, a in Areas do
		if not a.RequiresVip and a.SpinsNeeded > before and a.SpinsNeeded <= data.TotalSpins then
			areaUnlocked:FireClient(player, a.Id)
			-- RewardService (Milestone 2) gives the unlock reward here.
		end
	end

	local reveal = revealSeconds(player, rarity)
	nextSpinAt[player] = now + reveal + Economy.SpinGapSeconds - LATENCY_ALLOWANCE

	player:SetAttribute("EffectiveLuck", luck)
	player:SetAttribute("PityCounter", data.PityCounter)
	player:SetAttribute("LegendaryPityCounter", data.LegendaryPityCounter)
	DataService.Changed(player, { "PityCounter", "LegendaryPityCounter", "TotalSpins", "Discovered" })

	local chance = chanceOf(oddsTable, ability.Id)
	if rarity == "Mythic" or rarity == "Divine" or rarity == "Secret" then
		announcement:FireAllClients({
			PlayerName = player.DisplayName,
			AbilityName = ability.Name,
			Rarity = rarity,
			Chance = chance,
		})
	end

	return {
		Ok = true,
		AbilityId = ability.Id,
		Rarity = rarity,
		Chance = chance,
		IsNew = isNew,
		RevealSeconds = reveal,
		Luck = luck,
	}
end

export type ChooseResponse = {
	Ok: boolean,
	-- when Ok is false: "NothingWaiting", "StorageFull" (ask which to replace), "NotOwned", "Locked", "Equipped", ...
	Reason: string?,
	UniqueId: string?,
}

local function onChooseResult(player: Player, choice: string, slot: number?, replaceUniqueId: string?): ChooseResponse
	local pending = pendingByPlayer[player]
	if not pending then
		return { Ok = false, Reason = "NothingWaiting" }
	end

	if choice == "Skip" then
		pendingByPlayer[player] = nil
		return { Ok = true }
	end

	-- Keep or Equip: store it first (full storage needs something to replace).
	local uniqueId, reason = AbilityService.AddToStorage(player, pending.AbilityId, replaceUniqueId)
	if not uniqueId then
		return { Ok = false, Reason = reason } -- still waiting for a choice
	end
	pendingByPlayer[player] = nil

	if choice == "Equip" then
		-- No slot given → first empty slot, else slot 1.
		local target = slot
		if not target then
			local data = DataService.Get(player)
			target = 1
			if data then
				for i = 1, AbilityService.SlotCount(player) do
					if data.Equipped[i] == false then
						target = i
						break
					end
				end
			end
		end
		local equipped, equipReason = AbilityService.Equip(player, uniqueId, target :: number)
		if not equipped then
			-- It's safely in storage; only equipping failed.
			return { Ok = false, Reason = equipReason, UniqueId = uniqueId }
		end
	end
	return { Ok = true, UniqueId = uniqueId }
end

local function validateChoice(choice: unknown, slot: unknown, replaceUniqueId: unknown): boolean
	if not RemoteGuard.IsOneOf(choice, CHOICES) then
		return false
	end
	if slot ~= nil and not RemoteGuard.IsInteger(slot, 1, Economy.MaxSlots) then
		return false
	end
	if replaceUniqueId ~= nil and not RemoteGuard.IsString(replaceUniqueId, 64) then
		return false
	end
	return true
end

function SpinService.Init()
	announcement = Remotes.Event("Announcement")
	areaUnlocked = Remotes.Event("AreaUnlocked")
end

function SpinService.Start()
	RemoteGuard.Function("RequestSpin", { PerSecond = 4, Burst = 6 }, function(...)
		return select("#", ...) == 0
	end, onRequestSpin)

	RemoteGuard.Function("ChooseResult", { PerSecond = 4, Burst = 6 }, validateChoice, onChooseResult)

	Players.PlayerRemoving:Connect(function(player)
		-- Keep a waiting Epic+ if there's room (DataService releases data after this, deferred).
		local pending = pendingByPlayer[player]
		if pending and Rarities.Defs[pending.Rarity].Rank >= EPIC_RANK then
			AbilityService.AddToStorage(player, pending.AbilityId, nil)
		end
		pendingByPlayer[player] = nil
		nextSpinAt[player] = nil
	end)
end

return SpinService

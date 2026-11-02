--!strict
-- AbilityService: storage and equip slots (vault: 03 Systems → Abilities & Equip).
-- Status: storage + equip used by SpinService. The Equip/Unequip/Delete/Lock remotes
-- come with the Inventory screen.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Economy = require(Config:WaitForChild("Economy"))

local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)

local AbilityService = {}

local function storageCount(data: DataService.PlayerData): number
	local count = 0
	for _ in data.Inventory do
		count += 1
	end
	return count
end

local function isEquipped(data: DataService.PlayerData, uniqueId: string): boolean
	for _, equipped in data.Equipped do
		if equipped == uniqueId then
			return true
		end
	end
	return false
end

-- How many equip slots the player can use: 2, or 3 after 100 KOs / with the +1 Equip Slot pass.
function AbilityService.SlotCount(player: Player): number
	local data = DataService.Get(player)
	if not data then
		return Economy.FreeSlots
	end
	if data.KOs >= Economy.ThirdSlotKOs or MonetizationService.HasPass(player, "ExtraSlot") then
		return Economy.FreeSlots + 1
	end
	return Economy.FreeSlots
end

function AbilityService.IsStorageFull(player: Player): boolean
	local data = DataService.Get(player)
	return data == nil or storageCount(data) >= data.MaxStorage
end

-- Put an ability in storage. If storage is full, replaceUniqueId must name an owned,
-- unlocked, unequipped ability to throw away. Returns the new uniqueId, or nil + reason.
function AbilityService.AddToStorage(player: Player, abilityId: string, replaceUniqueId: string?): (string?, string?)
	local data = DataService.Get(player)
	if not data then
		return nil, "NotLoaded"
	end

	if storageCount(data) >= data.MaxStorage then
		if not replaceUniqueId then
			return nil, "StorageFull"
		end
		if not data.Inventory[replaceUniqueId] then
			return nil, "NotOwned"
		end
		if data.Locked[replaceUniqueId] then
			return nil, "Locked"
		end
		if isEquipped(data, replaceUniqueId) then
			return nil, "Equipped"
		end
		data.Inventory[replaceUniqueId] = nil
	end

	local uniqueId = HttpService:GenerateGUID(false)
	data.Inventory[uniqueId] = { AbilityId = abilityId, Level = 1 }
	DataService.Changed(player, { "Inventory" })
	return uniqueId, nil
end

-- Put an owned ability in a slot. If it's already in another slot, it moves.
function AbilityService.Equip(player: Player, uniqueId: string, slot: number): (boolean, string?)
	local data = DataService.Get(player)
	if not data then
		return false, "NotLoaded"
	end
	if not data.Inventory[uniqueId] then
		return false, "NotOwned"
	end
	if slot % 1 ~= 0 or slot < 1 or slot > AbilityService.SlotCount(player) then
		return false, "BadSlot"
	end
	for i, equipped in data.Equipped do
		if equipped == uniqueId then
			data.Equipped[i] = false
		end
	end
	data.Equipped[slot] = uniqueId
	DataService.Changed(player, { "Equipped" })
	return true, nil
end

function AbilityService.Init() end

function AbilityService.Start() end

return AbilityService

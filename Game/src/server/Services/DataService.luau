--!strict
-- DataService: owns every player's data (vault: 07 Tech Plan → Player data schema).
--
-- Status: Milestone 1 version. Data lives in memory only and resets when you leave.
-- Milestone 2 swaps the inside for ProfileStore (session lock, autosave, BindToClose)
-- without changing Get / Changed, so other services don't need to change.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Economy = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))

export type OwnedAbility = {
	AbilityId: string,
	Level: number,
}

export type PlayerData = {
	Version: number,

	Yen: number,

	Inventory: { [string]: OwnedAbility }, -- [uniqueId] = ability
	Equipped: { string | false }, -- uniqueId per slot, false = empty (3 slots)
	Locked: { [string]: boolean }, -- [uniqueId] = true
	MaxStorage: number,
	Discovered: { [string]: boolean }, -- [abilityId] = true once ever rolled (Index + "NEW!")

	PityCounter: number, -- spins in a row without Epic+
	LegendaryPityCounter: number, -- spins in a row without Legendary+
	TotalSpins: number, -- also decides which areas are unlocked

	Potions: { [string]: number },
	KOs: number,
	Deaths: number,

	TutorialDone: boolean,
	RedeemedCodes: { [string]: boolean },
	ProcessedReceipts: { [string]: boolean },
}

local function defaultData(): PlayerData
	return {
		Version = 1,
		Yen = 0,
		Inventory = {},
		Equipped = { false, false, false },
		Locked = {},
		MaxStorage = Economy.MaxStorage,
		Discovered = {},
		PityCounter = 0,
		LegendaryPityCounter = 0,
		TotalSpins = 0,
		Potions = { Luck = 1 }, -- tutorial gives 1
		KOs = 0,
		Deaths = 0,
		TutorialDone = false,
		RedeemedCodes = {},
		ProcessedReceipts = {},
	}
end

local DataService = {}

local dataByPlayer: { [Player]: PlayerData } = {}
local dataUpdated: RemoteEvent

local function load(player: Player)
	-- Milestone 2: ProfileStore load with session lock goes here.
	dataByPlayer[player] = defaultData()
	DataService.Changed(player, { "Yen", "Inventory", "Equipped", "Locked", "MaxStorage", "PityCounter", "LegendaryPityCounter", "TotalSpins", "Discovered" })
end

-- The player's data, or nil if it isn't loaded (yet / any more). Always handle nil.
function DataService.Get(player: Player): PlayerData?
	return dataByPlayer[player]
end

-- Tell the player's client that some fields changed. Sends only those fields.
function DataService.Changed(player: Player, fields: { string })
	local data = dataByPlayer[player]
	if not data then
		return
	end
	local payload: { [string]: any } = {}
	local raw = data :: any
	for _, field in fields do
		payload[field] = raw[field]
	end
	dataUpdated:FireClient(player, payload)
end

function DataService.Init()
	dataUpdated = Remotes.Event("DataUpdated")
end

function DataService.Start()
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		-- Deferred so other services' PlayerRemoving handlers (e.g. SpinService
		-- keeping a waiting Epic+ result) still see the data first.
		task.defer(function()
			-- Milestone 2: final save + release the session lock here.
			dataByPlayer[player] = nil
		end)
	end)
end

return DataService

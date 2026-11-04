--!strict
-- PlayerState: the client's copy of its own player data (from DataService's DataUpdated).
-- Read-only on the client: the server owns the real data. Controllers read Get() and
-- listen to Changed(fields) to redraw.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

export type OwnedAbility = {
	AbilityId: string,
	Level: number,
}

local PlayerState = {}

local data: { [string]: any } = {}
local changed = Instance.new("BindableEvent")

PlayerState.Changed = changed.Event -- (fields: { string })

function PlayerState.Get(field: string): any
	return data[field]
end

function PlayerState.Inventory(): { [string]: OwnedAbility }
	return data.Inventory or {}
end

-- uniqueId per slot, false = empty
function PlayerState.Equipped(): { string | false }
	return data.Equipped or {}
end

-- Connected on first require, so the first DataUpdated (queued by Roblox until someone
-- listens) is never missed.
Remotes.Event("DataUpdated").OnClientEvent:Connect(function(payload: { [string]: any })
	local fields = {}
	for field, value in payload do
		data[field] = value
		table.insert(fields, field)
	end
	changed:Fire(fields)
end)

return PlayerState

--!strict
-- Every remote in the game (vault: 07 Tech Plan → Remotes).
-- The server creates them at start in ReplicatedStorage.Remotes; the client waits for them.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EVENTS = {
	-- Client → Server
	"EquipAbility",
	"UnequipAbility",
	"DeleteAbility",
	"ToggleLock",
	"SaveSettings",
	"M1Attack",
	"SetBlock",
	"Dash",
	"UseAbility",
	"BuyPotion",
	"RequestPurchase",
	"ClaimPlaytimeReward",
	-- Server → Client
	"DataUpdated",
	"HitEffect",
	"Knockback",
	"KillFeed",
	"AbilityUsed",
	"AbilityHit", -- a projectile hit something: (attacker character, abilityId, position, normal[, target Model?, server time, seed])
	"AbilityLaunch", -- a server-clock projectile left the hand: (attacker character, abilityId, origin, direction, server time, seed)
	"AbilityStrike", -- a sky strike follows a projectile's character hit: (attacker character, abilityId, target Model, ground position, server time, seed)
	"AbilityImpact", -- a melee hit landed: (attacker character, abilityId, { { Target: Model, Position: Vector3 } }, server time)
}

local FUNCTIONS = {
	"RedeemCode",
}

local FOLDER_NAME = "Remotes"

local Remotes = {}

-- Server only: create the folder and every remote. Call once at startup.
function Remotes.Create()
	assert(RunService:IsServer(), "Remotes.Create is server-only")
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for _, name in EVENTS do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	for _, name in FUNCTIONS do
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

local function folder(): Folder
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

function Remotes.Event(name: string): RemoteEvent
	return folder():WaitForChild(name) :: RemoteEvent
end

function Remotes.Function(name: string): RemoteFunction
	return folder():WaitForChild(name) :: RemoteFunction
end

return Remotes

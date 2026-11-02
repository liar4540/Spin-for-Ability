--!strict
-- RemoteGuard: every client → server remote goes through here.
-- Order (LIHFOLK: Remote Abuse Patterns and Rate Limiting in Practice):
--   1. rate limit FIRST (cheap), 2. check argument types/shape/bounds, 3. run the handler.
-- The player always comes from Roblox (the first argument), never from the payload.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

export type Limit = {
	PerSecond: number, -- tokens refilled per second
	Burst: number, -- max tokens saved up
}

type Bucket = { tokens: number, updated: number }

local RemoteGuard = {}

-- [player][remoteName] = bucket. Keys are fixed remote names, never client strings.
local buckets: { [Player]: { [string]: Bucket } } = {}
local violations: { [Player]: number } = {}

local function allow(player: Player, name: string, limit: Limit): boolean
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local now = os.clock()
	local bucket = perPlayer[name]
	if not bucket then
		bucket = { tokens = limit.Burst, updated = now }
		perPlayer[name] = bucket
	end
	bucket.tokens = math.min(limit.Burst, bucket.tokens + (now - bucket.updated) * limit.PerSecond)
	bucket.updated = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

-- Count bad calls instead of kicking on the first one (laggy players resend).
-- No warn() per call, so a flood can't spam the logs.
local function strike(player: Player)
	local count = (violations[player] or 0) + 1
	violations[player] = count
	if count == 50 then
		warn(`[RemoteGuard] {player.Name} ({player.UserId}) sent 50 rejected remote calls`)
	end
end

-- ===== Argument checks =====

function RemoteGuard.IsFiniteNumber(x: unknown): boolean
	-- x == x is false for NaN, which would otherwise pass every range check.
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

function RemoteGuard.IsInteger(x: unknown, min: number, max: number): boolean
	if not RemoteGuard.IsFiniteNumber(x) then
		return false
	end
	local n = x :: number
	return n % 1 == 0 and n >= min and n <= max
end

function RemoteGuard.IsString(x: unknown, maxLength: number): boolean
	return type(x) == "string" and #x <= maxLength and utf8.len(x) ~= nil
end

function RemoteGuard.IsOneOf(x: unknown, allowed: { [string]: boolean }): boolean
	return type(x) == "string" and allowed[x] == true
end

-- ===== Wiring =====

-- RemoteEvent: validate(...) returns true if the arguments are OK.
function RemoteGuard.Event(name: string, limit: Limit, validate: (...any) -> boolean, handler: (Player, ...any) -> ())
	Remotes.Event(name).OnServerEvent:Connect(function(player: Player, ...)
		if not allow(player, name, limit) then
			strike(player)
			return
		end
		if not validate(...) then
			strike(player)
			return
		end
		handler(player, ...)
	end)
end

-- RemoteFunction: rejected calls get { Ok = false, Reason = ... } back.
function RemoteGuard.Function(name: string, limit: Limit, validate: (...any) -> boolean, handler: (Player, ...any) -> any)
	Remotes.Function(name).OnServerInvoke = function(player: Player, ...)
		if not allow(player, name, limit) then
			strike(player)
			return { Ok = false, Reason = "TooFast" }
		end
		if not validate(...) then
			strike(player)
			return { Ok = false, Reason = "BadRequest" }
		end
		return handler(player, ...)
	end
end

function RemoteGuard.Init() end

function RemoteGuard.Start()
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
		violations[player] = nil
	end)
end

return RemoteGuard

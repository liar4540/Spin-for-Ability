--!strict
-- PolicyService (ours): the ONLY code that asks Roblox's PolicyService about a player.
-- Fails closed: if we don't know, the player is treated as restricted.
-- Status: Milestone 1 placeholder. Always "restricted" until Milestone 2 adds the real
-- GetPolicyInfoForPlayerAsync lookup with retries (LIHFOLK: Regional Compliance).

local PolicyGate = {}

-- True if paid random items (paid luck) must be blocked for this player.
function PolicyGate.IsRandomItemsRestricted(_player: Player): boolean
	return true -- fail closed
end

function PolicyGate.Init() end

function PolicyGate.Start() end

return PolicyGate

--!strict
-- MonetizationService: game pass cache + the ONLY ProcessReceipt in the game.
-- Status: Milestone 1 placeholder. HasPass always says false until Milestone 2 fills
-- the cache with UserOwnsGamePassAsync on join (retrying errors, never caching "false" from an error).

local MonetizationService = {}

-- Does the player own this pass? Key is from Config/Products Passes (e.g. "X2Luck", "QuickSpin", "VIP").
function MonetizationService.HasPass(_player: Player, _key: string): boolean
	return false
end

function MonetizationService.Init() end

function MonetizationService.Start() end

return MonetizationService

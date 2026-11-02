--!strict
-- PotionService: luck potion timers (one runs at a time, weaker ones pause) + Server Luck later.
-- Status: Milestone 1 placeholder. No potions run yet, so the bonus is always 0.

local PotionService = {}

-- Luck the player's running potion adds (+1 Luck, +2 Super Luck), 0 if none.
function PotionService.GetLuckBonus(_player: Player): number
	return 0
end

-- Has someone bought Server Luck in this server and is it still running?
function PotionService.IsServerLuckActive(): boolean
	return false
end

function PotionService.Init() end

function PotionService.Start() end

return PotionService

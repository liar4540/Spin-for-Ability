--!strict
-- Prices and rewards (vault: 03 Systems → Economy). Starting numbers: tune after playtests.

local Economy = {
	-- Yen
	KOYen = 25,
	LuckPotionYenPrice = 100,

	-- Potions
	LuckPotionBonus = 1, -- +1x luck
	SuperLuckPotionBonus = 2, -- +2x luck (Later)
	PotionSeconds = 5 * 60,

	-- Spinning (free and unlimited)
	SpinGapSeconds = 1, -- wait after a reveal ends before the next spin
	QuickSpinRevealSeconds = 0.5, -- Quick Spin pass: reveals below Legendary
	MaxStorage = 15,

	-- Equip slots
	FreeSlots = 2,
	ThirdSlotKOs = 100,
}

return Economy

--!strict
-- Game pass and developer product IDs (vault: 04 Monetization).
-- Fill in the real IDs from the Creator Dashboard. 0 = not created yet.
-- Prices are NOT stored here: the UI loads them with MarketplaceService:GetProductInfoAsync.
-- BuysLuck = true means it's blocked for players where paid random items are restricted.

export type PassDef = { Id: number, BuysLuck: boolean }
export type ProductDef = { Id: number, BuysLuck: boolean }

local Products = {
	Passes = {
		X2Luck = { Id = 0, BuysLuck = true },
		QuickSpin = { Id = 0, BuysLuck = false },
		AutoSpin = { Id = 0, BuysLuck = false }, -- Later
		ExtraSlot = { Id = 0, BuysLuck = false },
		ExtraStorage = { Id = 0, BuysLuck = false }, -- Later
		VIP = { Id = 0, BuysLuck = true }, -- VIP Area adds luck
		X2Yen = { Id = 0, BuysLuck = true }, -- yen buys potions; Later
	} :: { [string]: PassDef },

	DevProducts = {
		LuckPotion = { Id = 0, BuysLuck = true },
		LuckPotion5 = { Id = 0, BuysLuck = true },
		SuperLuckPotion = { Id = 0, BuysLuck = true }, -- Later
		Yen1000 = { Id = 0, BuysLuck = true },
		ServerLuck = { Id = 0, BuysLuck = true }, -- Later
	} :: { [string]: ProductDef },
}

return Products

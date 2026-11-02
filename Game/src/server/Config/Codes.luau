--!strict
-- Redeem codes. Kept on the SERVER on purpose: anything in ReplicatedStorage
-- can be read by exploiters, so unreleased codes would leak.

export type CodeReward = {
	LuckPotions: number?,
	Yen: number?,
	ExpiresAt: number?, -- os.time(); nil = never
}

local Codes: { [string]: CodeReward } = {
	-- RELEASE = { LuckPotions = 2 },
}

return Codes

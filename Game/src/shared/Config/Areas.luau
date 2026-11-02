--!strict
-- Areas and their spin machines (vault: 05 World & Art).
-- LuckBonus is ADDED to the player's luck while they spin at that area's machine.

export type AreaDef = {
	Id: string,
	Name: string,
	SpinsNeeded: number, -- total spins to unlock (0 = free)
	LuckBonus: number,
	RequiresVip: boolean,
}

local Areas: { AreaDef } = {
	{ Id = "Starter", Name = "Training Grounds", SpinsNeeded = 0, LuckBonus = 0, RequiresVip = false },
	{ Id = "Area1", Name = "Area 1", SpinsNeeded = 1000, LuckBonus = 0.1, RequiresVip = false },
	{ Id = "Area2", Name = "Area 2", SpinsNeeded = 5000, LuckBonus = 0.2, RequiresVip = false },
	{ Id = "Area3", Name = "Area 3", SpinsNeeded = 15000, LuckBonus = 0.3, RequiresVip = false },
	{ Id = "Area4", Name = "Area 4", SpinsNeeded = 50000, LuckBonus = 0.4, RequiresVip = false },
	{ Id = "VIP", Name = "VIP Area", SpinsNeeded = 0, LuckBonus = 0.5, RequiresVip = true },
}

return Areas

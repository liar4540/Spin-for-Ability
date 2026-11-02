--!strict
-- Base battlegrounds moveset that every player has (vault: 03 Systems → Combat / Battlegrounds).
-- Placeholder numbers: tune them in playtests, with simulated lag.

local Combat = {
	M1 = {
		ChainLength = 4,
		Damage = { 4, 4, 4, 6 }, -- the 4th hit knocks back
		SwingSeconds = 0.35, -- min time between chain hits (checked on the server clock)
		ChainResetSeconds = 1.0,
		EndLagSeconds = 0.6, -- pause after a full chain
		Range = 6,
	},
	Block = {
		DamageTaken = 0.25, -- take 25% damage while blocking
		BreakHits = 4, -- hits before a guard break
		GuardBreakStunSeconds = 1.5,
	},
	Dash = {
		Distance = 16,
		CooldownSeconds = 2,
	},
	Hitstun = {
		FirstHitSeconds = 0.5,
		DecayPerHit = 0.85, -- each hit in a combo stuns a bit less
		MaxComboSeconds = 3.5,
		GetUpInvulnSeconds = 0.75,
	},
	Ragdoll = {
		Seconds = 1.5,
	},
	Respawn = {
		Seconds = 3,
		ShieldSeconds = 2,
	},
	KOCreditSeconds = 5, -- last damage within this window gets the KO
	MaxRewindSeconds = 0.25, -- lag compensation cap
}

return Combat

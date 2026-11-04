--!strict
-- Base battlegrounds moveset that every player has.
-- Numbers match "Spin for Abilities – Core Combat (M1, Block, Dash).pdf" and the vault note "12 Combat System".
-- Starting values only: tune them in playtests with simulated lag (150–250 ms).

local Combat = {
	M1 = {
		ChainLength = 4,
		Damage = { 3, 3, 3, 5 }, -- hit 4 is the finisher
		Hitstun = 0.45, -- must stay longer than MinInterval, or the target can hit back mid-string
		MinInterval = 0.3, -- server rate limit (anti autoclicker)
		ChainResetSeconds = 0.55, -- no M1 for this long → back to hit 1
		EndLagSeconds = 1.5, -- after hit 4: no M1, but dash + abilities allowed (combo extension)
		WhiffRecovery = 0.2,
		ForwardStep = 2, -- studs, hits 1–3
		StunnedWalkSpeed = 4,
		Hitbox = { Size = Vector3.new(5, 5, 5), Offset = 3.5, HitFrame = 0.12 },
	},

	-- Hit 4 variants. Chosen by the key held when hit 4 lands.
	Finishers = {
		Knockback = { Input = "None", Damage = 5, Ragdoll = 1.2, Launch = Vector3.new(0, 10, -60), CanRagdollCancel = true },
		Uppercut = { Input = "Space", Damage = 4, Ragdoll = 0, Launch = Vector3.new(0, 55, 0), CanRagdollCancel = false },
		GroundSmash = { Input = "S", Damage = 5, Ragdoll = 1.0, Launch = Vector3.new(0, -40, 0), CanRagdollCancel = false },
	},

	Air = {
		Hits = 3, -- 3rd is the Downslam
		Damage = { 3, 3, 6 },
		GravityScale = 0.2,
		IdleFallSeconds = 0.55,
		DownslamKnockdown = 1.0,
		UppercutLockoutSeconds = 4,
	},

	-- Abilities used to continue a combo.
	ComboExtension = {
		ScalingStartsAfterHit = 8,
		ScalingPerHit = 0.1,
		ScalingMin = 0.5,
		OncePerCombo = true, -- each ability only once per combo
		ComboDropSeconds = 1.6, -- no hit on the target for this long → combo over
	},

	Block = {
		DamageTaken = 0.3,
		FrontConeDegrees = 120,
		WalkSpeed = 8,
		GuardPoints = 6, -- M1 = 1, skill = 2, heavy = 3
		RegenPerSecond = 1,
		RegenDelay = 1.5,
		GuardBreakStunSeconds = 1.5,
		BlockDisabledAfterBreak = 3,
		Startup = 0.1,
	},

	Dash = {
		Front = { Distance = 30, Duration = 0.35, IFrames = 0, Cooldown = 2.5 },
		Side = { Distance = 14, Duration = 0.25, IFrames = 0.2, Cooldown = 2.0 },
		Back = { Distance = 16, Duration = 0.3, IFrames = 0.1, Cooldown = 2.0 }, -- shares Side cooldown
		WallComboWindow = 0.6,
		WallComboBonus = 0.12,
	},

	RagdollCancel = {
		EarliestSeconds = 0.25,
		IFrames = 0.4,
		Cooldown = 20,
		BackDashStuds = 10,
	},

	StunImmunityAfterRagdoll = 0.6,
	NormalWalkSpeed = 16,

	Respawn = {
		Seconds = 3,
		ShieldSeconds = 2,
	},
	KOCreditSeconds = 5, -- last damage within this window gets the KO
	MaxRewindSeconds = 0.25, -- lag compensation cap

	DebugStateLabels = true, -- shows each fighter's state over their head (Studio only)
}

return Combat

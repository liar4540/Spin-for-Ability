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
		-- After a string is dropped before hit 4 (M1, pause, M1…), hit 1 can only start again this long
		-- after the last swing. Hitstun is 0.45 s, so the target always gets ≥ 0.55 s to act: no stun-lock.
		RestartDelay = 1.0,
		EndLagSeconds = 1.5, -- after hit 4: no M1, but dash + abilities allowed (combo extension)
		WhiffRecovery = 0.2,
		ForwardStep = 2, -- studs, hits 1–3 (the attacker's own client steps, eased, at the swing)
		ForwardStepSeconds = 0.2,
		StunnedWalkSpeed = 4,
		-- Box in front of the attacker: Size = (width, height, depth), reach = Offset + depth / 2
		-- (+1.5 lag margin). Was 5 wide / 6 reach; now 6 wide / 7 reach so close fights connect.
		Hitbox = { Size = Vector3.new(6, 7, 6), Offset = 4, HitFrame = 0.12 },
	},

	-- Client animation feel (CombatController).
	Animation = {
		FadeIn = 0.06, -- crossfade from the previous punch / idle into the next punch
		BlendOut = 0.12, -- the last part of a punch blends back into idle instead of snapping
		-- Uploaded animation ids ("rbxassetid://...") per move in client/Animations/CombatKeyframes.
		-- Empty = Studio plays the keyframes directly; the live game needs the uploaded ids.
		Ids = {
			M1_1 = "",
			M1_2 = "",
			M1_3 = "",
			M1_4 = "",
			Uppercut = "",
			Downslam = "",
			-- hit reactions (played on whoever gets hit, by ReactionController)
			Stunned = "",
			Flinch = "",
			Launched = "",
			KnockedDown = "",
		},
		ReactionFadeIn = 0.08,
		ReactionFadeOut = 0.3, -- KnockedDown → idle over this long = getting up
	},

	-- Hit 4 variants:
	--   in the air (jumped) → Downslam · S held → Ground Smash · otherwise → Knockback.
	-- Launch is relative to the attacker's facing (-Z = forward, +Y = up).
	Finishers = {
		Knockback = { Input = "None", Damage = 5, Ragdoll = 1.2, Launch = Vector3.new(0, 10, -60), CanRagdollCancel = true },
		GroundSmash = { Input = "S", Damage = 5, Ragdoll = 1.0, Launch = Vector3.new(0, -40, 0), CanRagdollCancel = false },
		-- M1 ×3, jump, M1 in the air: hammer the target into the ground; it lies down (KnockedDown).
		Downslam = { Input = "Air", Damage = 6, Ragdoll = 1.0, Launch = Vector3.new(0, -60, 0), CanRagdollCancel = false },
	},

	-- Downslam details (hit 4 thrown in the air).
	Downslam = {
		HitFrame = 0.25, -- = CombatKeyframes.Downslam.HitTime
		-- Box in front of the attacker, shifted down: the target is usually standing below a jumping
		-- attacker. Covers from (Down + Height/2) below the attacker's root to (Height/2 - Down) above.
		Hitbox = { Size = Vector3.new(7, 12, 6), Offset = 4, Down = 3 },
		MinHeight = 1, -- server check: attacker's root must be this many studs above normal standing height
		HangSeconds = 0.25, -- attacker hangs in the air during the wind-up (client, until the hit)
		HangFallSpeed = 2,
		DropVelocity = 60, -- attacker drops to the ground after the hit (studs/s, for DropSeconds)
		DropSeconds = 0.2,
		EndLag = 0.6, -- attacker: no M1 after the slam (dash + abilities still allowed)
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
	HangFallSpeed = 4, -- studs/s fall while a hit keeps someone hanging in the air (Hit.hang, for abilities)
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

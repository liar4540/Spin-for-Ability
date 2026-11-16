--!strict
-- Base battlegrounds moveset that every player has.
-- Numbers match "Spin for Abilities – Core Combat (M1, Block, Dash).pdf" and the vault note "12 Combat System"
-- (the note wins where they disagree: no Uppercut, finishers picked by input on hit 4).
-- Starting values only: tune them in playtests with simulated lag (100 / 250 ms).
--
-- Timing words used below:
--   Startup  = from the swing starting to the hit frame (the punch can still be cancelled / interrupted)
--   Active   = how long after the hit frame the server keeps looking for a target (moving targets)
--   Length   = whole move; after it the attacker is free again (Recovery = Length - Startup)

local Combat = {
	M1 = {
		ChainLength = 4,
		Damage = { 3, 3, 3, 5 }, -- hit 4 is the finisher (its real damage is in Finishers)
		Hitstun = 0.45, -- must stay longer than MinInterval, or the target can hit back mid-string
		MinInterval = 0.3, -- time between swings (anti autoclicker)
		ChainResetSeconds = 0.55, -- no M1 for this long → back to hit 1
		-- After hit 3 you get longer for hit 4, so there's time to jump for the Downslam.
		-- (The target's hitstun still ends after 0.45 s, so waiting gives them a chance to escape.)
		FinisherWindow = 0.9,
		-- Network jitter: clicks sent exactly MinInterval apart can arrive a bit closer together, and
		-- late ones a bit later. The server allows this much slack on both, so it never disagrees with
		-- the client about which hit of the string you're on.
		ServerTolerance = 0.1,
		-- A click this early (before the next swing is allowed) is kept and thrown as soon as it's
		-- allowed, instead of being ignored. Only ONE click is ever kept, so spam never queues swings.
		InputBuffer = 0.2,
		-- After a string is dropped before hit 4 (M1, pause, M1…), hit 1 can only start again this long
		-- after the last swing. Hitstun is 0.45 s, so the target always gets ≥ 0.55 s to act: no stun-lock.
		RestartDelay = 1.0,
		EndLagSeconds = 1.5, -- after hit 4 (from the swing): no M1, but dash + abilities allowed (combo extension)
		-- A whiffed M1 still advances the string, but the next swing comes this much later (punishable).
		WhiffRecovery = 0.2,
		ForwardStep = 2, -- studs, hits 1–3 (the attacker's own client steps, eased, at the swing)
		ForwardStepSeconds = 0.2,
		StunnedWalkSpeed = 4,
		-- The punch goes where the camera looks, but never more than this far from where the body faces
		-- (server check; stops "punch behind me" exploits). The client turns the body to the aim.
		MaxAimAngle = 100,
		-- Box in front of the attacker: Size = (width, height, depth), reach = Offset + depth / 2
		-- (+1.5 lag margin). 6 wide / 7 reach so close fights connect.
		Hitbox = { Size = Vector3.new(6, 7, 6), Offset = 4 },
		-- Per move timing. Startup = the animation's hit frame (CombatKeyframes HitTime), Length = its length.
		Moves = {
			M1_1 = { Startup = 0.12, Active = 0.06, Length = 0.3 },
			M1_2 = { Startup = 0.12, Active = 0.06, Length = 0.3 },
			M1_3 = { Startup = 0.12, Active = 0.06, Length = 0.3 },
			M1_4 = { Startup = 0.2, Active = 0.06, Length = 0.45 }, -- Knockback + Ground Smash
			Downslam = { Startup = 0.25, Active = 0.08, Length = 0.45 },
		},
	},

	-- Client animation feel (CombatController).
	Animation = {
		FadeIn = 0.06, -- crossfade from the previous punch / idle into the next punch
		BlendOut = 0.12, -- the last part of a punch blends back into idle instead of snapping
		CancelFade = 0.08, -- a swing the server rejected / that got interrupted fades out this fast
		-- Uploaded animation ids ("rbxassetid://...") per move in client/Animations/CombatKeyframes.
		-- Empty = Studio plays the keyframes directly; the live game needs the uploaded ids.
		Ids = {
			M1_1 = "",
			M1_2 = "",
			M1_3 = "",
			M1_4 = "",
			Uppercut = "", -- removed move (2026-11-08); keyframes kept in case it comes back
			Downslam = "",
			Block = "",
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
	--   in the air (jumped) → Downslam · S held on the ground → Ground Smash · otherwise → Knockback.
	-- Launch is relative to the attacker's facing (-Z = forward, +Y = up). With the physics ragdoll it is
	-- a one-shot velocity given to every body part (the body then flies / slides on its own).
	-- Knockback: 30 up keeps it in the air ~0.3 s, so 50 forward ≈ 15 studs + a short slide ≈ 18 (PDF).
	Finishers = {
		Knockback = { Input = "None", Damage = 5, Ragdoll = 1.2, Launch = Vector3.new(0, 30, -50), CanRagdollCancel = true },
		GroundSmash = { Input = "S", Damage = 5, Ragdoll = 1.0, Launch = Vector3.new(0, -40, 0), CanRagdollCancel = false },
		-- M1 ×3, jump, M1 in the air: hammer the target into the ground; it lies down. Goes through block (PDF).
		Downslam = {
			Input = "Air",
			Damage = 6,
			Ragdoll = 1.0,
			Launch = Vector3.new(0, -60, 0),
			CanRagdollCancel = false,
			GuardBreak = true,
		},
	},

	-- Downslam details (hit 4 thrown in the air).
	Downslam = {
		-- Box in front of the attacker, shifted down: the target is usually standing below a jumping
		-- attacker. Covers from (Down + Height/2) below the attacker's root to (Height/2 - Down) above.
		Hitbox = { Size = Vector3.new(7, 12, 6), Offset = 4, Down = 3 },
		MinHeight = 1, -- server check: attacker's root must be this many studs above normal standing height
		HangSeconds = 0.4, -- attacker hangs in the air through the wind-up (a bit past the hit, for lag)
		HangFallSpeed = 2,
		DropVelocity = 60, -- attacker drops to the ground after the hit (studs/s, for DropSeconds)
		DropSeconds = 0.2,
	},

	-- Real R15 physics ragdoll (RagdollService). Motor6Ds are swapped for BallSocketConstraints that are
	-- built once per character and only switched on/off. Limits in degrees.
	Ragdoll = {
		UsePhysics = true, -- false = old animation-only knockdown (KnockedDown loop), for debugging
		Limits = {
			-- joint name = { cone (UpperAngle), twist lower, twist upper }
			Neck = { 30, -40, 40 },
			Waist = { 20, -20, 20 },
			RightShoulder = { 80, -60, 60 },
			LeftShoulder = { 80, -60, 60 },
			RightElbow = { 70, -5, 5 },
			LeftElbow = { 70, -5, 5 },
			RightWrist = { 25, -10, 10 },
			LeftWrist = { 25, -10, 10 },
			RightHip = { 50, -20, 20 },
			LeftHip = { 50, -20, 20 },
			RightKnee = { 70, -5, 5 },
			LeftKnee = { 70, -5, 5 },
			RightAnkle = { 20, -5, 5 },
			LeftAnkle = { 20, -5, 5 },
		},
		DefaultLimit = { 30, -15, 15 }, -- any other Motor6D (custom rigs, accessories with joints)
		MaxImpulse = 120, -- studs/s cap on any velocity given to a ragdoll (no flinging)
		-- Standing up: the body is put upright at the ground under it. If that spot is inside a wall it
		-- goes back towards where the ragdoll started, this many tries.
		StandUpTries = 4,
	},

	-- Abilities used to continue a combo, and the rules that stop infinite combos.
	ComboExtension = {
		ScalingStartsAfterHit = 8,
		ScalingPerHit = 0.1, -- −10 percentage points per hit after hit 8
		ScalingMin = 0.5,
		OncePerCombo = true, -- each ability only once per attacker → target combo (all hits of ONE cast count)
		ComboDropSeconds = 1.6, -- no valid hit on the target for this long → combo over
		-- Hard cap on being controlled (stunned / ragdolled / guard broken) without a break, so no combo is
		-- infinite, even with several attackers taking turns. Past the cap, hits still deal damage but
		-- can't stun or ragdoll, and the target gets ControlBreakImmunity of stun immunity once free.
		MaxControlSeconds = 5,
		ControlBreakImmunity = 1.0,
		-- Being free (not controlled) for this long resets the control clock.
		ControlResetSeconds = 0.6,
	},

	-- Defaults for abilities, used when an ability's config leaves a field out (Config/Abilities).
	AbilityDefaults = {
		Stun = 0.6, -- OnHit = "Stun": seconds of hitstun (longer than M1 hitstun so the string can restart)
		Ragdoll = 1.0, -- OnHit = "Ragdoll"
		LaunchUp = 45, -- OnHit = "Launch": upward speed
		LaunchHang = 0.6,
		PullSpeed = 40, -- OnHit = "Pull": towards the attacker
		Recovery = 0.25, -- after the hit frame the caster is still busy this long (no overlapping moves)
		GuardDamage = 2, -- blocked skill = 2 guard points (PDF)
	},

	Block = {
		DamageTaken = 0.3,
		FrontConeDegrees = 120, -- total cone in front that block covers; from behind = full hit
		WalkSpeed = 8,
		GuardPoints = 6, -- M1 = 1, skill = 2, heavy = 3
		M1GuardDamage = 1,
		FinisherGuardDamage = 2, -- a blocked Knockback / Ground Smash (PDF: heavy-ish)
		RegenPerSecond = 1,
		RegenDelay = 1.5, -- after the last blocked hit
		GuardBreakStunSeconds = 1.5,
		BlockDisabledAfterBreak = 3,
		Startup = 0.1, -- block must be held this long before it stops anything (no panic blocks)
		BlockedPushback = 6, -- studs/s nudge back on a blocked hit (feedback, not a combo tool)
	},

	-- Dashes are moved by the dashing player's own client; the server checks the distance.
	-- IFrames come from the PDF (side 0.2, back 0.1, front none).
	Dash = {
		Front = { Distance = 30, Duration = 0.35, IFrames = 0, Cooldown = 2.5, Group = "Front" },
		Side = { Distance = 14, Duration = 0.25, IFrames = 0.2, Cooldown = 2.0, Group = "SideBack" },
		Back = { Distance = 16, Duration = 0.3, IFrames = 0.1, Cooldown = 2.0, Group = "SideBack" },
		WallStop = 2, -- the client stops this far in front of a wall
		DistanceSlack = 3, -- extra studs the server allows (lag, slopes)
		ServerTolerance = 0.15, -- cooldown slack for jitter
		-- A front dash can be cancelled into a side dash (uses the side cooldown).
		FrontToSideCancel = true,
		-- Dash during an M1's startup cancels that M1 (it never lands). Dash after a hit is free.
		CancelsM1Startup = true,
	},

	RagdollCancel = {
		EarliestSeconds = 0.25,
		IFrames = 0.4,
		Cooldown = 20,
		BackDashStuds = 10,
		BackDashSeconds = 0.2,
	},

	StunImmunityAfterRagdoll = 0.6, -- stun immunity, NOT damage invulnerability
	HangFallSpeed = 4, -- studs/s fall while a hit keeps someone hanging in the air (Hit.hang, for abilities)
	NormalWalkSpeed = 16,

	Respawn = {
		Seconds = 3,
		ShieldSeconds = 2, -- spawn protection (damage + control); ends early if you attack
	},
	KOCreditSeconds = 5, -- last damage within this window gets the KO
	MaxRewindSeconds = 0.25, -- lag compensation cap (no rewind system yet: hitboxes use a lag margin)

	DebugStateLabels = true, -- shows each fighter's state over their head (Studio only)
}

return Combat

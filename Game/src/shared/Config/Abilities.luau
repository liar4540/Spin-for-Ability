--!strict
-- Every ability's stats. Starter set from the vault's Ideas Inbox (original names).
-- Placeholder set until ability design: Ascended and Divine have none yet, so the
-- odds screen leaves them out and their chance is shared by the other tiers.
-- Damage here is BASE damage; the rarity's Power (x1.35 per tier) and level are applied on top.
-- Numbers are placeholders: tune them in playtests.

local Types = require(script.Parent.Parent.Types)
local Assets = require(script.Parent.Assets)

type AbilityDef = Types.AbilityDef

local Abilities: { AbilityDef } = {
	{
		Id = "EmberFist",
		Name = "Ember Fist",
		Rarity = "Common",
		Type = "Melee",
		Damage = 12,
		Cooldown = 5,
		Range = 6,
		WindupSeconds = 0.27,
		HitboxWidth = 5,
		Knockback = 22, -- "small knockback" (vault): about 4 studs on a dummy
		AnimationId = nil, -- uploaded animation id; nil plays the Studio test animation (client/Abilities/Pose)
		Icon = Assets.Icons.EmberFist,
		-- Combat metadata: the first real example of the ability ↔ combat contract.
		-- After any finisher the target lies in a ragdoll; Ember Fist's stun stands it back up stunned,
		-- so the M1 string can start again once the finisher's end lag (1.5 s) is over. After a Knockback
		-- you have to dash in first (and the target can ragdoll-cancel). Once per combo per target.
		Followup = { "Knockback", "GroundSmash", "Downslam" },
		AirUsable = false,
		OnHit = "Stun",
		-- Long enough to bridge into the next M1 string when cast ~0.4 s after a finisher (the finisher's
		-- 1.5 s M1 lock must run out while the target is still stunned). Tune in playtests.
		Stun = 0.8,
		GuardBreak = false,
		RecoverySeconds = 0.25,
		Description = "A fiery punch with a small knockback.",
	},
	{
		Id = "PebbleToss",
		Name = "Pebble Toss",
		Rarity = "Common",
		Type = "Projectile",
		Damage = 8,
		Cooldown = 4,
		Range = 60, -- about 1.1 s of flight; shatters at the end if it hits nothing
		WindupSeconds = 0.4, -- the animation's "Release" marker (frame 12 @ 30 fps)
		ProjectileSpeed = 55,
		ProjectileRadius = 0.6, -- the rock (1.2 across): what stops it at walls and the ground
		HitboxRadius = 2.5, -- the sphere that finds characters; much bigger than the rock, so near misses hit
		Knockback = 8,
		AirUsable = true, -- kept usable in the air like before the combat rules existed (ability team: decide)
		OnHit = "None",
		AnimationId = nil, -- uploaded animation id; nil plays the Studio test animation (client/Abilities/Pose)
		Description = "Throws a quick rock that shatters into chips on hit.",
	},
	{
		Id = "GaleStep",
		Name = "Gale Step",
		Rarity = "Uncommon",
		Type = "Movement",
		Damage = 0,
		Cooldown = 4, -- the server checks this one (client/Abilities/GaleStepVFX CONFIG.COOLDOWN reads it)
		Range = 30, -- studs dashed, toward where the camera faces; stops 2 studs short of walls
		WindupSeconds = 0.2, -- the animation's "DashStart" marker (frame 6 @ 30 fps)
		MaxDashStuds = 32, -- the server pulls a player back if one dash moves them further than this
		DashWindowSeconds = 1, -- how long after the key press the server watches the dash
		AirUsable = true, -- kept usable in the air like before the combat rules existed (ability team: decide)
		AnimationId = "rbxassetid://130755455737261", -- GaleStep_Dash (Game/assets/gale_step.blend)
		Description = "An extremely fast dash with wind trails.",
	},
	{
		-- Numbers from Prompts/frost_jab_prompt.md; client/Abilities/FrostJabVFX CONFIG reads them.
		Id = "FrostJab",
		Name = "Frost Jab",
		Rarity = "Uncommon",
		Type = "Melee",
		Damage = 8 / 1.35, -- the hit deals exactly 8 after Uncommon's Power (x1.35)
		Cooldown = 3,
		Range = 6, -- box length in front of the HumanoidRootPart (HitboxService adds its 1.5-stud lag margin)
		WindupSeconds = 4 / 30, -- the animation's "Hit" marker: frame 4, where the fist is furthest out
		HitboxWidth = 5,
		HitboxHeight = 5,
		SlowMultiplier = 0.6, -- WalkSpeed x 0.6...
		SlowSeconds = 1.5, -- ...for 1.5 s; a new hit refreshes it
		MinRequestSeconds = 0.25, -- at most 1 request per 0.25 s
		DurationSeconds = 0.45,
		AnimationId = "rbxassetid://78544021138400", -- FrostJab_Punch (Game/assets/frost_jab.blend)
		Description = "An icy punch that slows briefly.",
	},
	{
		-- Numbers from Prompts/thunder_lance_prompt; client/Abilities/ThunderLanceVFX CONFIG reads them.
		Id = "ThunderLance",
		Name = "Thunder Lance",
		Rarity = "Rare",
		Type = "Projectile",
		Damage = 18 / 1.35 ^ 2, -- the hit deals exactly 18 after Rare's Power (x1.35 per tier above Common)
		Cooldown = 6,
		Range = 120, -- studs of flight; at the end it fades out with no impact
		WindupSeconds = 15 / 30, -- the animation's "Release" marker: frame 15, the hand's fastest frame
		ProjectileSpeed = 160,
		ProjectileRadius = 0.175, -- the spear (0.35 thick): what stops it at walls and the ground
		HitboxRadius = 2.5, -- finds characters; deliberately much bigger than the spear (Pebble Toss lesson)
		ThrowOffset = Vector3.new(0.85, 1.33, 2.97), -- the hand on the Release frame (thunder_lance.blend F15)
		ProjectileLead = 4, -- the spear's tip is 4 studs ahead of the grip; the flight tracks the tip
		ServerClock = true, -- flown on the server clock and announced with AbilityLaunch (AbilityService)
		MinRequestSeconds = 0.25, -- at most 1 request per 0.25 s
		SkyStrike = true, -- stage 7B: a character hit calls a lightning strike down onto the target (AbilityStrike)
		StrikeDamage = 0, -- balance number: the strike is visual only for now (dealt 0.15 s after the hit)
		AnimationId = "rbxassetid://71580696171096", -- ThunderLance_Throw (Game/assets/thunder_lance.blend); markers Summon F4, Release F15
		Description = "A fast lightning spear that flies in a straight line.",
	},
	{
		-- Numbers from the Frost Bloom prompt (2026-11-24); client/Abilities/FrostBloomVFX CONFIG reads them.
		-- Timeline: rune gathers 0-0.6 s (wind-up), flower opens 0.6-1.0 s, the hit lands at full bloom.
		Id = "FrostBloom",
		Name = "Frost Bloom",
		Rarity = "Epic",
		Type = "AoE",
		Damage = 20 / 1.35 ^ 3, -- the bloom deals exactly 20 after Epic's Power (x1.35 per tier above Common)
		Cooldown = 14,
		Range = 18, -- radius in studs: a flat circle centred on the caster's feet (HitboxService.InCircle)
		WindupSeconds = 1.0, -- key press -> full bloom (0.6 s rune wind-up + 0.4 s petals opening)
		RecoverySeconds = 0.2,
		AoeMaxTargets = 8,
		OnHit = "None", -- not a stun: targets can still move and attack, only slower
		SlowMultiplier = 0.6, -- Frozen Chill: WalkSpeed -40%...
		SlowJumpMultiplier = 0.7, -- ...jump -30%...
		SlowSeconds = 3, -- ...for 3 s; a new hit refreshes it, never stacks
		AirUsable = false,
		MinRequestSeconds = 0.25,
		AnimationId = "rbxassetid://103663794525019", -- generated in Studio (Studio MCP generate_animation), 1.57 s
		Description = "A crystal ice flower blooms around you, chilling everyone nearby.",
	},
	{
		-- From the Shadow Swap prompt (2026-11-26), changed with the user: no damage and no slow (the
		-- auto-lock + landing behind the target is strong enough), cooldown 15 s instead of 16.
		-- A combo opener: a better Gale Step that finds the enemy. client/Abilities/ShadowSwapVFX reads it.
		-- Timeline: shadows gather 0-0.15 s (wind-up), vanish at 0.15 s, reappear behind the target ~0.27 s.
		Id = "ShadowSwap",
		Name = "Shadow Swap",
		Rarity = "Epic",
		Type = "Movement",
		Damage = 0,
		Cooldown = 15,
		Range = 35, -- lock-on radius: the nearest enemy within this (no enemy = not cast, cooldown refunded)
		Teleport = true,
		BehindStuds = 3, -- lands this far behind the target, facing it
		WindupSeconds = 0.15, -- crouch + shadows gather, then the caster vanishes and the server moves them
		RecoverySeconds = 0.05, -- free to M1 / use abilities right after arriving
		AirUsable = true,
		MinRequestSeconds = 0.25,
		AnimationId = "rbxassetid://133124508136712", -- generated in Studio (generate_animation), 0.97 s; played at 1.5x
		Description = "Melt into shadow and reappear behind the nearest enemy.",
	},
	{
		-- From the Blood Moon Slash prompt (2026-11-26); decided with the user: damage stays 20 + 5 bleed,
		-- the crescent stops at walls; v2 (user feedback): a real katana drawn from a sheath at the left
		-- hip (iaido), release at 0.58 s (the draw's fastest moment, BloodMoonSlashKeyframes), crescent
		-- flies 30 studs in 0.33 s. client/Abilities/BloodMoonSlashVFX reads it.
		Id = "BloodMoonSlash",
		Name = "Blood Moon Slash",
		Rarity = "Legendary",
		Type = "Melee",
		Damage = 20 / 1.35 ^ 4, -- each enemy takes exactly 20 after Legendary's Power (x1.35 per tier above Common)
		Cooldown = 20,
		Range = 30, -- studs the crescent travels (less if a wall is in the way: it stops there)
		Crescent = true,
		CrescentWidth = 30,
		CrescentHeight = 10,
		ProjectileSpeed = 90,
		WindupSeconds = 0.58, -- the draw's fastest moment (client/Abilities/BloodMoonSlashKeyframes): the release
		RecoverySeconds = 0.35, -- follow-through before the caster is free
		OnHit = "None", -- no stun or knockback: the damage + bleed are the payoff
		BleedPerTick = 1, -- Bleeding Wound: 1 damage a second...
		BleedSeconds = 5, -- ...for 5 s (5 total); a new hit refreshes it
		MinRequestSeconds = 0.25,
		AirUsable = false,
		AnimationId = "rbxassetid://110314848067099", -- the hand-made draw (BloodMoonSlashKeyframes), uploaded 2026-11-26
		Description = "A giant crimson crescent that cuts through every enemy in front of you.",
	},
	{
		-- From the Star Cannon prompt (2026-11-26); decided with the user: the beam is locked to the
		-- direction faced at release (no sweeping), a heavy slow so enemies can't walk out (Kamehameha-
		-- inspired), a stun / ragdoll on the caster cancels the charge or the beam (cooldown still spent),
		-- a front block stops it but drains guard every tick. client/Abilities/StarCannonVFX reads it.
		-- Timeline: rooted charge 1.5 s (orb + aura), beam 2 s, arms lower 0.4 s.
		Id = "StarCannon",
		Name = "Star Cannon",
		Rarity = "Legendary",
		Type = "Projectile",
		Damage = 10 / 1.35 ^ 4, -- first contact deals exactly 10 after Legendary's Power
		Cooldown = 20,
		Range = 80, -- beam length (less if a wall is in the way: it stops there)
		Beam = true,
		BeamWidth = 12,
		BeamSeconds = 2,
		BeamTickSeconds = 0.2,
		BeamTickDamage = 2, -- every 0.2 s while inside after the first contact (final damage)
		BeamMaxDamage = 30, -- 10 + 10 ticks x 2: the most one enemy takes from one beam
		WindupSeconds = 1.5, -- the charge (caster rooted, can't turn); stun / ragdoll cancels it
		RecoverySeconds = 2.4, -- the beam (2 s) + lowering the arms; stays rooted, a stun stops the beam
		SlowMultiplier = 0.3, -- walk -70% while being hit...
		SlowJumpMultiplier = 0.5, -- ...jump -50%...
		SlowSeconds = 0.5, -- ...lasting 0.5 s after the last tick that hit them
		SlowKind = "Heavy",
		GuardDamage = 1, -- per blocked tick (guard 6: holding block into the beam breaks in ~1 s)
		AirUsable = false,
		MinRequestSeconds = 0.25,
		AnimationId = "rbxassetid://73106483251546", -- the hand-made charge + thrust (StarCannonKeyframes), uploaded 2026-11-27
		Description = "Charge a star in your hands and unleash a massive beam of stellar energy.",
	},
	{
		Id = "VoidEclipse",
		Name = "Void Eclipse",
		Rarity = "Mythic",
		Type = "AoE",
		Damage = 30,
		Cooldown = 20,
		Range = 18,
		Description = "A black sphere that pulls players in.",
	},
	{
		Id = "ZeroHour",
		Name = "Zero Hour",
		Rarity = "Secret",
		Type = "AoE",
		Damage = 20,
		Cooldown = 25,
		Range = 24,
		Description = "Freezes time around you for 1.5 seconds.",
	},
}

return Abilities

--!strict
-- Shared type definitions used by both server and client.

export type Rarity =
	"Common"
	| "Uncommon"
	| "Rare"
	| "Epic"
	| "Legendary"
	| "Ascended"
	| "Mythic"
	| "Divine"
	| "Secret"

export type AbilityType = "Melee" | "Projectile" | "AoE" | "Movement" | "Defense"

-- What a hit does to the target (vault: 12 Combat System → Abilities as combo extenders).
--   Stun / Pull → the M1 string can restart. Ragdoll / Launch → the combo ends unless another ability follows.
export type OnHit = "Stun" | "Ragdoll" | "Launch" | "Pull" | "None"
-- The M1 finishers an ability is designed to follow. Descriptive only: it never makes a hit land.
export type Finisher = "Knockback" | "GroundSmash" | "Downslam"

export type RarityDef = {
	Name: Rarity,
	Rank: number, -- 1 = Common ... 9 = Secret (higher = rarer)
	OneIn: number?, -- the "1 in N" check; nil for Common (it is the fallback)
	Lucky: boolean, -- true if luck boosts this tier
	Color: Color3,
	RevealSeconds: number, -- normal reveal length
	Power: number, -- damage/healing/shield multiplier (x1.35 per tier)
	Shards: number, -- Shards given when a result of this tier is skipped
}

export type AbilityDef = {
	Id: string,
	Name: string,
	Rarity: Rarity,
	Type: AbilityType,
	Damage: number,
	Cooldown: number, -- seconds
	Range: number, -- studs
	Description: string,
	-- Melee timing/feel. Optional until every ability has its own.
	WindupSeconds: number?, -- from key press to the hit (matches the animation)
	HitboxWidth: number?, -- studs, side to side
	HitboxHeight: number?, -- studs, up and down; set = an exact box (HitboxService.InBox) of Width x Height x Range
	Knockback: number?, -- studs/second pushed away from the attacker
	SlowMultiplier: number?, -- a hit multiplies the target's WalkSpeed by this (StateService.ApplySlow)...
	SlowSeconds: number?, -- ...for this long; a new hit refreshes the timer, never stacks
	SlowJumpMultiplier: number?, -- ...and its jump height/power by this (default 1 = no jump change)
	-- Channelled beam (Star Cannon): WindupSeconds = the charge (caster rooted); Range = beam length.
	Beam: boolean?,
	BeamWidth: number?, -- studs across (a square box this wide and tall)
	BeamSeconds: number?, -- how long it fires
	BeamTickSeconds: number?, -- damage every this often while inside
	BeamTickDamage: number?, -- per tick, final (no rarity Power); first contact deals Damage x Power
	BeamMaxDamage: number?, -- most one enemy can take from one beam
	SlowKind: string?, -- status icon for this ability's slow: "Freeze" (default) or "Heavy"
	-- Crescent slash (Blood Moon Slash): a wide wall of energy swept forward from the caster.
	-- WindupSeconds = release; Range = studs travelled; ProjectileSpeed = studs/second.
	Crescent: boolean?,
	CrescentWidth: number?, -- studs, side to side
	CrescentHeight: number?, -- studs, from the ground up
	BleedPerTick: number?, -- a clean hit bleeds this much every second... (CombatService.ApplyBleed)
	BleedSeconds: number?, -- ...for this long; a new hit refreshes it, never stacks
	AimTrackSeconds: number?, -- the caster's client turns them with the camera this long during the wind-up (Sever)
	AimAtRelease: boolean?, -- the direction is where the caster faces at the release, not at the key press
	RootDuringWindup: boolean?, -- no walking or jumping through the wind-up and recovery (turning allowed)
	-- Domain (Altar of Ruin): after the cast an altar rises DomainBehindStuds behind the caster; when it's up,
	-- every DomainTickSeconds for DomainSeconds everyone within Range (radius) of it takes Damage x Power,
	-- or DomainBlockedTickDamage while blocking (plus guard drain), and is slowed (SlowMultiplier...).
	Domain: boolean?,
	DomainBehindStuds: number?,
	DomainRiseSeconds: number?,
	DomainSeconds: number?,
	DomainTickSeconds: number?,
	DomainBlockedTickDamage: number?,
	DomainGuardDrainPerSecond: number?,
	DomainHeightLimit: number?,
	-- Lock-on teleport (Shadow Swap): Range = lock-on radius. WindupSeconds = when the caster vanishes.
	Teleport: boolean?, -- teleports behind the nearest enemy in Range (shared/Teleport); no enemy = refused, no cooldown
	BehindStuds: number?, -- how far behind the target it lands
	-- Area of effect around the caster. Range = radius (studs); WindupSeconds = when it hits.
	AoeMaxTargets: number?, -- most fighters one cast hits (default 8)
	MinRequestSeconds: number?, -- the server ignores another UseAbility for this ability within this time
	DurationSeconds: number?, -- how long the move lasts (animation + recovery)
	-- Projectile flight. WindupSeconds = when it leaves the hand; Range = how far it flies.
	ProjectileSpeed: number?, -- studs/second
	ProjectileRadius: number?, -- studs, the projectile itself: walls and the ground stop it
	HitboxRadius: number?, -- studs, the sphere swept along the path that finds characters (shared/Projectile)
	ThrowOffset: Vector3?, -- studs right, up, forward from the HumanoidRootPart where it leaves the hand
	ProjectileLead: number?, -- studs the projectile's front is ahead of the hand (a spear's tip)
	ServerClock: boolean?, -- flown on the server clock: AbilityLaunch tells the other clients when and where it left the hand
	SkyStrike: boolean?, -- a character hit also calls a lightning strike down onto the target (AbilityStrike)
	StrikeDamage: number?, -- damage of that strike, dealt StrikeDelay after the hit (0 = visual only)
	-- Movement (dash). Range = studs dashed; WindupSeconds = when the dash starts.
	MaxDashStuds: number?, -- studs; the server pulls back any dash that moves further
	DashWindowSeconds: number?, -- seconds after the key press the server watches the dash
	AnimationId: string?, -- uploaded animation ("rbxassetid://..."); nil = Studio-only test animation
	Icon: string?, -- image id shown on the hotbar and inventory cards (Config/Assets)
	-- Combat metadata (filled in by the ability team, read by CombatService). Missing = the default in
	-- Config/Combat → AbilityDefaults.
	Followup: { Finisher }?, -- intended combo routes (design + UI hints only, never guarantees a hit)
	AirUsable: boolean?, -- can be cast in the air (the server checks airborne-ness itself)
	OnHit: OnHit?, -- default "None"
	GuardBreak: boolean?, -- goes through block
	GuardDamage: number?, -- guard points taken when blocked (default 2; heavy skills 3)
	Stun: number?, -- seconds, for OnHit Stun / Launch / Pull
	RagdollSeconds: number?, -- for OnHit Ragdoll
	RagdollCancellable: boolean?, -- for OnHit Ragdoll; default true
	RecoverySeconds: number?, -- caster stays busy this long after the wind-up (default 0.25)
}

-- One row of the odds screen: the real chance of one ability.
export type AbilityChance = {
	AbilityId: string,
	Rarity: Rarity,
	Chance: number, -- 0..1
}

-- Everything that adds luck. The server fills this from what it knows
-- (passes, potions, which machine you're at); the client never sends it.
export type LuckSources = {
	HasLuckPass: boolean, -- x2 Luck pass: +1
	PotionBonus: number, -- active potion: +1 (Luck) or +2 (Super Luck), 0 if none
	AreaBonus: number, -- spin machine you're at: 0, 0.1 ... 0.4, VIP 0.5
	ServerLuck: boolean, -- someone bought Server Luck in this server: +1
}

return {}

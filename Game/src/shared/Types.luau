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

--!strict
-- CombatService: battlegrounds combat. The ONE hit pipeline for M1s and abilities.
-- Vault: 12 Combat System (latest rules) on top of the Core Combat PDF.
--
-- Abilities must go through CombatService.ApplyHit / AbilityHit; never TakeDamage, stun or ragdoll directly.
-- ApplyHit is where block, guard break, spawn shield, safe zones, i-frames, stun immunity, the control cap,
-- once-per-combo, combo scaling, KO credit, reactions and knockback all happen, in that order.
--
-- Client ↔ server for the sender's own inputs (CombatResult remote, kind first):
--   "M1", seq, true, comboIndex, finisher ("" if none), m1LockedUntil
--   "M1", seq, false, comboIndex, retryAt, m1LockedUntil, reason
--   "M1Whiff", seq, extraSeconds         the swing missed: the next one comes later
--   "M1Cancelled", seq                   the swing was interrupted before its hit frame
--   "Dash", accepted, kind, readyAt
--   "Block", accepted
--   "RagdollCancel", accepted, readyAt
--   "Ability", slot, false, readyIn, reason   (sent by AbilityService; readyIn in seconds)
-- Times named ...At / ...Until are server times (workspace:GetServerTimeNow()).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Knockback = require(Shared:WaitForChild("Knockback"))
local Types = require(Shared:WaitForChild("Types"))
local Combat = require(Shared:WaitForChild("Config"):WaitForChild("Combat"))
local Rarities = require(Shared:WaitForChild("Config"):WaitForChild("Rarities"))

local Services = script.Parent
local StateService = require(Services:WaitForChild("StateService"))
local HitboxService = require(Services:WaitForChild("HitboxService"))
local RagdollService = require(Services:WaitForChild("RagdollService"))
local RemoteGuard = require(Services:WaitForChild("RemoteGuard"))
local DataService = require(Services:WaitForChild("DataService"))

type AbilityDef = Types.AbilityDef

-- Training dummies (tag "TrainingDummy", made in Studio) heal back to full this long after a hit.
local DUMMY_HEAL_SECONDS = 2

export type Hit = {
	damage: number,
	stun: number?, -- seconds of hitstun
	ragdoll: number?, -- seconds of physics ragdoll
	ragdollCancellable: boolean?, -- can the target ragdoll-cancel (Q) out of it? default true
	launch: Vector3?, -- velocity relative to the attacker's facing (-Z = forward, +Y = up)
	worldLaunch: Vector3?, -- velocity in world space (added to launch)
	launchSeconds: number?, -- how long the launch pushes a standing target (default 0.18)
	hang: number?, -- seconds the target hangs in the air afterwards, falling at HangFallSpeed
	guardBreak: boolean?, -- goes through block
	guardDamage: number?, -- guard points taken if blocked (default: 1 for M1s, 2 for abilities)
	origin: Vector3?, -- where the hit comes from for the block's front check (default: attacker's root)
	castId: number?, -- the ability cast this hit belongs to (once-per-combo allows every hit of one cast)
	abilityId: string, -- "M1_1".."M1_4", "M1_Downslam", "M1_GroundSmash" for M1s; the ability's Id otherwise
	fxKind: string?, -- the hit effect kind clients show (default "Hit"; "WallCombo" for the wall combo)
	attackerModel: Model?, -- the attacker's character when there is no Player (NPC training dummies)
}

export type HitResult = "Hit" | "Blocked" | "GuardBreak" | "Immune" | "SafeZone" | "OncePerCombo" | "Invalid"

local CombatService = {}

local hitEffect: RemoteEvent
local knockbackRemote: RemoteEvent
local combatResult: RemoteEvent
local killFeed: RemoteEvent

-- Per-attacker M1 string. Reset when the character changes (respawn).
type Chain = { index: number, lastAt: number, nextAllowedAt: number, character: Model? }
local chains: { [Instance]: Chain } = {} -- keyed by Player, or by the character for NPC dummies

-- Dash cooldowns per player and group ("Front" / "SideBack"), server clock.
local dashReadyAt: { [Player]: { [string]: number } } = {}
local dashKinds: { [Model]: string } = {} -- kind of the dash currently running
local movementWatches: { [Player]: RBXScriptConnection } = {}

-- KO credit: last player who damaged this fighter, and when.
local lastHitBy: { [Model]: { player: Player, at: number } } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(model: Model?): BasePart?
	return if model then model:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.zero
end

local function reply(player: Player?, ...: any)
	if not player then
		return -- an NPC dummy has no client to answer
	end
	combatResult:FireClient(player, ...)
end

-- Moves a standing character where its physics is owned. seconds/hangSeconds are optional (see Knockback.Apply).
local function push(model: Model, root: BasePart, velocity: Vector3, seconds: number?, hangSeconds: number?)
	local victim = Players:GetPlayerFromCharacter(model)
	if victim then
		-- A player's character is moved by their own client (it owns the physics).
		knockbackRemote:FireClient(victim, velocity, seconds, hangSeconds)
	else
		local hover = if hangSeconds then { Seconds = hangSeconds, FallSpeed = Combat.HangFallSpeed } else nil
		Knockback.Apply(root, velocity, seconds, hover)
	end
end

-- ===== Zones =====

-- Parts tagged "SafeZone" (built in Studio): nobody inside can hit or be hit (dummies excepted).
local function inSafeZone(position: Vector3): boolean
	for _, zone in CollectionService:GetTagged("SafeZone") do
		if zone:IsA("BasePart") then
			local p = zone.CFrame:PointToObjectSpace(position)
			local half = zone.Size / 2
			if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z then
				return true
			end
		end
	end
	return false
end

local function isDummy(model: Model): boolean
	return CollectionService:HasTag(model, "TrainingDummy")
end

-- ===== Airborne (server's own check, the client's claim is only a hint) =====

-- Is the fighter really in the air? Height of the root above the ground under it (fighters ignored,
-- so a dummy underneath doesn't count as ground) vs. its normal standing height.
function CombatService.IsAirborne(character: Model): boolean
	local root = rootOf(character)
	if not root then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.CollisionGroup = "Fighters"
	local result = workspace:Raycast(root.Position, Vector3.new(0, -50, 0), params)
	local height = if result then root.Position.Y - result.Position.Y else math.huge
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local standing = (if humanoid then humanoid.HipHeight else 2) + root.Size.Y / 2
	return height >= standing + Combat.Downslam.MinHeight
end

-- ===== The one hit pipeline =====

local function attackerKey(attacker: Player?): string
	return if attacker then tostring(attacker.UserId) else "world"
end

local function isAbilityHit(hit: Hit): boolean
	return string.find(hit.abilityId, "^M1_") == nil
end

-- Is the hit coming from inside the target's front block cone?
local function fromFront(targetRoot: BasePart, origin: Vector3): boolean
	local toOrigin = flat(origin - targetRoot.Position)
	if toOrigin == Vector3.zero then
		return true
	end
	local facing = flat(targetRoot.CFrame.LookVector)
	local halfCone = math.rad(Combat.Block.FrontConeDegrees / 2)
	return facing:Dot(toOrigin) >= math.cos(halfCone)
end

local function setReaction(target: Model, reaction: string)
	target:SetAttribute("Reaction", reaction)
	-- Counter, so every hit fires the attribute signal even when the reaction is the same.
	target:SetAttribute("ReactionHit", ((target:GetAttribute("ReactionHit") :: number?) or 0) + 1)
end

local function noteDamage(target: Model, attacker: Player?)
	if attacker then
		lastHitBy[target] = { player = attacker, at = now() }
	end
end

-- ===== Perfect block buff (Critical / Black Flash) =====
-- A perfect block buffs the blocker's next M1: x CritMultiplier (Critical), or x BlackFlashMultiplier when
-- they were already buffed and the chain allows it. The chain counts consecutive Black Flashes; it resets
-- with a Critical, or when the buff lapses unused.
type Buff = { kind: string?, untilAt: number, chain: number }
local buffs: { [Model]: Buff } = {}

local function grantBuff(character: Model)
	local cfg = Combat.Block
	local t = now()
	local b = buffs[character]
	if not b then
		b = { kind = nil, untilAt = 0, chain = 0 }
		buffs[character] = b
	end
	if t >= b.untilAt then
		b.kind = nil
		b.chain = 0
	end
	b.kind = if b.kind and b.chain < cfg.BlackFlashMaxChain then "BlackFlash" else "Critical"
	b.untilAt = t + cfg.BuffSeconds
end

-- The attacker's M1 connects: returns the damage multiplier and the effect kind, and spends the buff.
local function spendBuff(character: Model?): (number, string?)
	local b = character and buffs[character]
	if not b or not b.kind or now() >= b.untilAt then
		return 1, nil
	end
	local kind = b.kind
	b.kind = nil
	if kind == "BlackFlash" then
		b.chain += 1
		return Combat.Block.BlackFlashMultiplier, kind
	end
	b.chain = 0
	return Combat.Block.CritMultiplier, kind
end

-- Blocked hit: chip damage, guard damage, maybe a guard break. Returns the result.
local function blocked(attacker: Player?, target: Model, root: BasePart, humanoid: Humanoid, hit: Hit): HitResult
	local f = StateService.Get(target)
	if not f then
		return "Invalid"
	end
	local cfg = Combat.Block
	local guardDamage = hit.guardDamage
		or (if isAbilityHit(hit) then Combat.AbilityDefaults.GuardDamage else cfg.M1GuardDamage)
	f.lastBlockedAt = now()
	StateService.SetGuard(target, f.guard - guardDamage)
	humanoid:TakeDamage(hit.damage * cfg.DamageTaken)
	noteDamage(target, attacker)

	local attackerRoot = rootOf(attacker and attacker.Character)
	local away = if attackerRoot then flat(root.Position - attackerRoot.Position) else Vector3.zero

	if f.guard <= 0 then
		-- Guard break: staggered, can't block for a while, guard refills for next time.
		StateService.Set(target, "GuardBroken", cfg.GuardBreakStunSeconds)
		f.blockDisabledUntil = now() + cfg.BlockDisabledAfterBreak
		StateService.SetGuard(target, cfg.GuardPoints)
		setReaction(target, "Stun")
		hitEffect:FireAllClients(target, hit.abilityId, root.Position, "GuardBreak", attacker and attacker.Character)
		return "GuardBreak"
	end
	if away ~= Vector3.zero then
		push(target, root, away * cfg.BlockedPushback, 0.12)
	end
	hitEffect:FireAllClients(target, hit.abilityId, root.Position, "Blocked", attacker and attacker.Character)
	return "Blocked"
end

-- The ONE damage path. Returns true if the hit landed (blocked hits count as landed), plus why.
function CombatService.ApplyHit(attacker: Player?, target: Model, hit: Hit): (boolean, HitResult)
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	local root = rootOf(target)
	if not humanoid or not root or humanoid.Health <= 0 or not StateService.Get(target) then
		return false, "Invalid"
	end
	if type(hit.damage) ~= "number" or hit.damage ~= hit.damage or hit.damage < 0 then
		return false, "Invalid"
	end
	local attackerCharacter = (if attacker then attacker.Character else nil) or hit.attackerModel
	if attackerCharacter == target then
		return false, "Invalid"
	end
	local attackerRoot = rootOf(attackerCharacter)

	-- 1. Safe zones (dummies can always be hit, so training near spawn works).
	if not isDummy(target) then
		if inSafeZone(root.Position) or (attackerRoot and inSafeZone(attackerRoot.Position)) then
			return false, "SafeZone"
		end
	end
	-- 2. Damage invulnerability: spawn shield, dash / ragdoll-cancel i-frames.
	if StateService.HasIFrames(target) then
		return false, "Immune"
	end
	-- 3. Abilities: once per attacker → target combo (every hit of the same cast is fine).
	local ability = isAbilityHit(hit)
	local comboKey = `{attackerKey(attacker)}:{hit.abilityId}`
	if ability and not StateService.AbilityAllowedInCombo(target, comboKey, hit.castId) then
		return false, "OncePerCombo"
	end
	-- 4. Block (front cone only, after its startup), unless the hit breaks guard.
	local f = StateService.Get(target)
	if f and f.state == "Blocking" and not hit.guardBreak then
		local held = f.blockStartedAt > 0 and now() - f.blockStartedAt >= Combat.Block.Startup
		local origin = hit.origin or (if attackerRoot then attackerRoot.Position else root.Position)
		-- Perfect block: an M1 from the front landing right after the block began is stopped entirely
		-- (no damage, no guard cost) and buffs the blocker's next M1.
		if
			not ability
			and f.blockStartedAt > 0
			and now() - f.blockStartedAt <= Combat.Block.PerfectWindow
			and fromFront(root, origin)
		then
			grantBuff(target)
			hitEffect:FireAllClients(target, hit.abilityId, root.Position, "PerfectBlock", attackerCharacter)
			return true, "Blocked"
		end
		if held and fromFront(root, origin) then
			local result = blocked(attacker, target, root, humanoid, hit)
			return true, result
		end
	end

	-- 5. Damage with combo scaling.
	local scale = StateService.RegisterComboHit(target)
	local hitKind = hit.fxKind or "Hit"
	if not ability and not hit.fxKind then
		-- An M1 after a perfect block hits much harder (Critical / Black Flash).
		local multiplier, buffKind = spendBuff(attackerCharacter)
		scale *= multiplier
		hitKind = buffKind or hitKind
	end
	humanoid:TakeDamage(hit.damage * scale)
	noteDamage(target, attacker)
	if ability and hit.castId then
		StateService.MarkAbilityUsed(target, comboKey, hit.castId)
	end

	-- 6. Control: stun / ragdoll, unless stun immune or past the control cap. Damage still counts.
	local state = StateService.GetState(target)
	local canControl = not StateService.IsStunImmune(target) and not StateService.IsControlCapped(target)
	local reaction: string? = nil
	if canControl and hit.ragdoll and hit.ragdoll > 0 then
		local seconds = math.min(hit.ragdoll, math.max(0.3, StateService.ControlLeft(target)))
		StateService.MarkRagdoll(target, hit.ragdollCancellable ~= false)
		StateService.Set(target, "Ragdolled", seconds)
		reaction = "Down"
	elseif canControl and hit.stun and hit.stun > 0 and (state ~= "Ragdolled" or ability) then
		-- An ability's stun picks a ragdolled body up (M1×4 → ability → M1×4 extensions); bounded by
		-- once-per-combo, cooldowns and the control cap. M1s never do (they skip ragdolled targets).
		local seconds = math.min(hit.stun, math.max(0.2, StateService.ControlLeft(target)))
		StateService.Set(target, "Stunned", seconds)
		reaction = if hit.hang or (hit.launch and hit.launch.Y > 0) then "Air" else "Stun"
	elseif state == "Ragdolled" then
		reaction = "Down"
	end
	if reaction then
		setReaction(target, reaction)
	end

	-- 7. Knockback / launch.
	local velocity = Vector3.zero
	if hit.launch and hit.launch.Magnitude > 0 then
		local facing = if attackerRoot then attackerRoot.CFrame else root.CFrame
		local look = flat(facing.LookVector)
		local basis = if look ~= Vector3.zero then CFrame.lookAt(Vector3.zero, look) else CFrame.identity
		velocity += basis:VectorToWorldSpace(hit.launch)
	end
	if hit.worldLaunch then
		velocity += hit.worldLaunch
	end
	if RagdollService.IsPhysical(target) then
		if velocity.Magnitude > 0 then
			RagdollService.Impulse(target, velocity)
		end
	elseif velocity.Magnitude > 0 then
		push(target, root, velocity, hit.launchSeconds, hit.hang)
	elseif hit.hang then
		push(target, root, Vector3.zero, 0, hit.hang) -- keep it hanging where it is
	end

	hitEffect:FireAllClients(target, hit.abilityId, root.Position, hitKind, attackerCharacter)
	return true, "Hit"
end

-- Can this ability hit this target right now? (once per combo, i-frames, safe zones)
-- Abilities may call it before their own effects (e.g. a pull); ApplyHit checks the same things again.
function CombatService.CanAbilityHit(target: Model, abilityId: string, attacker: Player?, castId: number?): boolean
	local root = rootOf(target)
	if not root or not StateService.Get(target) or StateService.HasIFrames(target) then
		return false
	end
	if not isDummy(target) and inSafeZone(root.Position) then
		return false
	end
	return StateService.AbilityAllowedInCombo(target, `{attackerKey(attacker)}:{abilityId}`, castId)
end

-- Old damage path, kept so older ability code keeps working. It now goes through ApplyHit
-- (block, immunity, scaling…). knockback = world velocity (studs/s). Prefer AbilityHit / ApplyHit.
-- ===== Channelled beam ticks (Star Cannon) =====
-- One tick of a beam: block (front cone, held) stops it but drains `guardDamage` guard (a guard break
-- staggers); otherwise `amount` damage with no combo scaling, no hit reaction and no knockback (the
-- beam is not a stun). Safe zones and i-frames apply. Returns what happened.
function CombatService.TickHit(attacker: Player, target: Model, amount: number, origin: Vector3, abilityId: string, guardDamage: number): HitResult
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	local root = rootOf(target)
	if not humanoid or not root or humanoid.Health <= 0 or not StateService.Get(target) then
		return "Invalid"
	end
	local attackerCharacter = attacker and attacker.Character
	if attackerCharacter == target then
		return "Invalid"
	end
	local attackerRoot = rootOf(attackerCharacter)
	if not isDummy(target) then
		if inSafeZone(root.Position) or (attackerRoot and inSafeZone(attackerRoot.Position)) then
			return "SafeZone"
		end
	end
	if StateService.HasIFrames(target) then
		return "Immune"
	end
	local f = StateService.Get(target)
	if f and f.state == "Blocking" then
		local held = f.blockStartedAt > 0 and now() - f.blockStartedAt >= Combat.Block.Startup
		if held and fromFront(root, origin) then
			return blocked(attacker, target, root, humanoid, { damage = amount, guardDamage = guardDamage, abilityId = abilityId } :: any)
		end
	end
	humanoid:TakeDamage(amount)
	noteDamage(target, attacker)
	return "Hit"
end

-- ===== Domain ticks (Altar of Ruin) =====
-- One tick of a lasting zone. The slashes come from every side, so a held block (any direction) only
-- softens it: blockedAmount damage and guardDrain guard lost instead of amount; when the guard runs out it
-- breaks (staggered, can't block for a while). No combo scaling, hit reaction or knockback; safe zones,
-- spawn shields and i-frames still stop it, and the caster gets the KO credit.
function CombatService.DomainTick(attacker: Player?, target: Model, amount: number, blockedAmount: number, guardDrain: number, abilityId: string): HitResult
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	local root = rootOf(target)
	if not humanoid or not root or humanoid.Health <= 0 or not StateService.Get(target) then
		return "Invalid"
	end
	local attackerCharacter = if attacker then attacker.Character else nil
	if attackerCharacter == target then
		return "Invalid"
	end
	if not isDummy(target) and inSafeZone(root.Position) then
		return "SafeZone"
	end
	if StateService.HasIFrames(target) then
		return "Immune"
	end
	local f = StateService.Get(target)
	local cfg = Combat.Block
	if f and f.state == "Blocking" and f.blockStartedAt > 0 and now() - f.blockStartedAt >= cfg.Startup then
		f.lastBlockedAt = now()
		StateService.SetGuard(target, f.guard - guardDrain)
		humanoid:TakeDamage(blockedAmount)
		noteDamage(target, attacker)
		if f.guard <= 0 then
			StateService.Set(target, "GuardBroken", cfg.GuardBreakStunSeconds)
			f.blockDisabledUntil = now() + cfg.BlockDisabledAfterBreak
			StateService.SetGuard(target, cfg.GuardPoints)
			setReaction(target, "Stun")
			hitEffect:FireAllClients(target, abilityId, root.Position, "GuardBreak", attackerCharacter)
			return "GuardBreak"
		end
		return "Blocked"
	end
	humanoid:TakeDamage(amount)
	noteDamage(target, attacker)
	return "Hit"
end

-- ===== Status damage (bleed) =====
-- Damage from a status over time: no block, combo scaling, hit reaction or knockback, but spawn
-- shields / i-frames still stop it and the attacker still gets the KO credit.
function CombatService.StatusDamage(attacker: Player?, target: Model, amount: number): boolean
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or not StateService.Get(target) or StateService.HasIFrames(target) then
		return false
	end
	humanoid:TakeDamage(amount)
	noteDamage(target, attacker)
	return true
end

-- Bleed: `perTick` damage every second for `seconds` (Blood Moon Slash: 1 x 5). A new bleed refreshes
-- the timer, never stacks. Mirrored as the attribute BleedEndsAt (server time) for UI / effects.
type Bleed = { attacker: Player?, perTick: number, nextTick: number, endsAt: number }
local bleeds: { [Model]: Bleed } = {}
local BLEED_INTERVAL = 1

local function stopBleed(target: Model)
	bleeds[target] = nil
	if target.Parent then
		target:SetAttribute("BleedEndsAt", nil)
	end
end

function CombatService.ApplyBleed(attacker: Player?, target: Model, perTick: number, seconds: number)
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local t = now()
	bleeds[target] = { attacker = attacker, perTick = perTick, nextTick = t + BLEED_INTERVAL, endsAt = t + seconds }
	target:SetAttribute("BleedEndsAt", t + seconds)
end

local function stepBleeds()
	local t = now()
	for target, bleed in bleeds do
		local humanoid = target:FindFirstChildOfClass("Humanoid")
		if not target.Parent or not humanoid or humanoid.Health <= 0 then
			stopBleed(target)
			continue
		end
		while t >= bleed.nextTick and bleed.nextTick <= bleed.endsAt + 0.001 do
			CombatService.StatusDamage(bleed.attacker, target, bleed.perTick)
			bleed.nextTick += BLEED_INTERVAL
		end
		if bleed.nextTick > bleed.endsAt + 0.001 then
			stopBleed(target)
		end
	end
end

function CombatService.DealDamage(attacker: Player, target: Humanoid, amount: number, knockback: Vector3, abilityId: string)
	local model = target.Parent
	if model and model:IsA("Model") then
		CombatService.ApplyHit(attacker, model, {
			damage = amount,
			worldLaunch = if knockback.Magnitude > 0 then knockback else nil,
			abilityId = abilityId,
		})
	end
end

-- ===== Abilities =====
-- AbilityService validates the slot and cooldown, then: BeginCast → (wind-up) → IsCastCurrent → AbilityHit.

-- Start casting. Returns the cast id, or nil if the caster's state doesn't allow it (stunned,
-- ragdolled, blocking, mid-cast, M1 startup, in the air without AirUsable).
function CombatService.BeginCast(player: Player, def: AbilityDef): number?
	local character = player.Character
	if not character or not rootOf(character) or not StateService.Can(character, "Ability") then
		return nil
	end
	if not def.AirUsable and CombatService.IsAirborne(character) then
		return nil
	end
	local windup = def.WindupSeconds or 0
	local recovery = def.RecoverySeconds or Combat.AbilityDefaults.Recovery
	local castId = StateService.BeginAction(character, `Ability:{def.Id}`, windup)
	StateService.Set(character, "Casting", windup + recovery)
	return castId
end

-- Still the same uninterrupted cast (not stunned / ragdolled / dead / respawned since)?
function CombatService.IsCastCurrent(player: Player, castId: number): boolean
	local character = player.Character
	return character ~= nil and StateService.IsActionCurrent(character, castId)
end

-- Build the hit from the ability's metadata (OnHit, GuardBreak, Knockback, rarity power) and apply it.
-- overrides can replace any field (e.g. a multi-hit ability's lighter first hits).
function CombatService.AbilityHit(
	player: Player,
	target: Model,
	def: AbilityDef,
	castId: number,
	overrides: { [string]: any }?
): (boolean, HitResult)
	local d = Combat.AbilityDefaults
	local rarity = Rarities.Defs[def.Rarity]
	local power = if rarity then rarity.Power else 1
	local hit: Hit = {
		damage = def.Damage * power,
		guardBreak = def.GuardBreak == true,
		guardDamage = def.GuardDamage,
		castId = castId,
		abilityId = def.Id,
	}
	local onHit = def.OnHit or "None"
	local attackerRoot = rootOf(player.Character)
	local targetRoot = rootOf(target)
	if onHit == "Stun" then
		hit.stun = def.Stun or d.Stun
	elseif onHit == "Ragdoll" then
		hit.ragdoll = def.RagdollSeconds or d.Ragdoll
		hit.ragdollCancellable = def.RagdollCancellable ~= false
	elseif onHit == "Launch" then
		hit.stun = def.Stun or d.Stun
		hit.launch = Vector3.new(0, d.LaunchUp, 0)
		hit.hang = d.LaunchHang
	elseif onHit == "Pull" and attackerRoot and targetRoot then
		hit.stun = def.Stun or d.Stun
		hit.worldLaunch = flat(attackerRoot.Position - targetRoot.Position) * d.PullSpeed
	end
	-- Small push away from the caster (e.g. Ember Fist), on top of OnHit.
	if def.Knockback and def.Knockback > 0 and attackerRoot and targetRoot and onHit ~= "Pull" then
		local away = flat(targetRoot.Position - attackerRoot.Position)
		if away == Vector3.zero then
			away = flat(attackerRoot.CFrame.LookVector)
		end
		hit.worldLaunch = (hit.worldLaunch or Vector3.zero) + away * def.Knockback + Vector3.new(0, def.Knockback * 0.4, 0)
	end
	if overrides then
		for key, value in overrides do
			(hit :: any)[key] = value
		end
	end
	return CombatService.ApplyHit(player, target, hit)
end

-- ===== Wall combo =====
-- A Knockback / Downslam finisher with a wall right behind the target arms it for a moment: the
-- attacker's next FRONT dash (see onDash) hits the target again for a share of their MaxHealth.
type WallArm = { target: Model, untilAt: number }
local wallArmed: { [Model]: WallArm } = {} -- [attacker character]
local wallReadyAt: { [Model]: number } = {} -- [attacker character] cooldown

local function armWallCombo(attacker: Model, target: Model)
	local aRoot, tRoot = rootOf(attacker), rootOf(target)
	if not aRoot or not tRoot then
		return
	end
	local away = flat(tRoot.Position - aRoot.Position)
	if away == Vector3.zero then
		away = flat(aRoot.CFrame.LookVector)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attacker, target }
	params.CollisionGroup = "Fighters"
	if workspace:Raycast(tRoot.Position, away * Combat.WallCombo.Distance, params) then
		wallArmed[attacker] = { target = target, untilAt = now() + Combat.WallCombo.Window }
	end
end

-- ===== M1 string =====
-- Hits 1–3, then hit 4 = finisher: in the air (jumped) → Downslam, S held → Ground Smash,
-- otherwise Knockback. So the Downslam is M1 ×3, jump, M1.

type Box = { Size: Vector3, Offset: number, Down: number? }

-- The closest living, hittable fighter in the box in front of the attacker, or nil (whiff).
-- Ragdolled bodies are skipped: M1s don't hit people on the ground (abilities do).
local function closestTarget(character: Model, root: BasePart, aim: Vector3, box: Box): Model?
	local targets =
		HitboxService.InFront(character, root, aim, box.Offset + box.Size.Z / 2, box.Size.X, 8, box.Size.Y, box.Down)
	local best: Model? = nil
	local bestDist = math.huge
	for _, h in targets do
		local m = h.Parent
		local r = if m and m:IsA("Model") then rootOf(m) else nil
		if m and m:IsA("Model") and r and StateService.Get(m) and StateService.GetState(m) ~= "Ragdolled" then
			local d = (r.Position - root.Position).Magnitude
			if d < bestDist then
				best, bestDist = m, d
			end
		end
	end
	return best
end

local function newChain(character: Model?): Chain
	return { index = 0, lastAt = 0, nextAllowedAt = 0, character = character }
end

-- The punch goes where the client aimed, but never further than MaxAimAngle from the body's facing.
local function validAim(root: BasePart, aim: Vector3): Vector3
	local facing = flat(root.CFrame.LookVector)
	local wanted = flat(aim)
	if wanted == Vector3.zero then
		return facing
	end
	if facing:Dot(wanted) < math.cos(math.rad(Combat.M1.MaxAimAngle)) then
		return facing
	end
	return wanted
end

-- Runs one accepted swing: wait for the hit frame, look for a target during the active frames,
-- apply the hit. Every step re-checks that the swing is still current (not interrupted).
local function resolveSwing(
	player: Player?,
	character: Model,
	chain: Chain,
	id: number,
	seq: number,
	index: number,
	finisherIn: string?,
	aim: Vector3,
	swingAt: number
)
	local cfg = Combat.M1
	local finisher = finisherIn
	local moveName = if finisher == "Downslam" then "Downslam" elseif finisher then "M1_4" else `M1_{index}`
	local move = cfg.Moves[moveName]
	task.wait(move.Startup)
	if not StateService.IsActionCurrent(character, id) then
		reply(player, "M1Cancelled", seq)
		return -- stunned / ragdolled / dash-cancelled / died / respawned during the wind-up
	end
	local root = rootOf(character)
	if not root then
		return
	end

	-- The server decides airborne-ness itself.
	local airborne = CombatService.IsAirborne(character)
	if finisher == "Downslam" and not airborne then
		finisher = "Knockback" -- the client said "in the air", but the server sees it standing
	elseif finisher == "GroundSmash" and airborne then
		finisher = "Knockback"
	end
	local box: Box = if finisher == "Downslam" then Combat.Downslam.Hitbox else cfg.Hitbox

	-- Active frames: keep looking for a short moment, so a target moving into the punch still gets hit.
	local deadline = os.clock() + move.Active
	local target = closestTarget(character, root, aim, box)
	while not target and os.clock() < deadline do
		RunService.Heartbeat:Wait()
		if not StateService.IsActionCurrent(character, id) or not root.Parent then
			return
		end
		target = closestTarget(character, root, aim, box)
	end

	if finisher then
		-- Rest of the finisher's end lag is visible as EndLag (dash + abilities allowed, no M1).
		if StateService.GetState(character) == "Attacking" then
			StateService.Set(character, "EndLag", math.max(0.05, StateService.M1LockedFor(character)))
		end
		if finisher == "Downslam" then
			-- Drop back to the ground after the hammer, hit or miss.
			local d = Combat.Downslam
			push(character, root, Vector3.new(0, -d.DropVelocity, 0), d.DropSeconds)
		end
	end

	if not target then
		if not finisher then
			-- Whiff: the next swing comes WhiffRecovery later. The client predicts this too; the message
			-- corrects it when it didn't (moving targets, lag).
			chain.nextAllowedAt = math.max(chain.nextAllowedAt, swingAt + cfg.MinInterval + cfg.WhiffRecovery - cfg.ServerTolerance)
			reply(player, "M1Whiff", seq, cfg.WhiffRecovery)
		end
		return
	end

	if not finisher then
		-- The forward step is done by the attacker's own client at the swing (smoother than a server push).
		CombatService.ApplyHit(player, target, {
			damage = cfg.Damage[index],
			stun = cfg.Hitstun,
			abilityId = `M1_{index}`,
			attackerModel = character,
		})
		return
	end
	local fcfg = Combat.Finishers[finisher]
	local _, result = CombatService.ApplyHit(player, target, {
		attackerModel = character,
		damage = fcfg.Damage,
		ragdoll = fcfg.Ragdoll,
		ragdollCancellable = fcfg.CanRagdollCancel,
		launch = fcfg.Launch,
		guardBreak = fcfg.GuardBreak == true,
		guardDamage = Combat.Block.FinisherGuardDamage,
		abilityId = if finisher == "Knockback" then "M1_4" else `M1_{finisher}`,
	})
	if result == "Hit" and (finisher == "Knockback" or finisher == "Downslam") then
		armWallCombo(character, target)
	end
end

local FINISHER_BY_INPUT: { [string]: string } = { None = "Knockback", Air = "Downslam", S = "GroundSmash" }

-- One M1 press for a fighter: a Player (their remote), or an NPC training dummy (player = nil, see
-- NpcM1). Same rules either way. Returns true when the swing started.
local function runM1(player: Player?, character: Model, aim: Vector3, finisherInput: string, seq: number): boolean
	local root = rootOf(character)
	if not root then
		return false
	end
	local cfg = Combat.M1
	local t = now()
	local key: Instance = player or character
	local chain = chains[key]
	if not chain or chain.character ~= character then
		chain = newChain(character)
		chains[key] = chain
	end
	local function reject(reason: string)
		-- Absolute server times (the client compares them with workspace:GetServerTimeNow()).
		local retryAt = chain.nextAllowedAt + cfg.ServerTolerance
		reply(player, "M1", seq, false, chain.index, retryAt, t + StateService.M1LockedFor(character), reason)
	end

	if not StateService.Can(character, "M1") then
		reject("State")
		return false
	end
	if t < chain.nextAllowedAt then
		reject("TooSoon")
		return false
	end
	-- Hit 4 gets a longer window (time to jump for the Downslam). Plus slack for network jitter.
	local window = if chain.index == cfg.ChainLength - 1 then cfg.FinisherWindow else cfg.ChainResetSeconds
	local dropped = t - chain.lastAt > window + cfg.ServerTolerance
	if dropped and chain.index > 0 and chain.index < cfg.ChainLength and t - chain.lastAt < cfg.RestartDelay then
		reject("Restart") -- string dropped before hit 4: wait before starting again (no M1, pause, M1 stun-locks)
		return false
	end
	if dropped or chain.index >= cfg.ChainLength then
		chain.index = 0
	end
	chain.index += 1
	chain.lastAt = t
	chain.nextAllowedAt = t + cfg.MinInterval - cfg.ServerTolerance

	local index = chain.index
	local isFinisher = index == cfg.ChainLength
	local finisher = if isFinisher then (FINISHER_BY_INPUT[finisherInput] or "Knockback") else nil
	local moveName = if finisher == "Downslam" then "Downslam" elseif finisher then "M1_4" else `M1_{index}`
	local move = cfg.Moves[moveName]

	-- "Startup" for the cancel rules covers the active frames too: no ability on top of a live punch.
	local id = StateService.BeginAction(character, "M1", move.Startup + move.Active)
	if isFinisher then
		StateService.LockM1(character, cfg.EndLagSeconds)
	end
	StateService.Set(character, "Attacking", move.Length)
	reply(player, "M1", seq, true, index, finisher or "", t + StateService.M1LockedFor(character))

	task.spawn(resolveSwing, player, character, chain, id, seq, index, finisher, validAim(root, aim), t)
	return true
end

local function onM1(player: Player, aim: Vector3, finisherInput: string, seq: number)
	local character = player.Character
	if character then
		runM1(player, character, aim, finisherInput, seq)
	end
end

-- NPC training dummies (TrainingDummyService) throw the same M1 string through the same pipeline:
-- same timings, block / perfect block, stun, finishers. Face the target before calling.
function CombatService.NpcM1(character: Model, aim: Vector3): boolean
	return runM1(nil, character, aim, "None", 0)
end

-- ===== Block =====

-- Raise / lower the block for a Player (their remote) or an NPC dummy (player = nil, see NpcBlock).
local function setBlock(player: Player?, character: Model?, down: boolean)
	local f = character and StateService.Get(character)
	if not character or not f then
		return
	end
	if down then
		if f.state == "Blocking" then
			return
		end
		if not StateService.Can(character, "Block") then
			reply(player, "Block", false)
			return
		end
		StateService.CancelAction(character)
		StateService.Set(character, "Blocking")
		f.blockStartedAt = now()
		reply(player, "Block", true)
	elseif f.state == "Blocking" then
		StateService.Set(character, "Idle")
	end
end

local function onSetBlock(player: Player, down: boolean)
	setBlock(player, player.Character, down)
end

-- NPC training dummies hold / drop their block through the same rules (startup, guard, guard break).
function CombatService.NpcBlock(character: Model, down: boolean)
	setBlock(nil, character, down)
end

-- ===== Movement watch (dashes are moved by the client; the server checks distance) =====

-- For `seconds`, the character may move at most maxStuds along the ground from where it is now.
-- Further than that, it's pulled back onto that circle and stopped there.
function CombatService.WatchMovement(player: Player, root: BasePart, maxStuds: number, seconds: number)
	local previous = movementWatches[player]
	if previous then
		previous:Disconnect()
	end
	local start = root.Position
	local endsAt = os.clock() + seconds
	local watch: RBXScriptConnection
	watch = RunService.Heartbeat:Connect(function()
		if os.clock() > endsAt or not root.Parent then
			watch:Disconnect()
			if movementWatches[player] == watch then
				movementWatches[player] = nil
			end
			return
		end
		local moved = root.Position - start
		local along = Vector3.new(moved.X, 0, moved.Z)
		if along.Magnitude > maxStuds then
			local allowed = start + along.Unit * maxStuds
			local rotation = root.CFrame - root.Position
			root.CFrame = rotation + Vector3.new(allowed.X, root.Position.Y, allowed.Z)
			root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
		end
	end)
	movementWatches[player] = watch
end

-- ===== Dash =====

local DASH_CONFIG: { [string]: string } = { Front = "Front", Back = "Back", Left = "Side", Right = "Side" }

local function onDash(player: Player, kind: string, direction: Vector3)
	local character = player.Character
	local root = rootOf(character)
	local f = character and StateService.Get(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not f or not humanoid then
		return
	end
	local dcfg = Combat.Dash
	local cfg = dcfg[DASH_CONFIG[kind]]
	local t = now()
	local readyAt = dashReadyAt[player]
	if not readyAt then
		readyAt = {}
		dashReadyAt[player] = readyAt
	end
	local function reject(reason: string)
		reply(player, "Dash", false, kind, readyAt[cfg.Group] or 0, reason)
		-- Its client may have started moving already: only normal walking is let through.
		CombatService.WatchMovement(player, root, humanoid.WalkSpeed * (cfg.Duration + 0.3) + 2, cfg.Duration + 0.3)
	end

	if not StateService.Can(character, "Dash") then
		reject("State")
		return
	end
	if f.state == "Dashing" then
		-- Only the front → side dash cancel.
		local running = dashKinds[character]
		if not (dcfg.FrontToSideCancel and running == "Front" and DASH_CONFIG[kind] == "Side") then
			reject("Dashing")
			return
		end
	end
	-- The kind comes from the keys relative to the CAMERA, which the server can't see (the body turns
	-- to face where it walks), so only the direction itself is checked. Lying about the kind gains
	-- little: each kind's distance is capped by the watch below.
	if flat(direction) == Vector3.zero then
		reject("Direction")
		return
	end
	if t < (readyAt[cfg.Group] or 0) - dcfg.ServerTolerance then
		reject("Cooldown")
		return
	end
	readyAt[cfg.Group] = t + cfg.Cooldown

	-- Dashing during an M1's startup cancels that M1 (it never lands). After the hit frame it's free.
	local actionKind = StateService.CurrentAction(character)
	if dcfg.CancelsM1Startup and actionKind == "M1" and StateService.InStartup(character) then
		StateService.CancelAction(character)
	end
	dashKinds[character] = kind
	StateService.Set(character, "Dashing", cfg.Duration)
	StateService.GiveIFrames(character, cfg.IFrames)
	-- A side dash covers less ground the lower the health is (the client scales its dash the same way).
	local distance = cfg.Distance
	if DASH_CONFIG[kind] == "Side" then
		distance *= Combat.SideDashScale(humanoid.Health / humanoid.MaxHealth)
	end
	CombatService.WatchMovement(player, root, distance + dcfg.DistanceSlack, cfg.Duration + 0.3)
	reply(player, "Dash", true, kind, readyAt[cfg.Group])

	-- Wall combo: a front dash right after a finisher that pinned the target against a wall.
	local arm = wallArmed[character]
	if kind == "Front" and arm then
		wallArmed[character] = nil
		local wc = Combat.WallCombo
		local targetRoot = rootOf(arm.target)
		local targetHumanoid = arm.target:FindFirstChildOfClass("Humanoid")
		if
			targetRoot
			and targetHumanoid
			and targetHumanoid.Health > 0
			and t <= arm.untilAt + dcfg.ServerTolerance
			and t >= (wallReadyAt[character] or 0)
			and (targetRoot.Position - root.Position).Magnitude <= wc.MaxRange
		then
			local _, result = CombatService.ApplyHit(player, arm.target, {
				damage = wc.DamagePercent * targetHumanoid.MaxHealth,
				stun = wc.Stun,
				abilityId = "M1_WallCombo",
				fxKind = "WallCombo",
			})
			if result == "Hit" then
				wallReadyAt[character] = t + wc.Cooldown
			end
		end
	end
end

-- ===== Ragdoll cancel (escape) =====

local function onRagdollCancel(player: Player)
	local character = player.Character
	local root = rootOf(character)
	local f = character and StateService.Get(character)
	if not character or not root or not f then
		return
	end
	local cfg = Combat.RagdollCancel
	local t = now()
	local readyAt = StateService.RagdollCancelReadyAt(player)
	if
		f.state ~= "Ragdolled"
		or not f.ragdollCancellable
		or t - f.ragdollStartedAt < cfg.EarliestSeconds
		or t < readyAt
	then
		reply(player, "RagdollCancel", false, readyAt)
		return
	end
	StateService.SetRagdollCancelReadyAt(player, t + cfg.Cooldown)
	StateService.Set(character, "Idle") -- stands up (RagdollService), stun immunity (StateService)
	StateService.GiveIFrames(character, cfg.IFrames)
	-- Short back dash, moved by the player's own client (it owns its physics again).
	local back = -flat(root.CFrame.LookVector)
	push(character, root, back * (cfg.BackDashStuds / cfg.BackDashSeconds), cfg.BackDashSeconds)
	CombatService.WatchMovement(player, root, cfg.BackDashStuds + Combat.Dash.DistanceSlack, cfg.BackDashSeconds + 0.4)
	hitEffect:FireAllClients(character, "RagdollCancel", root.Position, "Escape", character)
	reply(player, "RagdollCancel", true, t + cfg.Cooldown)
end

-- ===== KO credit =====

local function onFighterAdded(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local victim = Players:GetPlayerFromCharacter(model)
	if not humanoid or not victim then
		return
	end
	humanoid.Died:Connect(function()
		local last = lastHitBy[model]
		lastHitBy[model] = nil
		local killer = if last and now() - last.at <= Combat.KOCreditSeconds then last.player else nil
		local victimData = DataService.Get(victim)
		if victimData then
			victimData.Deaths += 1
			DataService.Changed(victim, { "Deaths" })
		end
		if killer and killer ~= victim and killer.Parent then
			local killerData = DataService.Get(killer)
			if killerData then
				killerData.KOs += 1
				DataService.Changed(killer, { "KOs" })
			end
			killFeed:FireAllClients(killer, victim)
		end
	end)
end

-- ===== Setup =====

-- Called once at startup, before any Start(). Create state, read config. Don't yield.
function CombatService.Init()
	hitEffect = Remotes.Event("HitEffect")
	knockbackRemote = Remotes.Event("Knockback")
	combatResult = Remotes.Event("CombatResult")
	killFeed = Remotes.Event("KillFeed")
end

local function setUpDummy(model: Instance)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	-- Tagged dummies kept in storage (outside Workspace) aren't in the world yet.
	if not humanoid or not model:IsA("Model") or not model:IsDescendantOf(workspace) then
		return
	end
	humanoid.BreakJointsOnDeath = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		-- The server moves dummies (knockback), so the server must own their physics.
		root:SetNetworkOwner(nil)
	end
	local lastHit = 0
	humanoid.HealthChanged:Connect(function(health)
		if health >= humanoid.MaxHealth then
			return
		end
		local hitAt = os.clock()
		lastHit = hitAt
		if health <= 0 then
			humanoid.Health = 1 -- dummies never die
		end
		task.delay(DUMMY_HEAL_SECONDS, function()
			if lastHit == hitAt then
				humanoid.Health = humanoid.MaxHealth
			end
		end)
	end)
end

local function isUnitVector(x: unknown): boolean
	if typeof(x) ~= "Vector3" then
		return false
	end
	local v = x :: Vector3
	return RemoteGuard.IsFiniteNumber(v.X)
		and RemoteGuard.IsFiniteNumber(v.Y)
		and RemoteGuard.IsFiniteNumber(v.Z)
		and math.abs(v.Magnitude - 1) < 0.05
end

-- Called once after every Init(). Connect events, start loops.
function CombatService.Start()
	for _, model in CollectionService:GetTagged("TrainingDummy") do
		setUpDummy(model)
	end
	CollectionService:GetInstanceAddedSignal("TrainingDummy"):Connect(setUpDummy)
	StateService.OnAdded(onFighterAdded)
	RunService.Heartbeat:Connect(stepBleeds)
	StateService.OnRemoved(function(model)
		dashKinds[model] = nil
		bleeds[model] = nil
		buffs[model] = nil
		chains[model] = nil
		wallArmed[model] = nil
		wallReadyAt[model] = nil
		task.delay(Combat.KOCreditSeconds, function()
			lastHitBy[model] = nil -- (Died reads it first)
		end)
	end)

	-- Rate limits come first (RemoteGuard), before any hitbox work. 5/s covers a swing every 0.3 s
	-- plus a buffered click; anything faster is dropped before validation.
	local FINISHER_INPUTS = { None = true, Air = true, S = true }
	RemoteGuard.Event("M1Attack", { PerSecond = 5, Burst = 5 }, function(aim, finisherInput, seq)
		return isUnitVector(aim) and RemoteGuard.IsOneOf(finisherInput, FINISHER_INPUTS) and RemoteGuard.IsInteger(seq, 0, 2 ^ 30)
	end, onM1)

	RemoteGuard.Event("SetBlock", { PerSecond = 8, Burst = 8 }, function(down)
		return type(down) == "boolean"
	end, onSetBlock)

	local DASH_KINDS = { Front = true, Back = true, Left = true, Right = true }
	RemoteGuard.Event("Dash", { PerSecond = 4, Burst = 4 }, function(kind, direction)
		return RemoteGuard.IsOneOf(kind, DASH_KINDS) and isUnitVector(direction)
	end, onDash)

	RemoteGuard.Event("RagdollCancel", { PerSecond = 3, Burst = 3 }, function(...)
		return select("#", ...) == 0
	end, onRagdollCancel)

	Players.PlayerRemoving:Connect(function(player)
		chains[player] = nil
		dashReadyAt[player] = nil
		local watch = movementWatches[player]
		if watch then
			watch:Disconnect()
			movementWatches[player] = nil
		end
	end)
end

return CombatService

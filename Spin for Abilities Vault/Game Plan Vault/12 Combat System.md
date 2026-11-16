# 12 Combat System

Owner: combat dev (me). Ability design + VFX: the other two teammates.
Base spec: ![[Spin for Abilities – Core Combat (M1, Block, Dash).pdf]]
This note adds **finisher variants** and **abilities as combo extenders** on top of the PDF. All numbers live in `Game/src/shared/Config/Combat.luau`.

## Core idea
Feel like a TSB-style battlegrounds game: a 4-hit M1 string where **hit 4 is a finisher**. The finisher leaves the enemy in a position, and **the abilities you spun decide how you continue the combo**. Two players with the same M1s play differently because of what they rolled.

## Finishers (hit 4)
The key held when hit 4 lands picks the finisher.

| Input on hit 4 | Finisher | Target ends up | Ragdoll | Ragdoll cancel? | Typical follow-up |
|---|---|---|---|---|---|
| M1 | **Knockback** | ~18 studs away | 1.2 s | Yes | Dash-in or ranged ability |
| Jump + M1 (in the air) | **Downslam** | Hammered flat on the ground in front of you | 1.0 s | No | Ground AoE / slow-startup ability |
| S + M1 | **Ground Smash** | Flat on the ground next to you | 1.0 s | No | Ground AoE / slow-startup ability |

- After any finisher: **1.5 s end lag**. No M1, but **dash and abilities can be used**. This is the combo-extension window.
- Ground Smash and Downslam can't be ragdoll cancelled, so their damage is a bit lower than Knockback.

## Abilities as combo extenders
Every ability in [[11 Abilities]] gets these fields in `Config/Abilities.luau`. The ability team fills them in, and combat reads them.

```lua
Followup = { "Knockback", "GroundSmash", "Downslam" }, -- finishers it combos from
AirUsable = false,
OnHit = "Stun",        -- "Stun" | "Ragdoll" | "Launch" | "Pull" | "None"
GuardBreak = false,
```

- `OnHit = "Stun"` or `"Pull"` → the M1 string can restart. That's how long combos are built: M1×4 → ability → M1×4 → ability.
- `OnHit = "Ragdoll"` or `"Launch"` → the combo ends unless another ability follows.

**Anti-infinite rules**
- Each ability can be used **once per combo** on the same target.
- Damage scaling: −10% per hit after the 8th (min 50%).
- 0.6 s stun immunity after standing up from ragdoll.
- A combo ends when the target hasn't been hit for 1.6 s.

## Contract between combat and abilities
Abilities **never** deal damage, stun or ragdoll directly. They call one function:

```lua
CombatService.ApplyHit(attacker: Player, target: Model, hit: {
    damage: number,
    stun: number?,        -- seconds of hitstun
    ragdoll: number?,     -- seconds of ragdoll
    launch: Vector3?,     -- velocity, relative to attacker facing
    guardBreak: boolean?, -- ignores block
    abilityId: string,
})
```

That way every ability automatically respects block, i-frames, stun immunity, combo scaling and once-per-combo. Until it's built, the ability team can keep using `CombatService.DealDamage`.

## Fighter states
Code: `StateService.luau`. One state per fighter, timers as timestamps, one Heartbeat loop.

| State | M1 | Block | Dash | Ability |
|---|---|---|---|---|
| Idle | ✅ | ✅ | ✅ | ✅ |
| Attacking | next hit | ❌ | ✅ | ✅ |
| EndLag (after finisher) | ❌ | ✅ | ✅ | ✅ ← extension |
| Blocking | ❌ | — | ❌ | ❌ |
| Stunned | ❌ | ❌ | ❌ | ❌ |
| Airborne | air M1 | ❌ | ❌ | `AirUsable` only |
| Ragdolled | ❌ | ❌ | cancel only | ❌ |
| GuardBroken | ❌ | ❌ | ❌ | ❌ |

In Studio, each fighter shows its state as yellow text over its head (`DebugStateLabels`).

## Build order
- [x] 1. `StateService` + `Combat.luau` synced to the PDF, debug state labels
- [x] 2. M1 string: hitbox, damage, hitstun (test that the stunned player can't hit back)
- [x] 3. `ApplyHit` API, then hand it to the ability team (`CombatService.ApplyHit`, `CombatService.CanAbilityHit`)
- [ ] 4. Finishers: Knockback + ragdoll, Ground Smash, Downslam ✅ (2026-11-08; real ragdoll physics still to do)
- [ ] 5. Block + guard meter
- [ ] 6. Dash + dash cancel, ragdoll cancel
- [ ] 7. Air M1s + Downslam ✅ (2026-11-07), wall combo

### Downslam = M1 ×3, jump, M1 (2026-11-08)
- Changed to match the reference recording (2026-11-04): hit 4 thrown **in the air** is the Downslam. The target is hammered into the ground and lies down 1 s (KnockedDown); you drop back to the ground.
- The client says "in the air" (Humanoid.FloorMaterial = Air); the server checks at the hit frame that your root really is ≥ 1 stud above standing height (raycast that ignores fighters). If not, it's a normal Knockback.
- While you're high enough, you hang during the 0.25 s wind-up so the slam lands from the air.
- Hitbox: 7 wide, 12 tall, shifted 3 studs down (the target stands below a jumping attacker).
- Numbers: `Combat.luau` → `Finishers.Downslam` and `Downslam`.
- **Removed (2026-11-08):** the Uppercut → air combo (Space + M1 on hit 4). Space + M1 now just jumps, so hit 4 becomes the Downslam. The Uppercut and Launched animations are still in `CombatKeyframes` if it comes back.
- Fighters don't collide with each other (collision group `Fighters`, set in `StateService`), so the attacker never gets pushed off the target. Ground M1 hitbox: 6 wide / 7 reach (was 5 / 6).
- Crater / rubble VFX on the Downslam is for the VFX team.

### M1 timing (2026-11-08)
- **Hit 4 window: 0.9 s after hit 3** (`M1.FinisherWindow`), so there's time to jump for the Downslam. Hits 1→2→3 keep 0.55 s.
- **Input buffer:** a click up to 0.2 s too early is thrown as soon as it's allowed instead of being ignored.
- **Server slack (0.1 s)** on the 0.3 s swing gap and on the windows, so network jitter never makes the server skip a hit the client already played (that put them on different hits of the string).
- **Whiff punish** is now a visible `EndLag` state (0.2 s) instead of a hidden server delay, for the same reason.
- Downslam: in the air but falling and below 1 stud → the client throws a normal Knockback, same as the server decides. Hang through the wind-up is 0.4 s.

### No stun-lock from restarting the string (2026-11-07)
- Problem: M1, pause, M1, pause… restarted at hit 1 every time, and each hit 1 stunned again, so a dummy could be stunned forever.
- Rule: if the string is dropped before hit 4, hit 1 can only start again **1 s after your last swing** (`M1.RestartDelay`). Hitstun is 0.45 s, so the target always gets at least 0.55 s to act. Checked on the server; the client mirrors it so no swing animation plays.

### Hit reactions (2026-11-07)
Played on whoever gets hit, by every client (`ReactionController`), from the `Reaction` / `ReactionHit` attributes the server sets in `ApplyHit`. Made in Blender like the punches (`build_combat_anims.py`, previews in `assets/animations/previews/`).
| Hit | Reaction | Animation |
|---|---|---|
| Ground M1 (stun) | Stun | **Stunned** dazed loop (hunched, head drooping, arms limp) + **Flinch** jolt (head snaps back) on every hit |
| Hits with `hang` or an upward launch (abilities) | Air | **Launched** loop: tipped back, face to the sky, arms out, legs dangling |
| Downslam, Knockback, Ground Smash (ragdoll) | Down | **KnockedDown** loop: flat on the back, face up, arms out, one knee up |
- When the stun/ragdoll ends, the loop fades out over 0.3 s (getting up).
- Real physics ragdoll is still to do; KnockedDown is an animation with the HumanoidRootPart upright.

### Smoother punches (2026-11-07)
- Keyframes exported at 60 per second instead of 30 (Roblox blends linearly between keys, so the 0.12 s strike had only ~4).
- 0.06 s crossfade between punches, and the last 0.12 s of every move blends back to idle instead of snapping.
- The forward step on hits 1–3 is done by your own client at the swing, easing out over 0.2 s. It used to be a server push that arrived late and jerked.
- [ ] 8. Combo extension: `Followup` / `OnHit` tags, once-per-combo, scaling
- [ ] 9. Animations, VFX hookup, HUD, then a lag playtest with 8+ players

## Open questions
- Should the ability team design each ability for a specific finisher, or should most abilities work after any finisher?
- Ground Smash input: S + M1 clashes with "early downslam" (S + M1 in the air). That's fine because one is on the ground and one is in the air, but it needs checking in playtests.

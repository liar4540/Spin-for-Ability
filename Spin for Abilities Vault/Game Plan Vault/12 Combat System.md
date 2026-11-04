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
| Space + M1 | **Uppercut** | ~14 studs up, no pushback | — (air hitstun) | No | Air M1s → Downslam, or `AirUsable` ability |
| S + M1 | **Ground Smash** | Flat on the ground next to you | 1.0 s | No | Ground AoE / slow-startup ability |

- After any finisher: **1.5 s end lag**. No M1, but **dash and abilities can be used**. This is the combo-extension window.
- Ground Smash and Uppercut can't be ragdoll cancelled, so their damage is a bit lower than Knockback.

## Abilities as combo extenders
Every ability in [[11 Abilities]] gets these fields in `Config/Abilities.luau`. The ability team fills them in, and combat reads them.

```lua
Followup = { "Knockback", "Uppercut", "GroundSmash" }, -- finishers it combos from
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
- [ ] 4. Finishers: Knockback + ragdoll, Ground Smash, Uppercut
- [ ] 5. Block + guard meter
- [ ] 6. Dash + dash cancel, ragdoll cancel
- [ ] 7. Air M1s + Downslam, wall combo
- [ ] 8. Combo extension: `Followup` / `OnHit` tags, once-per-combo, scaling
- [ ] 9. Animations, VFX hookup, HUD, then a lag playtest with 8+ players

## Open questions
- Should the ability team design each ability for a specific finisher, or should most abilities work after any finisher?
- Ground Smash input: S + M1 clashes with "early downslam" (S + M1 in the air). That's fine because one is on the ground and one is in the air, but it needs checking in playtests.

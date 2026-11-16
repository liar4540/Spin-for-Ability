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
- [ ] 4. Finishers: Knockback + ragdoll, Ground Smash, Uppercut
- [ ] 5. Block + guard meter
- [ ] 6. Dash + dash cancel, ragdoll cancel
- [ ] 7. Air M1s + Downslam, wall combo
- [ ] 8. Combo extension: `Followup` / `OnHit` tags, once-per-combo, scaling
- [ ] 9. Animations, VFX hookup, HUD, then a lag playtest with 8+ players

### Combat pass (2026-11-16)
Code is the source of truth; this is what changed and why.

**M1 timing and client/server agreement**
- Every swing has a **sequence number**; the server answers each one (`CombatResult`). Rejected → the client cuts the animation and goes back to the server's hit, so it can't stay on the wrong hit of the string.
- Every swing has a server **attack id**. Getting stunned, ragdolled or guard broken, dying, respawning or dash-cancelling the startup cancels it, so the scheduled hit never lands.
- Per-move timing in `Combat.M1.Moves` (startup = the animation's hit frame). Hit 4 now lands at **0.20 s** like its animation (it used 0.12).
- **Active frames** (0.06 s): the server keeps looking for a target for a few frames, so someone walking into the punch still gets hit.
- **Whiff:** no longer a state. The next swing just comes 0.2 s later; the client predicts it with the same box, and the server corrects it if they disagree.
- Finisher end lag is an **M1 lock** (1.5 s) that survives dashing and abilities; the state shows `EndLag` after the hit frame.
- No ability can start during an M1's startup or active frames (no overlapping attacks). A dash during startup cancels the punch.
- The punch goes where the camera looks (the body turns to it); the server limits it to 100° from the body's facing.
- M1s don't hit ragdolled bodies; abilities do.
- Stunned / blocking / ragdolled players can't jump.

**Physics ragdoll** (`RagdollService`)
- BallSocketConstraints with joint limits, built once per character, switched on/off by the `Ragdolled` state only.
- While ragdolled the **server owns** the body (the victim can't walk out); ownership goes back to the player on stand-up, only if alive and still in the game.
- Stand-up: upright on the ground under the body; if that's inside a wall, it moves back towards where the ragdoll started. All velocities zeroed (no fling). Launch speeds capped at 120.
- Knockback launch changed to `(0, 30, −50)` as a one-shot velocity (≈ 18 studs). KnockedDown animation only plays if the physics ragdoll is off (`Combat.Ragdoll.UsePhysics = false`).

**Block, dash, ragdoll cancel** (numbers from the PDF)
- F: front 120° cone after a 0.1 s startup, 30% damage, no stun. Guard 6 (M1 1, finisher 2, skill 2), regen 1/s after 1.5 s, break = 1.5 s stagger + 3 s no block. Downslam goes through block.
- Q: direction from movement relative to the camera. Front 30 studs / 2.5 s; side 14 / back 16 sharing 2 s. Front → side cancel. Stops 2 studs before walls. Side 0.2 s and back 0.1 s i-frames (from the PDF, so they're kept).
- Q while ragdolled: only Knockback (and abilities that allow it), 0.25 s after the ragdoll starts, 20 s cooldown (kept through respawns), 0.4 s i-frames, 10-stud back dash.

**Abilities through one pipeline**
- `AbilityService` now calls `CombatService.BeginCast` (state, `AirUsable`), checks the cast wasn't interrupted after the wind-up, then `CombatService.AbilityHit`, which builds the hit from `OnHit` / `GuardBreak` / `Stun` and goes through `ApplyHit`. `DealDamage` still exists but goes through `ApplyHit` too.
- **Once per combo** is per attacker + ability and stores the cast id: every hit of the same cast lands (multi-hit abilities), a second cast in the same combo doesn't.
- `Followup` is design info only. It never makes a hit land.
- An ability's stun stands a ragdolled target back up (M1×4 → ability → M1×4). M1s can't.
- Pebble Toss and Gale Step were marked `AirUsable = true` so they keep working in the air. Ability team: decide.

**Anti-infinite**
- Damage scaling and the restart delay don't stop a stun-lock when **two attackers take turns** (each one's restart delay is separate). So: `ComboExtension.MaxControlSeconds = 5`. After 5 s of being stunned / ragdolled / guard broken without a 0.6 s break, hits still deal damage but can't stun or ragdoll, and the target gets 1 s of stun immunity once free.
- **Stun immunity ≠ invulnerability.** Standing up from a ragdoll gives 0.6 s of stun immunity (hits still hurt). Only dash/cancel i-frames and the 2 s spawn shield block damage.
- Conflicts with older notes: 07 Tech Plan / 03 Systems say "hitstun decay, ~3–4 s combo cap, 0.5–1 s get-up invulnerability". This note's rules (0.6 s stun immunity, no hitstun decay) win; the 5 s control cap covers the "combo cap" idea.

**Other**
- KO credit: last player to hit within 5 s gets the KO (KOs / Deaths saved, `KillFeed` fired). Yen rewards still to do.
- `SafeZone`-tagged parts: nobody inside can hit or be hit (dummies can).
- Mobile: HIT / BLOCK / DASH buttons above the hotbar (touch-only devices).
- Block pose is a hand-written placeholder (`client/Animations/BlockKeyframes.luau`); make the real one in Blender and upload it (`Combat.Animation.Ids.Block`).

### Studio test checklist (combat pass)
Test → Clients and Servers, 2 players, then again with **Network Simulation** set to 100 ms and 250 ms.
- [ ] Spam M1 on a dummy: never more than one queued swing; the debug label and the animation agree on the hit.
- [ ] M1 at nothing: the next click comes slightly later (whiff); no animation that then gets cut.
- [ ] Hit 4 normal / S + M1 / jump + M1: Knockback flies ~18 studs, Ground Smash and Downslam drop flat; all three ragdoll with physics.
- [ ] Ragdoll into a wall and on a slope: stands up upright, not inside the wall, no fling.
- [ ] Get hit during your wind-up: your punch doesn't land.
- [ ] Die mid-wind-up and while ragdolled; respawn: no errors, new character moves normally.
- [ ] Both players M1 each other at the same moment (trades).
- [ ] Block from the front (blue flash, 30% damage) vs from behind (full hit). 6 blocked M1s → guard break.
- [ ] Q in all four directions, into walls, front → side cancel. Q while ragdolled after a Knockback (works) and after a Ground Smash (doesn't).
- [ ] M1×4 → dash → Ember Fist → M1 string again. Ember Fist twice in one combo: the second does nothing.
- [ ] Two attackers alternating M1s on one player: after 5 s the label shows `(cap)` and the victim breaks free.
- [ ] Remote spam (autoclicker): no errors, no extra hits.

### 8-player playtest checklist
- [ ] 100 and 250 ms: do strings still feel connected? Retune `Hitstun`, `ServerTolerance`, `Active`.
- [ ] Several ragdolls at once: server frame rate (MicroProfiler), anyone stuck or flung.
- [ ] Phones: buttons reachable, block hold works, ragdoll cost OK.
- [ ] Spawn shield / safe zone: no spawn kills.
- [ ] KO credit goes to the right player (including edge knock-offs within 5 s).

## Open questions
- Should the ability team design each ability for a specific finisher, or should most abilities work after any finisher?
- Ground Smash input: S + M1 clashes with "early downslam" (S + M1 in the air). That's fine because one is on the ground and one is in the air, but it needs checking in playtests.

---
epoch: 1793763226569
mode: agent
backendId: claude
sessionId: "5cd453f0-b6c8-4d1d-9ffc-bf655be78abc"
topic: "I have 3 person in my team, 2 of them will focus on ability…"
tags:
  - copilot-conversation
usage: '{"usedTokens":75203,"contextWindow":1000000,"inputTokens":2,"outputTokens":3,"cacheReadTokens":73037,"cacheWriteTokens":2161,"updatedAt":1793763663465}'
---

**user**: I have 3 person in my team, 2 of them will focus on ability design and vfx. I will be doing the Combat system. The combat system will be like roblox game strongest battleground. Can M1 4 times and the last M1 will be ragdoll the opponent. It can be upper cut, ground smash or normal knock back. The concept is the player able to use ablity they spin to combo extension
[Timestamp: 2026/11/04 11:33:46]

**ai**: Your Core Combat PDF already covers most of this: the 4-hit M1 string, uppercut into an air combo, block, dash and ragdoll cancel. Two of your ideas aren't in it yet: **3 finisher types** and **abilities as combo extenders**. Here's how I'd add them, plus how to split the work so your two teammates aren't blocked waiting on you.

## 1. Three finishers on hit 4

The direction key you hold when hit 4 lands picks the finisher:

| Input on hit 4 | Finisher | Effect on target | Best follow-up |
|---|---|---|---|
| M1 only | **Knockback** | Flies ~18 studs, ragdoll 1.2 s | Dash in, or a ranged/dash ability |
| Space + M1 | **Uppercut** | Launched ~14 studs up, no pushback | Air M1s or `AirUsable` ability |
| S + M1 | **Ground Smash** | Slammed flat in place, knocked down 1.0 s, can't ragdoll cancel | Ground AoE / slow startup ability |

Each finisher leaves the enemy in a different position: far away, in the air, or on the ground next to you. Which one you pick decides which of your rolled abilities can follow up. That fits the spin concept well.

## 2. Abilities extend the combo

- After hit 4 there's 1.5 s of end lag. You can't M1 during it, but **you can use abilities**. That's where the combo continues.
- Each ability gets a **follow-up tag** in its config. The ability team fills these in and your system reads them:
  ```lua
  Followup = { "Knockback", "Uppercut", "GroundSmash" }, -- which finishers it can follow
  AirUsable = true,
  OnHit = "Ragdoll" | "Stun" | "Launch" | "Pull",       -- what state it leaves the target in
  ```
- An ability that ends in `Stun` or `Pull` can restart the M1 string, which opens up longer combos.
- Two anti-infinite rules: damage drops after the 8th hit (already in the PDF), and **each ability can only be used once per combo**.

## 3. Work split

**You (combat):**
- The state machine (Idle, Attacking, Stunned, Ragdolled, Airborne…)
- Hitboxes
- Hitstun and ragdoll
- The 3 finishers
- One API the abilities call: `CombatService.ApplyHit(attacker, target, {damage, stun, ragdoll, launch, guardBreak})`

**Teammates (abilities and VFX):** they only ever call `ApplyHit`, never handle damage or stun themselves. That way every ability gets the same block, i-frame and stun-immunity rules for free.

Agree on that `ApplyHit` signature this week. After that, they can build abilities against a stub while you build the real system.

## Where the code is now

- `Game/src/shared/Config/Combat.luau` has different numbers from the PDF. For example, the M1 hits do 4/4/4/6 damage instead of 3/3/3/5, block breaks after 4 hits instead of 6, and ragdoll lasts 1.5 s instead of 1.2 s. These should be made to match.
- `CombatService` only has a `DealDamage` function so far. The state machine, M1 string and ragdoll aren't built yet.

**Next step:** I can add the finisher and combo-extension sections to the design notes in your vault, or start the code with build-order step 1: the state service, synced config and debug state text over each player's head. Which would you like?
[Timestamp: 2026/11/04 11:33:46]

**user**: do both
[Timestamp: 2026/11/04 11:37:11]

**ai**: Nothing reads the combat config yet, so I can safely rewrite it to match the PDF.The require path matches what the other services use. Now the vault note:I did both: there's a new design note in the vault, and step 1 of the combat build order is written. I haven't run any of the code in Studio yet, so it's untested.

**Design note: [[12 Combat System]]**
- **3 finishers on hit 4:** Knockback (M1), Uppercut (Space + M1) and Ground Smash (S + M1). Each one leaves the enemy in a different spot, and your rolled abilities decide the follow-up.
- **Combo extension:** after a finisher there's 1.5 s where you can't M1 but can use abilities. Each ability gets new fields (`Followup`, `AirUsable`, `OnHit`, `GuardBreak`) for your teammates to fill in. An ability that ends in `Stun` or `Pull` lets you start the 4-hit string again.
- **Handoff to your teammates:** abilities only ever call `CombatService.ApplyHit(...)`, so block, i-frames, damage scaling and the once-per-combo rule apply to them automatically.
- It also has a state table, the build order as a checklist, and 2 open questions for the team.

**Code:**
- `Game/src/shared/Config/Combat.luau`: I rewrote it to use the PDF's numbers and added settings for the finishers, air combo, combo extension, dash and ragdoll cancel. Nothing was reading this file yet, so nothing else breaks.
- `Game/src/server/Services/StateService.luau` (new): it gives every player and training dummy one combat state, and one loop ends timed states like stun or ragdoll. It also checks what each state allows (M1, block, dash, ability), keeps damage scaling and once-per-combo tracking on the target, and shows each fighter's state as yellow text over their head in Studio.
- `Game/src/server/init.server.luau`: `StateService` now starts before `CombatService`.

**Not done yet:**
- `ApplyHit` isn't written. Your teammates should keep using `DealDamage` until it is.
- No code reads the new `Followup` / `OnHit` fields yet.
- Nothing calls `StateService` yet, so every fighter will show "Idle" until the M1 string (step 2) changes states.

To check it, press Play in Studio. You should see "Idle" over your character and over any training dummy.

Next is step 2, the M1 string with its hitbox and hitstun, then `ApplyHit` so your teammates can start using it.
[Timestamp: 2026/11/04 11:37:11]
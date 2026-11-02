# Systems

| System | Purpose | Priority (MVP / Later) | Status |
|---|---|---|---|
| Spin / RNG Roll | Roll for random abilities by rarity, the main hook | MVP | ⬜ |
| Abilities & Equip | Store abilities, equip 2–3 at once for combo builds | MVP | ⬜ |
| Combat / Battlegrounds | Battlegrounds PvP: shared M1 / block / dash moveset + your rolled abilities, fight players and dummies | MVP | ⬜ |
| Currency & Economy | Yen (from fighting) + Shards (from skipped spins) | MVP | ⬜ |
| Shards & Ability Upgrades | Skipped spins give Shards; Shards + yen level abilities up (1–10) | MVP (levels) / Later (Awakening) | ⬜ |
| KO Streak Luck | 3+ KOs in a row in the arena = +0.5x luck at the arena spin machine | MVP | ⬜ |
| Saving (DataStore) | Save abilities, currency, stats | MVP | ⬜ |
| Luck Potions | Temporary boost to rare roll chances | MVP | ⬜ |
| New Player Tutorial | First spin, dummy, free potion, arrow to the Battlegrounds | MVP | ⬜ |
| Playtime Rewards | Potions/yen at 5/10/15/20 min | MVP | ⬜ |
| Monetization | Game passes + dev products | MVP | ⬜ |
| Odds & Policy check | Odds shown for every ability; paid luck blocked where a country restricts it | MVP (required before selling any luck) | ⬜ |
| Areas / Zones | Areas unlock by total spins and give a luck bonus | MVP (Area 1 + VIP Area) / Later (Areas 2–4) | ⬜ |
| Events / Biomes | Server-clock events that boost some abilities ("⚡ Storm: Thunder abilities x3") | Later (first post-launch update) | ⬜ |
| Awakening / Titles | Awaken max-level abilities, show-off titles | Later | ⬜ |
| Quests | Daily/session goals for rewards | Later | ⬜ |
| Daily Login Rewards | 7-day streak rewards | Later | ⬜ |
| Collection Index | Every ability you've **ever rolled** (kept or skipped) vs. still "???" | MVP (simple grid) / Later (completion rewards) | ⬜ |
| Leaderboards | Most KOs, rarest ability, most spins, longest KO streak, highest ability level | Later | ⬜ |
| Group Rewards | Free luck potion for joining the Roblox group | Later | ⬜ |
| Trading | Swap abilities with players | Later (maybe never) | ⬜ |

> **MVP = the smallest version people can actually play.** Build the MVP first, release it, then add the "Later" systems as updates.

## Notes per system

### Spin / RNG Roll
- **Spinning is free and unlimited.** No spin currency. Stand at a spin machine and press SPIN, one spin at a time. *(LIHFOLK: Teardown - Sol's RNG)*
  - **Speed:** the next spin is ready ~1 s after the reveal ends, so a Common takes about 2.5 s → **~24 spins a minute**. Quick Spin pass: ~1 s per spin below Legendary.
  - ✅ **Decided: 9 rarities.** Uncommon, Ascended and Divine were added, so there's always a next goal. Ascended fills the old gap between Legendary (~4 min) and Mythic (~7 h).
  - **Average time of spinning to get each rarity** (24 spins/min, 1x luck): Epic ~1 min · Legendary ~4 min · Ascended ~42 min · Mythic ~7 h · Divine ~35 h · Secret ~174 h. At max luck (5x) everything Epic+ is about 5x faster.
    Ascended is the "this session" goal, Mythic a multi-session goal, and Divine/Secret are weeks-long chases, like the top of an RNG game.
- **How the roll works:** check from rarest down (Secret first). Each tier has a "1 in N" check; the first one that hits wins. If none hit, it's Common.
- **Real odds:** because the checks run rarest-first, the real chances are *lower* than the "1 in N" labels for the common tiers. **Show these real numbers, not the labels.** *(LIHFOLK: Genre Playbook - RNG and Collection Games, §3)*
  | Rarity | Check | Luck? | Real chance at 1x | Real chance at 2x | Real chance at 5x (max) | Power (x1.35 per tier) |
  |---|---|---|---|---|---|---|
  | Common | fallback | – | 55.3777% | 52.4751% | 44.0843% | x1.00 |
  | Uncommon | 1 in 3 | no | 27.6888% | 26.2376% | 22.0422% | x1.35 |
  | Rare | 1 in 8 | no | 11.8666% | 11.2447% | 9.4466% | x1.82 |
  | Epic | 1 in 25 | yes | 3.9555% | 7.8224% | 18.8933% | x2.46 |
  | Legendary | 1 in 100 | yes | 0.9989% | 1.9955% | 4.9719% | x3.32 |
  | Ascended | 1 in 1,000 | yes | 0.09999% | 0.1999% | 0.4997% | x4.48 |
  | Mythic | 1 in 10,000 | yes | 0.01000% | 0.01999% | 0.04999% | x6.05 |
  | Divine | 1 in 50,000 | yes | 0.002000% | 0.004000% | 0.01000% | x8.17 |
  | Secret | 1 in 250,000 | yes | 0.0004000% | 0.0008000% | 0.002000% | x11.03 |
  - Odds per ability = tier chance ÷ number of abilities in that tier. The Odds screen lists **every ability**, not just the tiers (Roblox rule for paid random items, see [[04 Monetization]]).
  - Never type these numbers by hand. One shared `Odds` module computes them from `Rarities.luau`, and both the server roll and the Odds screen call it.
- **Luck (one definition, used everywhere):**
  - Luck boosts **Epic and rarer only** (their "1 in N" becomes "luck in N"). Common, Uncommon and Rare are not boosted, so a lot of luck can never make Common disappear.
  - Luck sources **add up** instead of multiplying: `luck = 1 + bonuses`. Example: x2 Luck pass (+1) + Luck Potion (+1) + Area 2 (+0.2) = **3.2x**. KO streak luck (+0.5) only counts at the arena spin machine.
  - **Cap: 5x total.** Without a cap, multiplying could reach 30x, which made Rare+ guaranteed. *(LIHFOLK: RNG Drops and Luck Systems, §3)*
  - The HUD 🍀 shows the exact luck the next spin will use, including the cap.
- **Reveal animation:** rarer rolls get longer and flashier reveals, plus a server-wide announcement for Mythic, Divine and Secret. The server rolls **first**, and the animation lands on that result.
- **Pity (two counters, both saved):**
  - **Epic pity:** guaranteed Epic+ after 50 spins without one. Real effect: Epic+ goes from 5.07% to about **5.47% over the long run** (~7.8% of 50-spin streaks reach it).
  - **Legendary pity** ✅: guaranteed **Legendary+** after **300 spins** without one (~12.5 min of spinning). Legendary+ goes from 1.111% to about **1.152%**; it rescues the unluckiest ~3.5% of players. (500 spins would almost never trigger, 0.4%.)
  - If both are due on the same spin, Legendary+ wins. A Legendary+ result resets **both** counters; an Epic resets only the Epic one. The counter is saved and shown ("Epic+ guaranteed in 23 spins"), and on the guaranteed spin the Odds screen shows Epic+ only.
- **First spin:** the very first spin is guaranteed Rare+ (matches the tutorial; set in `Rarities.luau`). The Odds screen shows "Next spin: Rare+ guaranteed" while it applies.
  - ⚠️ LIHFOLK warns a guaranteed great first roll "teaches the wrong odds" (one measured project removed it after playtesting). Keep it for now; check in [[10 Playtest Log]] whether new players expect every spin to be good.
- ⚠️ **Rolls happen on the server** with a server `Random.new()` object, so exploiters can't fake them.
- **Test:** simulate 1,000,000 rolls at 1x, 2x and 5x and check the results match the table above.

### Ability power by rarity
- ✅ **Decided: each rarity is x1.35 stronger than the one below** (Secret ≈ 11x Common). The multiplier scales the ability's **damage / healing / shield strength**, not cooldowns or range.
- Rarer abilities also look bigger and flashier, and get unique effects (pull, freeze, teleport).
- ⚠️ **Watch in playtests:** at x1.35 per tier a Mythic+ owner can beat new players easily. Keep these in mind if it feels unfair:
  - M1 / block / dash are the same for everyone, so skill still matters at close range.
  - Bounties on top players (Later) and KO streaks ending on death give everyone a reason to chase the strongest player.
  - The multiplier lives in `Rarities.luau`, so it can be lowered (e.g. to x1.25) without touching any ability.
- Ability design itself (which abilities, how many per tier) is planned later.

### Shards & Ability Upgrades
- ✅ **Decided:** every **skipped** spin result (Skip button, spinning again, or Auto Spin skipping it) turns into **Shards**. No spin is wasted. *(LIHFOLK: Teardown - Sol's RNG, "make every roll useful")*
  | Rarity skipped | Shards |
  |---|---|
  | Common | 1 |
  | Uncommon | 2 |
  | Rare | 4 |
  | Epic | 10 |
  | Legendary | 30 |
  | Ascended | 100 |
  | Mythic | 500 |
  | Divine | 2,000 |
  | Secret | 10,000 |
  - About **2.5 Shards per spin** at 1x luck → ~60 a minute of spinning.
- ✅ **Levels belong to the ability type**, not the copy: level Thunder Lance to 7 and every Thunder Lance you own or roll later is level 7. Duplicates never feel bad, and deleting or replacing a copy never loses levels. You need to own at least one copy to upgrade it.
- **Upgrading:** Shards + yen level an ability from **1 to 10**. Each level = **+4% power**, so a level-10 ability is **+36%**, about one rarity tier higher.
  | Level up | Shards | Yen |
  |---|---|---|
  | 1 → 2 | 25 | 100 |
  | 2 → 3 | 100 | 200 |
  | n → n+1 | 25 × n² | 100 × n |
  | 9 → 10 | 2,025 | 900 |
  | **Total 1 → 10** | **7,125** (~2 h of spinning) | **4,500** (~180 KOs) |
  - Needing both Shards (spinning) and yen (fighting) ties the two halves of the game together, and gives yen its second use.
- **Locked** abilities can't be skipped, so they never turn into Shards by accident.
- **Later:** Awakening at level 10 (a new VFX or an extra effect), and buying a specific ability's upgrade with Shards of its own rarity.
- Shards are **not sold for Robux** (keeps upgrades earned, and keeps them out of paid random item rules).

### Abilities & Equip
- Each ability has: name, rarity, level (1–10), damage, cooldown, range, VFX, and a type (melee / projectile / AoE / movement / defense).
- **Equip slots:** 2 free, plus a 3rd unlocked free at 100 KOs (or right away with the +1 Equip Slot game pass).
- **Storage:** keep up to 15 abilities (25 with the +10 Storage pass, Later), so new spins don't replace the ones they like.
- **Keeping results:** a spin result is **not** stored automatically (you'd fill 15 slots in a minute). After each spin you pick **Equip**, **Keep** or **Skip**. Pressing SPIN again skips the last result.
  - **Safety for rare rolls:** you can't spin again while an **Epic+** result is still waiting for a choice. If you leave with one waiting, it's kept automatically when there's room.
  - **Full storage:** you can still spin. Keep asks which ability to replace.
  - **Auto Spin** keeps results at or above your chosen rarity (default Epic+) and skips the rest. It stops with "Storage full" when there's no room.
- Start small: **10–15 abilities for MVP**, and add more in updates.
- ✅ **Index:** every ability you roll is recorded in the **Index** even if you skip it, so kids can complete the collection without hoarding storage.

### Combat / Battlegrounds
PvP works like a Roblox **battlegrounds** game: one open arena, drop in anytime, no rounds, respawn in seconds. Everyone shares the same basic moveset, and the abilities you roll are your special moves on top. *(Source: LIHFOLK "Genre Playbook - Battlegrounds and Arena Fighters".)*

- **Safe zone:** spawn and spin area, no damage.
- **Battlegrounds arena:** step in and you can fight. Aim for **10–20 players per server** (fewer and fights are hard to find, more and duels turn into chaos and lag).
- **Basic moveset (everyone has it):**
  | Move | Rule of thumb |
  |---|---|
  | **M1 combo** | 4 hits; the 4th knocks back / ragdolls; short end lag after the chain |
  | **Block** | Hold to take much less damage; breaks after a few hits or a heavy attack (**guard break**) |
  | **Dash** | Short burst, 1.5–3 s cooldown; side dash and forward dash |
  | **Abilities 1/2/3** | Your rolled abilities (2 slots, 3rd at 100 KOs / pass). Cooldowns ~5–25 s |
  | **Ultimate** *(Later)* | Charges from dealing and taking damage; a powered-up mode for 30–60 s |
- **No infinite combos:** hitstun gets shorter with each hit, combos are capped at ~3–4 s, and after a ragdoll you get 0.5–1 s of get-up invulnerability. *(Later: a combo breaker on a long cooldown.)*
- **Ragdolls:** keep them short (1–2 s) and simpler in Low VFX mode. They're expensive on phones.
- **Respawn:** 2–5 s, then a **2 s spawn shield**. Several spawn points so nobody gets spawn-camped.
- **KO credit:** whoever did the last damage within the last few seconds gets the KO (so knocking someone off an edge still counts).
- **Newcomers:** training dummies near spawn (with a combo counter). Bounties on top players *(Later)* so the strong players get chased instead of the new ones. Don't scale damage for weak players; it feels unfair.
- Controls: M1 = click / tap, block = F / button, dash = Q / button, abilities = 1/2/3 on PC, buttons on mobile. **Abilities aim softly at the nearest enemy in front** on mobile, and shift-lock camera is on by default on touch.
- **Dying doesn't lose abilities.** You just respawn.
- KO reward: Yen. **Kill feed** shows KOs and streaks.
- **KO Streak Luck** ✅ **Decided:**
  - **3 KOs in a row** without dying = **🔥 ON A STREAK**: +0.5x luck (shown as "1.5x") for as long as the streak lasts.
  - The streak **ends** when someone KOs you **or you leave the Battlegrounds arena** (no hiding in the safe zone with it).
  - It only boosts spins at the **Arena Spin Machine**, which stands *inside* the arena. Spinning with your streak means standing where others can hunt you.
  - Everyone sees the streak: a 🔥 flame above your head and "PlayerA is on a 5 KO streak!" in the kill feed. Ending someone's streak pays bonus yen (**+25 ¥ per streak KO**, so ending a 6-streak pays +150 ¥).
  - The bonus is flat +0.5x (doesn't grow with longer streaks) and counts toward the 5x cap. It's free luck, so it's fine for restricted players too.
- **Repeat KOs on the same player** ✅ (stops friends farming each other): allowed, but the rewards shrink, and the count **resets every day** (00:00 UTC). It's saved, so rejoining doesn't reset it.
  | KO on the same player today | Yen | Counts toward your streak? |
  |---|---|---|
  | 1st | 100% (25 ¥) | yes |
  | 2nd | 50% (12 ¥) | yes |
  | 3rd | 25% (6 ¥) | yes |
  | 4th and later | 10% (2 ¥) | no |
  - The streak-ending bonus shrinks the same way, so you can't farm it by letting a friend end your streak again and again.
- ⚠️ **Server-authoritative combat:** the attacker's client plays the animation and VFX instantly, but the **server** decides every hit. It checks the attacker is alive and not stunned, the move is off cooldown (server clock), the target is in range plus a small lag margin, and the move didn't hit more targets than it's allowed. Each fighter has a state on the server (idle / attacking / blocking / stunned / ragdolled / dashing) and illegal moves get rejected.
- **Every move is data:** damage, cooldown, hitbox size, stun time and knockback live in a config file, not in scripts.
- **Test with lag:** two clients with simulated latency (100 ms and 250 ms) for every combo before shipping.

### Economy
- **Currencies:** **Yen** (from fighting) and **Shards** (from skipped spins). Spinning is free, so there's no spin currency.
- **Sources (how you earn):**
  - KOs in the Battlegrounds (the main source)
  - Playtime rewards
  - VIP Area yen spawns
  - Quests and daily login (Later)
  - Robux purchases
- **Sinks (how you spend):**
  - Buying luck potions
  - Upgrading abilities (Shards + yen, see Shards & Ability Upgrades)
- **Starting balance idea:** 1 KO = 25 yen, Luck Potion = 100 yen, so 4 KOs = 1 potion (5 min of +1x luck). Adjust this after testing.

### Luck Potions
- Luck Potion: **+1x luck** for 5 minutes (shown as "x2 Luck"). Super Luck Potion (Later): +2x.
- Only one potion runs at a time. Drinking a stronger one pauses the weaker one instead of wasting it. *(LIHFOLK: RNG Drops and Luck Systems)*
- If you're already at the 5x cap, the potion button says "Your luck is already at max" and won't let you drink or buy it.
- Sources: tutorial (1 free), playtime rewards, group reward, codes, yen (100), Robux.
- Timer is shown on screen.

### Saving (DataStore)
- Save: abilities owned (with levels), equipped abilities, yen, Shards, potions, pity counter, stats (KOs, total spins). KO streaks are **not** saved (they end when you leave anyway).
- Use **ProfileStore** for the session lock, so one player in two servers can't duplicate or overwrite data.
- Autosave every few minutes, and also save when the player leaves or the server shuts down.
- Retry if a save fails, so players never lose data. If loading fails, never save default data over the real save.

### Monetization
- **Game passes:** x2 Luck, +1 Equip Slot, Quick Spin, Auto Spin, VIP (cosmetic aura + bonus yen + VIP Area access; no chat tag).
- **Dev products:** luck potions, yen, Server Luck. No spin packs.
- Keep it fair. Everything can be earned for free, just slower.
- **Paid random items:** free spins are exempt from Roblox's paid random item rules. But as soon as **paid luck** is active (x2 Luck pass, a Robux potion, VIP Area, someone's Server Luck), that spin's odds were changed with Robux, so the rules apply. Show full odds per ability everywhere, and block paid luck for players in countries that restrict it. Details in [[04 Monetization]].

### Areas / Zones
- Areas unlock by **total spins** (1,000 / 5,000 / 15,000 / 50,000) and add +0.1x to +0.4x luck while you stand at their spin machine. Full table in [[05 World & Art]].
  - Time of spinning at ~24/min: Area 1 ~40 min (first session) · Area 2 ~3.5 h · Area 3 ~10 h · Area 4 ~35 h. Quick Spin roughly halves these. Re-check after playtesting.
- **VIP Area:** VIP pass only. +0.5x luck at its spin machine, and yen spawns on the ground to collect.
- **Arena Spin Machine:** inside the Battlegrounds arena. No area bonus, but it's the only machine where **KO Streak Luck** counts. Open to everyone.
- ⚠️ **The server decides which machine you're at** and which luck applies, never the client.

### Events / Biomes (Later: first post-launch update)
- ✅ **Decided.** Short events on a **server clock**, so every server agrees without messaging *(LIHFOLK: Teardown - Sol's RNG)*: e.g. "⚡ Storm: Thunder abilities x3 for 10 min", "🌑 Eclipse: Shadow abilities x3".
- During an event, abilities with that element are more likely **within their rarity** (the rarity odds don't change). The Odds screen shows the event's effect live.
- One random event every ~30–60 min, announced 1 min before with a banner. Gives players a reason to stay and come back.
- Needs an **element** on every ability (fire, ice, lightning, shadow, light…), so plan that with the ability design.

### Later
- **Awakening:** level-10 abilities can awaken (new VFX or an extra effect).
- **Player titles:** show-off rewards like "Mythic Hunter", "Streak Breaker".

## Suggested build order
1. Saving (DataStore), so everything else saves from day one
2. Spin system + rarity odds
3. Battlegrounds base combat: M1 combo, block, dash, hitstun, ragdoll, respawn + dummies (this is what makes fights feel good, so build it first)
4. Abilities (start with 3–5) + equip, layered on top of the base combat
5. Yen, KO rewards, KO streak luck + arena spin machine, buying potions with yen
6. Shards from skipping + ability upgrades (levels 1–10)
7. Luck potions + playtime rewards
8. Tutorial / first 5 minutes
9. Monetization
10. Test with friends → **release MVP** 🚀
11. Add "Later" systems as updates

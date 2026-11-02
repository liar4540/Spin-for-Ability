# Roadmap

> Order follows [[03 Systems]] and [[07 Tech Plan]]. Finish each milestone before starting the next. Time estimates assume a few hours a week, so adjust to your pace.

## Milestone 1: Prototype (core loop playable) · ~2–3 weeks
**Goal:** spin → get an ability → hit a dummy or a friend with it. Ugly is fine.
- [ ] Set up folders in `src/` (Rojo) from [[07 Tech Plan]] (Main scripts + empty service modules, delete `Hello.luau`)
- [ ] Rarities config (9 tiers + odds + power x1.35 per tier + Shards per tier) and Abilities config (3–5 abilities)
- [ ] `Odds` module (real % per ability, luck capped at 5x) + million-roll test that matches it
- [ ] `RequestSpin` remote through `RemoteGuard`, server-side roll, basic text result on screen
- [ ] **Battlegrounds base combat first:** M1 combo (4 hits, last knocks back), block + guard break, dash
- [ ] Server fighter states (idle / attacking / blocking / stunned / ragdolled / dashing), hitstun with a combo cap
- [ ] Equip 2 abilities and use them with keys 1/2 on top of the base moveset
- [ ] Server-side damage, cooldowns and range checks (one damage path for M1s and abilities)
- [ ] Training dummy that shows damage numbers and a combo counter
- [ ] Safe zone vs Battlegrounds arena (no damage in safe zone)
- [ ] Respawn (2–5 s) with a 2 s spawn shield, without losing abilities
- [ ] Admin command (only you) to give spins for testing
- [ ] Test with 2 players in Studio with simulated lag (100 ms and 250 ms): do combos still feel fair?

✅ **Done when:** a friend can spin, equip and KO you in a test server.

## Milestone 2: MVP (saving, shop, 1 map) · ~4–6 weeks
**Goal:** everything in the MVP column of [[03 Systems]] works and saves.

**Saving**
- [ ] DataService with ProfileStore (load, autosave, save on leave/shutdown)
- [ ] Check: rejoin keeps yen, spins, abilities, equipped slots (all 3) and the pity counter
- [ ] Check: joining a second server while the first still holds the profile doesn't duplicate or wipe anything

**Spins & abilities**
- [ ] Grow to 10–15 abilities across all rarities
- [ ] Pity (Epic+ after 50, Legendary+ after 300) and guaranteed Rare+ on the first spin
- [ ] Simple Index: every ability ever rolled (kept or skipped) vs "???"
- [ ] Reveal animation that gets bigger with rarity
- [ ] Server-wide announcement for Mythic / Divine / Secret
- [ ] Skipping gives Shards; Upgrade button levels abilities 1–10 with Shards + yen (+4% power per level)
- [ ] Free unlimited spinning with a server cooldown; Keep / Equip / Skip after each spin (Epic+ must be chosen before the next spin)
- [ ] Storage UI: view, equip, delete, 🔒 lock (limit 15; Keep with full storage asks what to replace)
- [ ] 3rd slot unlocks at 100 KOs
- [ ] Honest reveal: strip shows only reachable abilities, no near-misses, glow comes from the result

**Economy**
- [ ] Yen on KO (25 yen per KO)
- [ ] KO streaks: 3+ KOs = 🔥 + +0.5x luck at the Arena Spin Machine; ends on KO or leaving the arena; ending a streak pays bonus yen
- [ ] Repeat KOs on the same player pay 100/50/25/10% (4th+ doesn't count for streaks), reset daily at 00:00 UTC
- [ ] Buy luck potions with yen (100 yen each)
- [ ] Luck potions (+1x for 5 min, on-screen timer, stronger one pauses weaker, blocked at the 5x cap)
- [ ] Playtime rewards at 5 / 10 / 15 / 20 min

**New players**
- [ ] SPIN usable within 5 s of joining + 1 free luck potion
- [ ] Tutorial: spin → try on dummy → arrow to the Battlegrounds → reward for first hit

**Shop** (MVP list from [[04 Monetization]])
- [ ] Game passes: x2 Luck, Quick Spin, Auto Spin, VIP (incl. VIP Area access; no chat tag)
- [ ] Dev products: Luck Potion (1 and 5-pack), 1,000 Yen (one `ProcessReceipt`, `PurchaseId` saved in the profile together with the grant)
- [ ] Prices loaded with `GetProductInfoAsync`, not typed in
- [ ] **Odds screen:** every ability as a %, live with luck/pity, "📊 Odds" on the Spin button and every luck / spin-speed shop card
- [ ] **PolicyService gate:** restricted players can't buy luck (potions, x2 Luck, VIP, Server Luck, yen, x2 Yen), checked on the server; test with the Studio debug switch

**Settings & extras** (step 10 of [[07 Tech Plan]])
- [ ] Settings menu saved with `SaveSettings` (volume, Low VFX, simplify others' VFX, auto-skip, announcements, damage numbers)
- [ ] Redeem codes (`RedeemCode`)

**Map & UI**
- [ ] One map: spawn/spin area, dummy area, Battlegrounds arena (cover, several spawn points)
- [ ] Kill feed (with streaks) + combo counter
- [ ] Arena Spin Machine inside the Battlegrounds arena
- [ ] Area 1: locked gate, unlocks at 1,000 spins, own spin machine with +0.1x luck + unlock popup
- [ ] VIP Area: VIP pass only, spin machine with +0.5x luck, yen spawns
- [ ] HUD: yen, spins, potion timer, shop button
- [ ] Mobile buttons for M1 / block / dash / abilities with soft targeting, test every combo on a phone
- [ ] Every screen checked at 844×390, 667×375, 1920×1080 and a notched phone: no overlaps, taps ≥ 44 px

✅ **Done when:** a new player can play 20 minutes with no bugs and their progress is still there next day.

## Milestone 3: Launch · ~1–2 weeks
- [ ] Playtest with friends, log bugs in [[10 Playtest Log]]
- [ ] Fix every bug that loses data, money or crashes
- [ ] Balance check: is 4 KOs per potion right? Do the top rarities come too fast with free spinning? Do players still fight, or just stand at the machine?
- [ ] Thumbnails & icon
- [ ] Description (pitch from [[01 Concept]] + "odds shown in game")
- [ ] Create the Roblox group
- [ ] Fill in the Maturity & Compliance questionnaire (say the game has **paid random items**) + make the game public
- [ ] Re-check Roblox's paid random items and PolicyService pages (rules in [[04 Monetization]] are as of Oct 2026)
- [ ] Share with friends / Discord / TikTok clip of a Mythic reveal

✅ **Done when:** the game is public and strangers are playing.

## Post-launch updates
Roughly one update every 1–2 weeks, so returning players always see something new.
- [ ] **Update 1:** **Events / Biomes** on a server clock (boost one ability type, e.g. Melee x3) + new abilities + Daily login rewards (7-day streak)
- [ ] **Update 2:** Quests (daily/session goals) + Group join reward
- [ ] **Update 3:** Index completion rewards + Leaderboards (KOs, rarest ability, spins, longest KO streak, highest ability level)
- [ ] **Update 4:** Awakening for level-10 abilities + player titles
- [ ] **Later shop:** +10 Storage, x2 Yen, Super Luck Potion, Server Luck
- [ ] **New areas:** Area 2 (5,000 spins), Area 3 (15,000), Area 4 (50,000), one per update or as big updates
- [ ] **Each update:** 2–5 new abilities, maybe a limited-time one
- [ ] Trading (only if the game is popular and you're ready for scam and dupe protection)

## Tracking goals (from [[01 Concept]])
- [ ] 1,000 visits in first month
- [ ] 50 players at peak
- [ ] 80%+ like ratio
- [ ] 100 Robux earned
- [ ] 100 group members

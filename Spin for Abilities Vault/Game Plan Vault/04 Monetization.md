# Monetization

**Goal:** earn 100 Robux from game passes (from [[01 Concept]]). Players mostly spend Robux on *luck and speed*, not raw PvP power.
- You keep about 70% of each pass sale (Roblox's fee is 30%). So 100 Robux earned is about **143 Robux of sales**, for example one x2 Luck pass.

## Gamepasses
| Name | Price (R$) | Benefit |
|---|---|---|
| x2 Luck | 149 | Permanently **+1x luck** on every spin (1x → 2x). Example on the card: "Mythic: 0.009999% → 0.01999%" |
| Quick Spin | 49 | Faster spinning: reveals below Legendary take 0.5 s instead of 1.5–2 s (about 2x more spins per minute) |
| Auto Spin | 99 | Spins automatically while you stand at a spin machine, keeping only your chosen rarity and up. **Never drinks potions** on its own |
| +1 Equip Slot | 199 | Equip 3 abilities instead of 2 *(see rule below)* |
| +10 Storage | 49 | Hold more abilities in storage |
| VIP | 249 | +20% yen, VIP-only cosmetic aura, **access to the VIP Area** (+0.5x luck at its machine + yen spawns). *No chat tag: LIHFOLK counts visible "paid status" markers as pressure on kids.* |
| x2 Yen | 99 | Double yen from KOs and playtime rewards |

> 💡 Cheap passes (49 R$) are easy first buys for kids. Most first purchases are under 100 R$.

## Developer Products
| Name | Price (R$) | Benefit |
|---|---|---|
| Luck Potion | 19 | +1x luck for 5 min |
| 5 Luck Potions | 79 | 5 × Luck Potion (best value) |
| Super Luck Potion | 49 | +2x luck for 5 min *(was x5. Lowered because luck is now capped at 5x, see [[03 Systems]])* |
| 1,000 Yen | 39 | +1,000 yen |
| Server Luck | 99 | +1x luck for **everyone in this server** for 10 min + announcement. The card and banner must say "this server", because players assume it works everywhere. |

> 💡 Server Luck is a great product. The buyer feels like a hero, and everyone else sees it and wants to buy one too.

> **No spin packs:** spinning is free, so Robux only buys **luck** (passes, potions, Server Luck) and **speed** (Quick Spin, Auto Spin). This is how RNG games like Sol's RNG make money. *(LIHFOLK: Teardown - Sol's RNG)*

- **Prices on screen come from Roblox** (`MarketplaceService:GetProductInfoAsync`), never typed into the UI. Regional pricing means a typed price can be wrong. *(LIHFOLK: Developer Products and ProcessReceipt)*
- The numbers in these tables are just the starting prices you set in the Creator Dashboard.

## Paid random items (Roblox rules, as of Oct 2026)
Spinning is free, and **free random rewards are exempt.** But luck you pay for is a "probability modifier", and the rules cover it:
- A free spin **with paid luck active** (x2 Luck pass, a potion bought with Robux, or with yen that can be bought with Robux, the VIP Area, someone else's Server Luck) counts as a paid random item.
- **Quick Spin / Auto Spin** don't change the odds, but they buy more spins per minute. LIHFOLK's safe reading: show the full odds before selling them too.
- Simplest rule: **show the odds everywhere, always.** It costs nothing. *(LIHFOLK: Paid Random Items and Odds Disclosure in Practice §2; Teardown - Sol's RNG; Regional Compliance)*

**1. Show the odds**
- Before any purchase, show **every ability** and its real chance as a **percentage**. The percentages must add up to 100%. "1 in 10,000" can be shown as well, but not instead.
- Put the odds behind a button with a word on it ("📊 Odds"), not just an ⓘ icon. It goes on **every purchase surface**: the Spin button, the spin machine, and the Shop cards for luck, Quick Spin and Auto Spin.
- The odds come from the same code the server rolls with, and they update **live** when luck changes (potion, pass, area, someone's Server Luck) and when pity or the first-spin guarantee applies.
- Rounding: keep at least 4 digits after the first non-zero digit (0.009999% not 0.01%), add "values are rounded", and never show a non-zero chance as 0%.

**2. Luck products show before → after**
- Each luck product shows its effect in numbers before purchase, using the player's real luck and the cap, e.g. "Mythic: 0.01999% now → 0.02999% with this potion".
- At the 5x cap the button is disabled: "Your luck is already at max".

**3. Restricted players (`PolicyService`)**
In some countries Roblox flags players with `ArePaidRandomItemsRestricted`. For those players:
- **Blocked (anything that buys luck):** Luck / Super Luck Potions for Robux, Server Luck, x2 Luck, VIP (its area adds luck), 1,000 Yen and x2 Yen (yen buys potions). The cards are hidden and the server refuses the prompt.
- **Still allowed:** Quick Spin, Auto Spin, +1 Equip Slot, +10 Storage. They spin **for free** with free luck only (area bonus, potions bought with yen they earned), which is exempt.
- **Server Luck** bought by someone else **does not apply** to a restricted player's rolls.
- If the policy check fails, treat the player as **restricted** (fail closed). Check on the server, not only by hiding UI.
- Test it with a debug switch that pretends your Studio account is restricted, then walk through every shop and popup.

**4. Changing odds later**
- Any change to odds, luck or the cap counts as a policy change. Log it with the date, announce it in the update log, and resubmit the Maturity & Compliance questionnaire if needed.

## Rules
- **Fair for free players?** ✅ Yes. Everything that affects gameplay (spins, potions, yen, abilities) can be earned for free, just slower.
- **No pay-to-win in PvP?** ✅ Mostly. Robux buys *luck and speed*, not damage. Free players can roll the same Mythic abilities.
  - ⚠️ The **+1 Equip Slot** pass is the only one that gives a PvP edge. Options:
    1. Let free players unlock slot 3 by playing (e.g. at level 10 or after 100 KOs), so the pass just gets it sooner. **(Recommended)**
    2. Remove the pass.
  - The **VIP Area** luck (+0.5x) only helps rolling, not PvP damage, so it still fits the "luck and speed" rule.
- **No selling abilities directly.** You can't buy a Mythic ability, only luck. This keeps the RNG exciting and rare abilities special.
- **No fake "limited time" pressure** on kids. Timers only when there's a real end date.
- **No near-misses on spins.** The reel never stops "one card away" from a Mythic. *(LIHFOLK: Ethical Design and Player Trust)*
- **Auto modes never spend paid items** (potions) on their own.

## Where to show purchases (without being annoying)
- Shop button on the HUD
- Potion timer running out: a small "Potion ended. Buy another? (100 ¥ / R$)" toast, with the yen option first
- Server Luck announcement banner
- ~~Luck pass suggestion after an unlucky streak~~ **Removed.** Selling luck right when a kid is frustrated is a dark pattern. The pity bar ("Epic+ guaranteed in 12 spins") does that job for free. *(LIHFOLK: Ethical Design and Player Trust, §3 and §6)*

**Popups the game opens on its own** (not ones the player taps) are never shown:
- during the tutorial or the first ~3 minutes
- in combat or right after dying
- within 5 minutes of the last one

## Purchases that never get lost
- Grant dev products only in `ProcessReceipt`, never from a client signal. Only **one** script sets `ProcessReceipt`.
- Save the grant and the `PurchaseId` **in the same player profile**, then return `PurchaseGranted`. If the player isn't in the server or the save fails, return `NotProcessedYet`.
- Game passes: one server cache filled on join with `UserOwnsGamePassAsync`. If the check errors, retry. Never treat an error as "doesn't own".
- Keep a purchase log (purchase id, product, Robux paid, what was given, time) for support.

## Launch plan
- **MVP:** x2 Luck, Quick Spin, **Auto Spin** ✅ *(moved from Later: speed passes fit free spinning, and skipped results still give Shards)*, VIP, Luck Potion (1 and 5-pack), 1,000 Yen (+ the odds screen and policy check above, required before selling any luck)
- **Later:** Storage, x2 Yen, Super Luck Potion, Server Luck
- **Never sold:** Shards and ability levels (upgrades stay earned).

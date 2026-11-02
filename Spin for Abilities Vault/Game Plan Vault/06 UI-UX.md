# UI / UX

> Filled-in draft. Open decisions are settled (see bottom). Tweak freely.

## Style
- **Main colors:**
  | Use | Color | Hex |
  |---|---|---|
  | Panel background | Deep navy (90% opaque) | `#141826` |
  | Panel inner / cards | Lighter navy | `#1F2538` |
  | Outline / stroke | Near-black | `#0A0C14` |
  | Main accent (buttons, highlights) | Energy gold | `#FFC83D` |
  | Second accent (spin, luck) | Electric cyan | `#3DE0FF` |
  | Good / confirm | Green | `#4CD964` |
  | Bad / close / delete | Red | `#FF4D5E` |
  | Text | White, with black stroke | `#FFFFFF` |
- **Font:** `LuckiestGuy` for titles, numbers and buttons (bold, anime/cartoon). `FredokaOne` for small text and descriptions (easy for kids to read). Every text gets a black `UIStroke` (thickness 2–3) so it's readable on top of VFX.
- **Rarity colors:** Common Grey `#B0B4BE` · Uncommon Green `#7BD65A` · Rare Blue `#3D8BFF` · Epic Purple `#A64DFF` · Legendary Amber Gold `#FF9F1C` · Ascended Magenta `#FF4FD8` · Mythic Red `#FF3B3B` · Divine White-gold `#FFF1C4` (with glow) · Secret Rainbow (animated `UIGradient`) on black `#000000` (from [[05 World & Art]])
  - Every rarity card also shows the rarity **name** as text, so Uncommon green never reads as the green "confirm" button and color-blind players can tell tiers apart.
  - Legendary is warmer than the button gold (`#FFC83D`) and always has the rotating shine, so Legendary cards never look like buttons.
- **Button style:** chunky and rounded (`UICorner` 0.25 scale), thick dark outline, a vertical `UIGradient` (lighter top → darker bottom) and a darker "shadow" copy 4 px below so they look pressable. Icon on the left, text on the right.
- **Animations:**
  - Hover: grow to 1.08x (0.1 s). Click: shrink to 0.92x, then bounce back (Back easing).
  - Popups: scale from 0.6 → 1 with `Back` easing (0.25 s) + darkened background fade.
  - Close: shrink + fade (0.15 s). Never make the player wait for a close animation.
  - Number changes (yen, spins): count up quickly + small "pop" scale.
  - Rare+ items: slow rotating `UIGradient` shine across the card.

## Screens
- [x] HUD
- [x] Spin / Roll screen
- [x] Inventory / Equip
- [x] Shop (Gamepasses + Products)
- [x] Area Unlock popup
- [x] Odds / Index (all abilities + chances)
- [x] Settings
- [x] Main menu / Loading
- [x] Daily rewards (Later)
- [x] Quests (Later)

> **Rule for all menus:** only one big menu open at a time. Opening a new one closes the old one. Every menu has a big red ✖ in the top right **and** closes when you tap the dark background.

---

### HUD (always on screen)
| Element | Position on screen | Notes |
|---|---|---|
| Yen counter | Top-left, under the Roblox top bar | ¥ icon + number + small green **+** that opens Shop → Yen tab |
| Shards counter | Top-left, next to yen | 💎 icon + number. No **+** button (Shards aren't sold). Tap = opens the Inventory to upgrade |
| Total spins counter | Top-left, under yen | "🎲 3,400 spins" (how many you've done, not a currency) + thin progress bar underneath: "Area 2: 3,400 / 5,000" |
| Luck multiplier | Top-center | "🍀 3.2x". Shows the **exact** luck the next spin uses, after the 5x cap ("🍀 5.0x MAX"). Tap = popup explaining where it comes from: "1x base + x2 Luck pass +1 + Potion +1 + Area 2 +0.2". Server Luck says "this server" |
| Potion timer | Top-center, right under luck | Only when active: potion icon + "4:32". Flashes in the last 10 s |
| Spin button | Bottom-center, biggest button | Cyan, says **SPIN** (free, unlimited). Pulses when ready, with a short fill sweep while the next spin loads. Only shows near a spin machine. If an Epic+ result is still waiting for Keep/Skip, it says **CHOOSE FIRST** |
| Auto Spin toggle **(Later)** | Small button just left of Spin | Gamepass only. Hidden until the Auto Spin pass launches. Then: without pass it shows a 🔒 and opens the pass in the Shop. With the pass: tap to toggle, long-press to pick "keep at or above: Rare / Epic / Legendary" |
| Ability slots (1 / 2 / 3) | Bottom-right (mobile), bottom-center row (PC) | Square icons with rarity-colored border, keybind number in the corner, cooldown = dark sweep + seconds. Slot 3 shows 🔒 until unlocked. Tapping it shows both ways: "Unlock free at 100 KOs (37/100)" and "Get it now" (opens the +1 Equip Slot pass) |
| Combat buttons (mobile) | Bottom-right, around the jump button | **M1** (biggest, where the right thumb rests), **Block** (hold) and **Dash**, with the ability slots in an arc above. Only shows in the Battlegrounds. PC uses click / F / Q |
| Health bar | Bottom-center, above Spin / ability row | Green → yellow → red. Only shows in the Battlegrounds or when damaged. Block meter as a thin bar under it (shows how close you are to a guard break) |
| Menu buttons (Shop, Inventory, Index, Settings) | Left side, middle, stacked vertically | Big square icon buttons: 🛒 Shop (gold, biggest), 🎒 Inventory, 📖 Index, ⚙️ Settings. Red dot on a button when something new is there |

Extra HUD bits:
- **Playtime reward bar** (left side, under menu buttons): "🎁 Free potion in 2:14". Tap when ready.
- **Notifications** (right side, middle): small toasts like "+25 ¥ KO!" that slide in and fade after 3 s. Max 3 at once.
- **Server announcements** (top-center banner): Mythic/Divine/Secret rolls, events starting, and Server Luck (Server Luck and events are **Later**).
- **KO streak badge** (under the luck counter, only while on a streak): "🔥 5 KO STREAK · +0.5x luck at the arena machine". Disappears with a small "streak ended" toast when you're KO'd or leave the arena.
- **Zone label** (top-center when entering a zone): "⚔️ BATTLEGROUNDS" in red or "🛡️ SAFE ZONE" in green, fades after 2 s.
- **Kill feed** (top-right, Battlegrounds only): "PlayerA ⚔️ PlayerB", max 4 lines, fades after 5 s.
- **Combo counter** (center-right, while hitting someone): "4 HIT!" that pops on each hit and fades when the combo ends.

### Spin / Roll screen
- **What shows while rolling:** HUD fades out (except yen). A horizontal strip of ability cards scrolls fast across the middle of the screen, slowing down like a slot machine. Card borders flash in their rarity colors. Ticking sound speeds up then slows.
- **Honest reveal rules** *(LIHFOLK: Reward Moments and Celebrations, §3; Ethical Design and Player Trust)*:
  - The server rolls **first**. The strip is built to stop on that result.
  - The strip only shows abilities this player **could actually get** right now, picked from the real odds (mostly Commons, like real spins).
  - **No near-misses:** the strip never stops one card past an Ascended or rarer. Spins can be bought with Robux, so this counts as a paid roll.
  - Any build-up glow must **come from the result**: a gold glow means at least Legendary, every time. Never fake a glow that ends in a Common.
  - Reveals stay short overall: Common/Rare is the most common result, so keep it short and save the darkening, HUD hiding and big shake for Legendary+.
- **How long the reveal takes:** Common/Uncommon/Rare 1.5 s · Epic 2 s · Legendary 3 s · Ascended 3.5 s · Mythic 4 s · Divine/Secret 5 s. **Quick Spin pass:** 0.5 s for everything below Legendary (big ones still play, they're the fun part). The next spin unlocks ~1 s after a reveal ends.
- **Rarity reveal effect:**
  | Rarity | Effect |
  |---|---|
  | Common | Card pops in, small grey flash |
  | Uncommon | Card pops in, small green flash |
  | Rare | Blue flash + sparkles |
  | Epic | Purple burst, light camera shake |
  | Legendary | Screen goes dark → gold light beams → card slams in, shake, gold confetti |
  | Ascended | Magenta energy rings rise up the screen, card ascends from below, petals/sparks |
  | Mythic | Red lightning, screen flashes red, big shake, slow-mo "MYTHIC!" text |
  | Divine | White light floods the screen, choir-like sound, halo forms around the card, slow fade-in |
  | Secret | Screen goes fully black for 1 s, "???" text, then rainbow explosion + unique sound |
  - Each tier adds something the one below doesn't have, and the big screen effects (darkening, HUD hiding) are saved for Legendary+ so they keep feeling special.
- **Result card:** big card in the center: ability icon, name, rarity banner, real chance ("0.009999% · about 1 in 10,000"), type (melee/projectile/AoE/movement/defense), damage + cooldown. **"NEW!"** sticker if it's the first time.
- **Buttons after roll:** [x] Keep  [x] Equip  [x] Skip / Delete. They only become tappable **0.3 s** after they appear, so a kid mashing the screen doesn't skip a Mythic by accident.
  - **Equip** (green) – opens a quick "Pick a slot" with your slots.
  - **Keep** (gold) – puts it in storage. If storage is full, it asks which ability to replace.
  - **Spinning again** = Skip for Common/Uncommon/Rare results. For **Epic+** you must pick Keep/Equip/Skip first, so a Mythic is never thrown away by mashing SPIN.
  - **Skip** (grey) – shows what you get: "Skip → +10 💎 Shards". Works on any rarity. Epic+ asks "Are you sure?" so kids don't skip a Mythic by accident. Locked abilities can't be skipped.
  - **Auto-skip** setting: auto-skip up to Common / Uncommon / Rare (turns them straight into Shards) so fast spinners aren't spammed.
  - Skipping shows a small "+2 💎" pop flying to the Shards counter.
- **Pity bar:** small bar under the Spin button showing the closer guarantee: "Epic+ in 23 spins" and, smaller, "Legendary+ in 187".
- **Odds button:** "📊 Odds" next to the Spin button. It has to be a word, not just an icon (Roblox rule for paid spins). Opens the Odds tab with your *current* odds.
- **Server announcement for:** Mythic, Divine and Secret (and Ascended as a chat message only). Banner: "🔥 **PlayerName** rolled **Inferno Fist** [MYTHIC] (1 in 10,000)!" Merge banners if several land at once, and max 1 every few seconds.

### Inventory / Equip
- **Layout:** two parts in one window.
  - **Top:** your 2–3 equip slots, big, with the ability names. This is your "build".
  - **Bottom:** scrollable grid of storage cards (4 per row on mobile, 6 on PC). Card = icon + rarity border + name.
  - **Right side (PC) / popup (mobile):** info panel for the selected ability.
- **Max storage slots:** 15 (+10 with the Storage pass = 25; the pass is **Later**). Counter at the top: "12 / 15".
- **Sort by:** [x] Rarity  [x] Newest  [x] Damage. Plus a rarity filter row (tap a color to show only that rarity).
- **Info shown per ability:** name, rarity, type icon, **level (1–10)**, damage (with the level bonus), cooldown, range, short description, and a small looping preview of the VFX (or a still image for MVP).
- **⬆ Upgrade button** on the info panel: "Level 4 → 5 · 400 💎 + 400 ¥ · +4% power". Levels are per ability type, so it also says "All your Thunder Lances level up". Grey with the missing amount if you can't afford it ("Need 120 more 💎"). Max level shows "MAX".
- **Equip:** tap a card → **Equip** button → tap the slot. (Drag-and-drop is bad on mobile, so keep it to taps; you can add drag for PC later.)
- **Other buttons on the info panel:** Unequip, Delete (with confirm), 🔒 Lock (locked abilities can't be deleted or auto-skipped).

### Odds / Index
- **Tabs:** Odds · Index
- **Odds tab** *(Roblox paid random item rules, see [[04 Monetization]])*:
  - **One row per ability**, grouped under rarity headers: icon, name, **your chance as a %**, and optionally "about 1 in N". All rows together add up to 100%.
  - Numbers come from the same `Odds` module the server rolls with, and update **live** when your luck changes (potion starts or ends, area, someone buys Server Luck).
  - Rounding: at least 4 digits after the first non-zero one (0.009999%), never "0%", plus a small line: "Values are rounded and may not add up to exactly 100%."
  - **Special next spins:** on a pity spin it shows "Next spin: Epic+ guaranteed" with only Epic+ rows. The same applies during the first-spin Rare+ guarantee.
  - Pity rules in words: "Epic+ guaranteed after 50 spins without one. You're at 27." and "Legendary+ guaranteed after 300 spins without one. You're at 113."
  - Bottom: "Your luck: 3.2x = 1x + x2 Luck pass +1 + Potion +1 + Area 2 +0.2 (max 5x)".
- The **same Odds popup** opens from every place that sells luck or spin speed, and from the spin itself: the Spin button, the in-world spin machine, and the Shop cards for potions, x2 Luck, VIP, Server Luck, Quick Spin and Auto Spin.
- **Index tab:** grid of every ability. **Found = rolled at least once, even if you skipped it** (you don't have to keep it). Found = full color + its level. Not found = black silhouette + "???" and its rarity border so players know what to chase. Top shows "Found 8 / 15". (Later: rewards for completing a rarity.)

### Shop
- **Tabs:** [x] Gamepasses  [x] Potions  [x] Yen  *(no Spins tab: spinning is free)*
- **Layout:** tabs on the left (vertical), big cards on the right. Each card: icon, name, one-line benefit, green Robux price button. Owned passes show "✅ OWNED" in grey.
- **Prices** on the buttons are loaded from Roblox (`GetProductInfoAsync`), never typed in.
- **Luck and spin-speed cards** have a "📊 Odds" button. Luck cards show before → after in numbers ("Mythic 0.01999% → 0.02999%"). At max luck they're disabled: "Your luck is already at max".
- **Restricted players** (`RandomItemsRestricted`, set by the server): everything that buys luck is hidden: Robux potions, x2 Luck, VIP, Server Luck, yen packs and x2 Yen. The server also refuses them, so hiding is only for looks.
- **Highlight "Best Value":** gold ribbon in the corner of **5 Luck Potions** and **x2 Luck**. A "🔥 POPULAR" tag on Quick Spin (cheap first buy).
- **Yen can buy things too:** Luck Potions show **two** buttons: ¥ yen price first, then R$ price, so free players see they can earn it.
- **Where the Shop opens from:** 🛒 HUD button, the green **+** next to yen, the 🔒 on Auto Spin / slot 3, and the Shop NPC.
- **Popups the game opens on its own** (offers, "potion ended") wait in a queue. They never show during the tutorial, in a fight, right after dying, on top of another menu, or within 5 minutes of the last offer. *(LIHFOLK: Ethical Design and Player Trust, §6; HUD Design, popup arbitration)*

### Area Unlock popup
- **Message:** "🎉 NEW AREA UNLOCKED! **Desert Village**"
- **Reward shown:** "🍀 +0.2x Luck at this area's spin machine" + reward cards: "+2 Luck Potions" and "+500 ¥" that pop in one by one.
- **Effect:** screen flash, confetti in the area's color, big drum sound, then a **Teleport there** button and a **Later** button. A golden arrow leads to the gate if they pick Later.
- **Locked gate preview (in world):** BillboardGui over the gate: "🔒 15,000 Spins · 🍀 +0.3x Luck" with a progress bar.

### Settings
- [x] Music volume (slider)
- [x] SFX volume (slider)
- [x] Low graphics / VFX mode
- [x] Hide other players' VFX: simplifies them (fewer particles, no screen effects) but **never hides attacks or hit warnings**, so you can still see what's about to hit you in a fight *(LIHFOLK: VFX Performance Budgets and Culling)*
- ~~Skip spin animation~~ **Removed.** It gave away for free the same thing the **Quick Spin** pass sells. Fast reveals are the pass's job.
- [x] Auto-skip up to: Off / Common / Uncommon / Rare (skipped ones become Shards)
- [x] Hide server announcements
- [x] Show damage numbers
- [x] Redeem code box (codes are great for Roblox games: put them in update logs and the group)

Layout: simple list, toggle switches on the right (green ON / grey OFF), sliders for volume.

### Main menu / Loading
- **Loading screen shows:** logo in the center, dark background with slowly moving speed lines, a loading bar in gold, and a random tip under it ("💡 Areas give permanent luck!", "💡 You never lose abilities when you die"). Rotating showcase of a Mythic ability card in the background so they see the goal.
- **Play button:** [x] Yes. One big **PLAY** button once loaded (lets music/VFX load and gives a "start" feeling). Skip it for returning players later if it feels slow.

### Daily rewards (Later)
- 7 boxes in a row (Day 1–7), Day 7 is bigger and gold. Claimed = ✅, today = glowing, future = dim.
- Auto-opens on join if there's a reward to claim. One **CLAIM** button.

### Quests (Later)
- Small tracker on the right side of the HUD (collapsible): up to 3 quests, each with a progress bar "Get 5 KOs 3/5" and reward icon.
- Full quest menu from a 📜 HUD button: Daily / Session tabs, **Claim** buttons glow when done.

---

## HUD sketch
```
┌──────────────────────────────────────────────────────────┐
│ [Roblox top bar]          🍀 1.3x                         │
│ ¥ 1,250 [+]  💎 3,420    🧪 4:32                         │
│ 🎲 3,400 spins                                           │
│ ▓▓▓▓░░ Area 2: 3,400/5,000                   +25¥ KO!   │
│                                                          │
│ [🛒]                                                     │
│ [🎒]                                                     │
│ [📖]                                                     │
│ [⚙️]                                                     │
│ 🎁 2:14                                                  │
│                         ████████░░ HP                    │
│ (joystick)          [AUTO] [    SPIN    ]     [1] [2]    │
│                      Epic+ in 23 spins            [3🔒]  │
└──────────────────────────────────────────────────────────┘
```
_Replace with a real mockup later: paste the image on this line in Obsidian._

## New player flow (first 60 seconds)
1. **0–10 s:** Loading → PLAY. Spawn right in front of the spin machine. One line of text: "Spin for a power. It's free!" → **SPIN!** (the HUD Spin button is glowing with a pointing hand).
2. **10–30 s:** First spin is a guaranteed Rare+ with a flashy reveal → **Equip** button is highlighted → it goes into slot 1. Arrow points to the training dummy: "Try your new power!"
3. **30–50 s:** They hit the dummy (slot 1 button pulses on mobile). Popup: "Nice! Here's a free 🧪 Luck Potion" → drink it → spin again with luck.
4. **50–60 s:** Arrow + quest text: "⚔️ Go to the Battlegrounds and get your first KO for **+1 Luck Potion**." Tutorial ends, but the arrow stays until they enter the arena.

> Keep tutorial text to one short sentence at a time, with a big pointing arrow. Kids skip reading.

## Mobile considerations
- [x] Buttons big enough for thumbs (at least **44 px**, ideally 60+ px for Spin and ability buttons)
- [x] Ability buttons on the right side, joystick on the left
- [x] Nothing hidden behind the Roblox top bar or phone notch: set `ScreenInsets` on **every** ScreenGui (`CoreUISafeInsets` for the HUD). Don't hard-code the top bar height. *(LIHFOLK: Safe Areas and Insets)*
- [x] Text readable on small screens (min text size ~18 px, use `TextScaled` + `UITextSizeConstraint`). LIHFOLK's hard minimum is 12 px; our 18 px is stricter, so keep it.
- [x] Gaps between tappable things at least **8 px**, and **no overlaps** (check the combat buttons vs. the ability arc vs. the jump button)
- [x] Low VFX mode for weaker phones
- [ ] Test on: [ ] Phone  [ ] Tablet  [ ] PC  [ ] Console
- [ ] Studio device sizes to check every screen at: **844×390** and **667×375** (phones), **1920×1080** (PC), plus one notched phone. *(LIHFOLK: AI Pitfalls - UI and Input)*
- **Other notes:**
  - Use **Scale** (not Offset) for sizes + `UIAspectRatioConstraint` on every button and card so nothing stretches.
  - Menus take ~85% of the screen on phones, ~60% on PC.
  - Jump button on mobile sits bottom-right: put ability slots **above and left of it**, not on top of it.
  - Console: every button needs gamepad selection (`Selectable`, `NextSelection…`); add later if you ship to console.

## Ideas / To decide
- ✅ **Decided:** Currency is **Yen** (¥) everywhere.
- ✅ **Decided:** The Spin button only shows near a spin machine (each area has its own machine for its luck bonus, see [[05 World & Art]]).
- Ability "build" presets: save 2–3 loadouts and swap with one tap.
- Title under the player's name showing their rarest ability ("🔥 Mythic Owner").
- Small "Last 10 rolls" history in the spin screen.
- Make UI in Claude Design / ForgeGUI using this note as the spec, then build it in Studio.

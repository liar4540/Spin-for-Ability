# Tech Plan

> Built from [[03 Systems]], [[02 Core Loop]] and [[04 Monetization]]. **Golden rule:** the server decides everything important (rolls, damage, money). The client only asks and shows.

## Folder layout
Code lives in `src/` and Rojo syncs it into Studio (mapping is in `default.project.json`):

| Folder on disk | Shows up in Studio as |
|---|---|
| `src/server/` | `ServerScriptService.Server` |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` |
| `src/shared/` | `ReplicatedStorage.Shared` |

```
src/
  server/
    init.server.luau           -- Main: starts every service in order
    Packages/
      ProfileStore.luau        -- saving module (drop it in here)
    Services/
      DataService.luau         -- load/save/autosave player data
      SpinService.luau         -- RNG rolls, pity, luck
      AbilityService.luau      -- equip/unequip, lock, storage limits
      CombatService.luau       -- battlegrounds combat: M1 combo, block/guard break, dash, fighter states, hitstun, ragdoll, damage, KOs + kill credit
      HitboxService.luau       -- spatial queries per move + 1 s position history for lag-compensated reach checks
      EconomyService.luau      -- yen, buying potions with yen
      PotionService.luau       -- luck potion timers (+ Server Luck later)
      RewardService.luau       -- playtime rewards, tutorial rewards, codes
      MonetizationService.luau -- game passes + ProcessReceipt (the ONLY script that sets ProcessReceipt)
      PolicyService.luau       -- the ONLY script that calls Roblox PolicyService; fails closed (unknown = restricted)
      RemoteGuard.luau         -- one guard every remote goes through: rate limit → type/shape → bounds → act
      ZoneService.luau         -- safe zone / Battlegrounds arena, spawn shield, areas, spin machines, VIP Area access

  shared/
    Config/
      Rarities.luau            -- rarity names, "1 in N" checks, colors, which tiers luck affects, luck cap
      Odds.luau                -- ONE function: (luck, pity, guarantees) → real % per ability. Used by SpinService AND the Odds UI
      Abilities.luau           -- every ability's stats (name, rarity, damage, cooldown, range, type, hitbox, stun, knockback)
      Combat.luau              -- base moveset data: M1 chain damage/timing, block HP, dash cooldown, hitstun decay, combo cap, respawn + shield times
      Areas.luau               -- area names, spins needed, luck bonus (incl. VIP Area)
      Economy.luau             -- prices, KO reward, spin cost
      Products.luau            -- game pass + dev product IDs
      (Codes live server-only in src/server/Config/Codes.luau, so exploiters can't read unreleased codes)
    Types.luau                 -- shared type definitions

  client/
    init.client.luau           -- Main: starts every controller
    Controllers/
      SpinController.luau      -- spin button, reveal animation
      CombatController.luau    -- M1 / block / dash input (100–200 ms input buffer), instant local animation + VFX, mobile combat buttons, soft targeting
      AbilityController.luau   -- keys 1/2/3 + mobile buttons, local VFX
      InventoryController.luau -- storage / equip UI
      HUDController.luau       -- yen, spins, potion timer, popups
      ShopController.luau      -- purchase prompts
      SettingsController.luau  -- settings menu, codes box
```
`src/shared/Hello.luau` is just Rojo's template file. Delete it when Milestone 1 starts.

**Built in Studio, not synced by Rojo** (saved in the place file):
- `ReplicatedStorage/Remotes/`: made by the server at start, so there's nothing to build
- `ReplicatedStorage/Assets/VFX/`: ability effects, reveal effects
- `StarterGui/`: ScreenGuis (HUD, Spin, Inventory, Shop, Settings)
- `Workspace/`: maps, SafeZone/Battlegrounds zone parts, arena spawn points, area spin machines and gates (tagged with CollectionService), `Dummies/`

> ⚠️ Rojo only syncs what's in `default.project.json`. Anything you build in Studio lives in the place file, so **publish often** so you don't lose it.

## Remotes
| Remote | Direction | Payload | Server validation |
|---|---|---|---|
| `RequestSpin` (Function) | Client → Server | none | Spinning is **free**, so no cost check. Is the next spin ready (server clock: reveal length of the last result + ~1 s, shorter with Quick Spin)? **No Epic+ result still waiting for a choice?** **Standing near a spin machine?** The server works out which area's machine it is (and checks the area is unlocked, or the VIP pass for the VIP Area), then rolls and returns the result |
| `EquipAbility` | Client → Server | `abilityId, slot` | Player owns it? Slot is 1–2 (or 3 if unlocked)? Not already equipped |
| `UnequipAbility` | Client → Server | `slot` | Valid slot number |
| `DeleteAbility` | Client → Server | `abilityId` | Owns it? Not equipped? **Not locked?** |
| `ToggleLock` | Client → Server | `uniqueId` | Owns it? |
| `SaveSettings` | Client → Server | `settings` table | Only known keys, right types (numbers 0–1 for volume, booleans for toggles) |
| `RedeemCode` (Function) | Client → Server | `code` | String, max ~30 chars? Code exists and isn't expired? Not already redeemed? |
| `M1Attack` | Client → Server | `comboIndex` (1–4) | In Battlegrounds or near dummy? Alive and **not stunned / ragdolled**? Next hit in the chain and not faster than the swing timing (server clock)? **Server runs the hitbox** and deals damage |
| `SetBlock` | Client → Server | `isBlocking` (bool) | Boolean? Allowed from the current state (not stunned, not mid-attack)? Guard break state is tracked on the server |
| `Dash` | Client → Server | `direction` | Unit vector? Off cooldown (server timer)? Not stunned? Server checks the distance moved afterwards (no long teleports) |
| `UseAbility` | Client → Server | `slot, aimDirection` | Equipped? Off cooldown (server timer)? In Battlegrounds or near dummy? Alive and **not stunned**? Direction is a unit vector. **Server finds targets and deals damage** (never trust a "I hit X" message) |
| `ChooseResult` (Function) | Client → Server | `choice` ("Keep" / "Equip" / "Skip"), `slot?`, `replaceUniqueId?` | Is there a waiting result? Valid choice? Keep with full storage needs a `replaceUniqueId` the player owns, **hasn't locked** and hasn't equipped. Answers `{ Ok, Reason }` so the client can ask "which one to replace?" |
| `SetAutoSpin` | Client → Server | `on`, `keepMinRarity` | Owns the Auto Spin pass? Boolean? Rarity is one of the fixed names? |
| `UpgradeAbility` (Function) | Client → Server | `abilityId` | Known ability id? Owns at least one copy? Level < 10? Enough Shards **and** yen for this level (server table)? Take both and add the level in one step, no yields in between |
| `BuyPotion` | Client → Server | `potionType` | Known type? Enough yen? Not already at the 5x luck cap? |
| `RequestPurchase` | Client → Server | `productKey` | Known key (fixed list)? **Restricted player and this product buys luck (potions, x2 Luck, Server Luck, VIP, yen, x2 Yen) → refuse.** Only then does the server call `PromptProductPurchase` / `PromptGamePassPurchase` |
| `ClaimPlaytimeReward` | Client → Server | `tier` | Has the player actually been in the server long enough? Not already claimed |
| `DataUpdated` | Server → Client | changed fields (yen, spins, inventory…) | — |
| `SpinResult` | Server → Client | `abilityId, rarity` | — |
| `Announcement` | Server → All | `text, rarity` | — (Mythic/Divine/Secret rolls, events, Server Luck) |
| `AreaUnlocked` | Server → Client | `areaId` | — (shows the Area Unlock popup) |
| `HitEffect` | Server → All | `attacker, abilityId, position` | — (so everyone sees the VFX) |
| `Knockback` | Server → Client | `direction, strength` | — (the victim's own client applies it, since players own their character's physics) |
| `KillFeed` | Server → All | `killer, victim, streak` | — (also "X is on a 5 KO streak!" / "Y ended X's streak") |

Every client → server remote goes through `RemoteGuard`, in this order *(LIHFOLK: Remote Abuse Patterns and Rate Limiting in Practice)*:
1. **Rate limit first** (e.g. max 10 calls/second per player), before any expensive lookup.
2. **Types and shape:** right types, no extra keys, strings capped in length.
3. **Numbers:** check `x == x` (catches NaN, which passes every range check) and finite, then integer if needed, then range. Vectors: every part finite, then length (unit vector ≈ 1).
4. Use the `player` Roblox passes in, **never** a user id from the payload.
5. No `task.wait` / yields between "check" and "change data" on anything that moves yen, spins or items (stops duplication).
6. Don't kick on one bad call (laggy players). Count violations and act on repeated ones. No `warn` per rejected call.

**Live attributes the server sets for the UI:** `EffectiveLuck` (updates whenever any luck source starts or ends), `RandomItemsRestricted`, `PityCounter`, `LegendaryPityCounter`, `KOStreak` (also drives the 🔥 above the head).

## Battlegrounds combat (server)
*(From LIHFOLK: "Genre Playbook - Battlegrounds and Arena Fighters", "Combat Systems Architecture", "Hitboxes and Hit Detection".)*
- **Fighter state machine** on the server per player: Idle, Attacking, Blocking, Stunned, Ragdolled, Dashing. Remotes that don't fit the current state are ignored.
- **One damage path:** M1s, abilities and anything else all go through one `CombatService:Damage()` function, which applies block, spawn shield, multipliers (fixed order), KO credit and rewards.
- **Hit detection:** the server runs the hitbox (spatial query) at the hit moment, deduplicated per character per swing. It keeps the **last 1 s of positions** per player (sampled ~30 times a second) and rewinds by the attacker's ping, **capped at 250 ms**.
- **Feel:** the attacker's client plays the animation and VFX straight away; the server only decides damage.
- **Anti-infinite combo:** hitstun decays per hit, max combo ~3–4 s, 0.5–1 s get-up invulnerability after ragdoll.
- **KO credit:** last player to damage the victim in the last ~5 s.
- **Damage formula:** `ability base damage × rarity power (x1.35 per tier, from Rarities.luau) × (1 + 0.04 × (level − 1))`, then block, shield etc. in the one damage path.
- **Repeat-KO rewards:** before paying a KO, look up `DailyKOs.Victims[victimUserId]` (reset when `DailyKOs.Day` isn't today's UTC day). 1st/2nd/3rd/4th+ KO on that player today pays 100% / 50% / 25% / 10% yen; the 4th+ doesn't count toward the streak. Keep at most ~200 victims per day in the table.
- **KO streak (session only, server memory):** +1 on each KO credit that counts. Reset to 0 when the player is KO'd **or ZoneService says they left the arena**. At 3+ the player gets +0.5 luck, but only when SpinService sees them at the Arena Spin Machine. Ending a streak pays +25 ¥ × the streak length.

## Player data schema
```lua
{
	Version = 1,

	-- Currency
	Yen = 0,
	Shards = 0,               -- from skipped spins; spent with yen on ability upgrades
	-- (no Spins currency: spinning is free)

	-- Abilities
	Inventory = {},           -- { [uniqueId] = { AbilityId = "FireFist" } }  (copies; no level here)
	Levels = {},              -- { [abilityId] = 1..10 } level per ability TYPE, shared by every copy
	Discovered = {},          -- { [abilityId] = true } every ability ever rolled (Index + "NEW!")
	Equipped = { false, false, false }, -- uniqueId per slot, false = empty
	                          -- (NOT { nil, nil, nil }: in Lua that is just an empty table, so slot 3 vanishes)
	Locked = {},              -- { [uniqueId] = true } can't be deleted or auto-skipped
	MaxStorage = 15,

	-- RNG
	PityCounter = 0,          -- spins since last Epic+
	LegendaryPityCounter = 0, -- spins since last Legendary+
	TotalSpins = 0,           -- also decides which areas are unlocked

	-- Potions
	Potions = { Luck = 1 },   -- owned, unused (tutorial gives 1)
	ActivePotion = { Kind = "", SecondsLeft = 0 },    -- the one running potion
	PausedPotions = {},       -- { [kind] = secondsLeft } weaker potions paused by a stronger one

	-- Stats
	KOs = 0,
	Deaths = 0,
	BestStreak = 0,           -- for the longest-streak leaderboard
	DailyKOs = { Day = 0, Victims = {} }, -- { Day = UTC day number, Victims = { [userId] = KOs today } }

	-- Progress flags
	TutorialDone = false,
	RedeemedCodes = {},       -- { [code] = true }

	-- Settings (from the Settings menu)
	Settings = {
		Music = 0.5,
		SFX = 0.5,
		LowVFX = false,
		HideOthersVFX = false,    -- simplifies others' VFX, never hides attacks
		AutoSkip = "None",       -- "None" | "Common" | "Uncommon" | "Rare" (skip up to and including)
		HideAnnouncements = false,
		DamageNumbers = true,
	},

	-- Purchases
	ProcessedReceipts = {},   -- PurchaseIds already granted. Lives IN the profile, so grant + marker save together
}
```
- ✅ **Potion time counts down only while you play** (`SecondsLeft`), so it doesn't run out while you're offline.
- **Not saved:** KO streaks (they end when you leave the arena anyway).
- **Version** lets you add fields later without breaking old saves (fill missing fields with defaults on load).
- Game passes are **not saved** — check them with `UserOwnsGamePassAsync` on join.
- **Waiting spin result** (`PendingResult`) lives in server memory, not the save. On leave: an Epic+ one is kept if there's room, anything else is dropped.
- **Not saved (session only):** playtime reward claims (`PlaytimeClaimed`) and time joined. Keep them in a normal table in `RewardService`, since they reset every session anyway.
- Unlocked areas aren't saved separately. They're worked out from `TotalSpins`.

## Saving rules
- Load on join with retries; if it fails, kick with "Data failed to load, please rejoin" (better than overwriting good data with an empty save).
- **Session lock** so the same player in two servers can't overwrite their data. Easiest way: use **ProfileStore** (free community module) instead of writing this yourself.
- Autosave every 3 minutes, on leave, and in `game:BindToClose`.
- If the profile is **locked by another server** or **failed to load**, never save defaults over it. Load must return ready / locked / failed separately. *(LIHFOLK: Session Locking and Profile Libraries)*
- Test in Studio with a separate test DataStore key, so test runs never touch real player data.

## Purchases *(LIHFOLK: Developer Products and ProcessReceipt; Game Passes)*
- **Only one** script sets `ProcessReceipt` (MonetizationService). A second one silently replaces the first, and its products never grant.
- In `ProcessReceipt`:
  1. Player not in this server, profile not loaded, or unknown product → return `NotProcessedYet`.
  2. `PurchaseId` already in `ProcessedReceipts` → return `PurchaseGranted` (already given).
  3. Give the item **and** add the `PurchaseId` to the profile, **save**, and only then return `PurchaseGranted`.
- At startup, check every product in `Products.luau` has a grant function.
- Never grant from `PromptProductPurchaseFinished` or a client remote.
- Retired products keep their grant code forever (old receipts can still arrive).
- Game passes: one server cache filled on join with `UserOwnsGamePassAsync` and updated on purchase. If the check **errors, retry**. Don't store "false".
- Prices in the UI come from `MarketplaceService:GetProductInfoAsync`.
- Keep a purchase log (PurchaseId, product, Robux paid, what was given, time).

## Spin logic (server)
*(LIHFOLK: RNG Drops and Luck Systems; Genre Playbook - RNG and Collection Games; Paid Random Items and Odds Disclosure in Practice)*
1. Checks pass (see `RequestSpin`). Spinning is free, so nothing is taken. An unchosen Common/Uncommon/Rare result from last time is skipped → its **Shards** are added.
2. **Luck (one function, `Odds.EffectiveLuck`):** `luck = 1 + pass(+1) + potion(+1 / +2) + area(+0.1…+0.4, VIP +0.5) + ServerLuck(+1) + KO streak(+0.5, Arena Spin Machine only)`, then **`min(luck, 5)`**. Restricted players don't get Server Luck. The same function sets the `EffectiveLuck` attribute.
3. **Roll** with a server `Random.new()`, rarest first through 8 checks: Secret `luck/250000`, Divine `luck/50000`, Mythic `luck/10000`, Ascended `luck/1000`, Legendary `luck/100`, Epic `luck/25`, then Rare `1/8` and Uncommon `1/3` (**no luck**). Each capped at 1. If none hit → Common.
4. **Guarantees** (applied before rolling, and shown on the Odds screen):
   - `LegendaryPityCounter ≥ 299` (300th spin with no Legendary+) → roll only among Legendary+. Checked first.
   - `PityCounter ≥ 49` (this is the 50th spin with no Epic+) → roll only among Epic+.
   - First-spin guarantee: the very first spin (`TotalSpins == 0`) → roll only among Rare+.
5. Pick a random ability of that rarity (equal chance inside a tier), store it as the player's `PendingResult`, update the pity counters (`PityCounter` 0 on Epic+, else +1; `LegendaryPityCounter` 0 on Legendary+, else +1), and return the result from `RequestSpin` (`SpinResult` is for Auto Spin later). The client reveal **lands on** that result. It goes into the inventory only on Keep/Equip (`ChooseResult`), or automatically with Auto Spin if it's at or above the chosen rarity. Skip (button, spinning again, Auto Spin or auto-skip) adds the rarity's Shards (1 / 2 / 4 / 10 / 30 / 100 / 500 / 2,000 / 10,000).
6. `TotalSpins += 1`. If that crosses an area's requirement (1,000 / 5,000 / 15,000 / 50,000), give the unlock reward and send `AreaUnlocked`.
7. **Odds screen** calls `Odds.Compute(luck, pity, guarantees)`, the same math as steps 2–4, and splits each tier evenly over its abilities.

**Tests:** roll 1,000,000 times at luck 1x, 2x and 5x, and on a pity spin, and check the counts match `Odds.Compute` (chi-square test). Expected at 1x: Common 55.38%, Uncommon 27.69%, Rare 11.87%, Epic 3.956%, Legendary 0.9989%, Ascended 0.09999%, Mythic 0.0100%, Divine 0.0020%, Secret 0.0004%. (A million rolls only gives ~4 Secrets, so test Secret/Mythic separately with a forced high luck or a bigger run.)

> ✅ **Done in code:** 9 tiers with `Power` and `Shards` per tier in `Rarities.luau`, Legendary pity (`Odds.MinRarityFor` + `LegendaryPityCounter`), new `OddsTest` numbers, project name **Spin for Abilities**.
> ⚠️ **Still to code:** giving Shards on Skip, the `UpgradeAbility` remote, levels per ability type (`Levels` in `DataService`), KO streaks, repeat-KO rewards.

## Tools / workflow
**Decision: Rojo for code, Studio for building.** Rojo 7.7.1 is already set up in the project folder.
- **Code:** write scripts in VS Code inside `src/`. Run `rojo serve` and click **Connect** in the Rojo Studio plugin, and changes sync into Studio live.
- **First time:** `rojo build -o "Spin for Abilities.rbxlx"`, then open that file in Studio (see the project `README.md`).
- **Building:** maps, UI, VFX and dummies are made in Studio as normal and saved in the place file (Rojo doesn't touch them).
- **Git:** the project folder is a git repo. Commit `src/` often. The `.rbxlx` place file is git-ignored, so back it up by publishing.
- **Team Create** on if anyone else builds with you (they also need Rojo to edit scripts).
- **Script layout:** one `Main` script per side, everything else a `ModuleScript` (no `_G`).
- **Packages / modules:** ProfileStore (saving) in `src/server/Packages/`. Optional later: a simple Signal module, or Wally to manage packages.
- **Testing:** Studio *Test → Clients and Servers* with 2 players to test PvP, **with simulated latency (100 ms and 250 ms)** for every combo; a server-only admin command (your UserId only, and only in Studio or for an allowlist) to give spins/yen for testing.
- **Policy test switch:** a Studio-only debug flag that makes your account count as `RandomItemsRestricted`. Walk through every shop card and popup with it on.
- **Backups:** File → Publish often; Studio keeps version history on the published place.
- **Before release:** turn on *Enable Studio Access to API Services* only in the test place; check the odds are shown in the spin UI.

## Build order (from [[03 Systems]])
1. DataService + data schema
2. Rarities/Abilities config + `Odds` module + SpinService + `RequestSpin` + RemoteGuard (+ the million-roll test)
3. CombatService + HitboxService + `Combat` config: M1 combo, block, dash, states, ragdoll, respawn + ZoneService (safe zone / Battlegrounds) + dummies
4. 3–5 abilities + AbilityService (equip), going through the same combat damage path
5. EconomyService (KO yen, buy potions with yen)
6. PotionService + RewardService
7. Tutorial
8. PolicyService + MonetizationService + Odds screen (all three before anything is for sale)
9. Areas: Area 1 + VIP Area spin machines, area luck in SpinService, `AreaUnlocked`
10. Settings + codes (`SaveSettings`, `RedeemCode`) + ability lock
11. Playtest with friends → log in [[10 Playtest Log]] → release MVP

# World & Art

## Art style
- **Vibe:** anime fighting style, inspired by Shindo Life 2 and other anime-power games (our own designs, not copies)
- **World:** stylized, colorful terrain, with each area having its own theme and color
- **VFX:** the star of the game. Bright, flashy anime power effects (fire, lightning, energy beams, auras, slashes)
  - Rarer abilities get bigger VFX, more particles, screen shake and glow
- **Rarity colors (use everywhere: UI, auras, reveals):**
  | Rarity | Color |
  |---|---|
  | Common | Grey |
  | Uncommon | Green *(new)* |
  | Rare | Blue |
  | Epic | Purple |
  | Legendary | Gold |
  | Ascended | Pink / magenta *(new)* |
  | Mythic | Red |
  | Divine | White-gold with a soft glow *(new)* |
  | Secret | Rainbow / Black |
  - Higher tiers add more than color: Ascended+ get a particle trim on their card and aura, Divine+ a glow, Secret an animated rainbow. Rarity must be readable for color-blind players too (shape and motion, not only color).
- **Mobile-friendly:** keep particle counts reasonable so phones don't lag *(LIHFOLK: VFX Performance Budgets and Culling)*
  - Write a particle budget per ability (per cast and per player) before making it.
  - Other players' effects play at **half or less**, and there's a global cap for the whole screen, so a full 20-player server doesn't lag.
  - **Reuse effects from a pool** instead of cloning and destroying per hit (that causes stutters in long fights).
  - Big see-through pieces close to the camera are what lags phones. Keep them small.
  - Low VFX mode **simplifies** attack effects but never removes them. Players must always see what's about to hit them.

## Maps / Zones
Areas unlock by **total spins**. Each new area gives a permanent luck boost at its spin machine, so players have a reason to keep spinning.
> Luck bonuses **add** to your other luck (Area 2 = +0.2x), and total luck is capped at **5x**. See [[03 Systems]].

| Zone                 | Unlock requirement | Luck bonus              | Theme                                                       |
| -------------------- | ------------------ | ----------------------- | ----------------------------------------------------------- |
| Spawn / Starter Area | Free               | 1x                      | Training grounds, spin machine, training dummies, safe zone |
| Area 1               | 1,000 spins        | 1.1x                    | e.g. Hidden Leaf-style village *(own design)*               |
| Area 2               | 5,000 spins        | 1.2x                    | e.g. Desert / Sand village                                  |
| Area 3               | 15,000 spins       | 1.3x                    | e.g. Snowy mountain temple                                  |
| Area 4               | 50,000 spins       | 1.4x                    | e.g. Sky / Floating islands                                 |
| Battlegrounds Arena  | Free               | – (KO streak: +0.5x at the Arena Spin Machine) | Open battlegrounds arena: fight other players, earn yen from KOs |
| VIP Area             | VIP Gamepass       | 1.5x luck + yen spawns | Gold / luxury theme, yen spawn on the ground to collect   |

### Zone ideas
- Each area has its own **spin machine**, so you must be standing there to get the luck bonus.
- Show a **locked gate** with "🔒 15,000 Spins" so players can see the next goal.
- Area unlock gives a **big announcement + reward** (luck potions + yen).

### Battlegrounds arena layout
- **Open and readable:** mostly flat ground with a few pieces of cover (rocks, pillars, walls) so fights can break line of sight but you can still see people coming. Sized for **10–20 players**.
- **Breakable props** *(nice to have)*: crates and fences that shatter when someone gets knocked into them. Keep the count low for phones.
- **Edges:** low walls or a soft boundary. Knockback into walls should look cool, not trap people.
- **Several spawn points** around the edge with a 2 s spawn shield, so nobody gets spawn-camped.
- **Entrance from spawn:** a clear gate or arch with the "⚔️ BATTLEGROUNDS" label, right next to the training dummies.
- **Arena Spin Machine:** one spin machine *inside* the arena, in an open spot (not a hiding corner), where KO Streak Luck works. Players on a streak spinning there are easy to spot and attack, which is the point.
- *(Later)* More arena maps that rotate, or one per area theme.

## Characters / Enemies
- **Players:** custom Roblox avatars with ability auras and VFX
- **Training dummies:** in spawn, for testing abilities
- **NPCs:** spin machine keeper, quest giver (Later), shop NPC
- **Bosses (Later idea):** a boss per area that drops spins or rare potions

## Asset list (models, VFX, sounds, animations)
**Tools:** LIHFOLK Vault, Blender, Claude Design
- **LIHFOLK** is a Claude Code plugin (turned on for this project). Useful parts: `lihfolk-vfx` (slashes, impacts, auras, beams), `lihfolk-sfx` (licensed combat/UI sounds), `lihfolk-assets` (local asset pack), `roblox-blender-modeling` + `roblox-asset-import` (Blender → Roblox), `lihfolk-worldbuilding` (maps), `roblox-ui-builder` (screens).

### Maps / Models
- [ ] Spawn / Starter area
- [ ] Spin machine (one per area, different look, + the Arena Spin Machine)
- [ ] Area 1 map
- [ ] Area 2–4 maps (Later)
- [ ] Battlegrounds arena (cover, spawn points, entrance gate)
- [ ] VIP Area + yen models
- [ ] Locked area gates
- [ ] Training dummies

### VFX
- [ ] Spin reveal effects (one per rarity, 9 total)
- [ ] KO streak flame above the head
- [ ] Shard pickup / upgrade effects
- [ ] Ability VFX (start with **3–5 for MVP**)
- [ ] Rarity auras around players
- [ ] Luck potion effect
- [ ] Yen pickup effect
- [ ] Area unlock effect

### Animations
- [ ] M1 combo (4 punches, last one knocks back)
- [ ] Block, guard break and dash (side + forward)
- [ ] Ability attack animations
- [ ] Hit / stun, knockback and short ragdoll (1–2 s), get-up
- [ ] Spin machine animation

### Sounds
- [ ] Spin rolling + reveal sounds (bigger for rarer)
- [ ] Ability sounds
- [ ] M1 swing / hit, block, guard break, dash sounds
- [ ] Hit / KO sounds
- [ ] Yen pickup
- [ ] Background music per area

### UI (Claude Design)
- [ ] Spin UI + odds display
- [ ] Inventory / equip screen
- [ ] Shop
- [ ] HUD (yen, spins, luck multiplier, potion timer)
- [ ] Area unlock popup

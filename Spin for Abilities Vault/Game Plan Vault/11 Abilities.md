# Abilities

✅ **Decided launch set: 16 abilities** across the 9 rarities. No elements. Events boost an ability **type** instead (see [[03 Systems]]).
Power multiplier per rarity is x1.35 per tier ([[03 Systems]] → Ability power by rarity). Damage below is **base** damage, before rarity power and level.

## The list

| Rarity | Ability | Type | What it does | How it looks |
|---|---|---|---|---|
| Common | **Ember Fist** | Melee | Fiery punch, small knockback | Orange-white flash on the fist, small fire burst + shock ring at the hit |
| Common | **Pebble Toss** | Projectile | Throws a quick rock | Small spinning rock, dust puff on launch, rock chips on hit |
| Uncommon | **Gale Step** | Movement | Quick dash with a wind trail | Pale cyan wind streaks along the dash path, swirl at start and end |
| Uncommon | **Frost Jab** | Melee | Icy punch that slows briefly | Blue-white flash, a few ice shards burst forward, frost ring on the target |
| Rare | **Stone Wall** | Defense | Wall that blocks projectiles for 3 s | Rock slabs rise out of a ground crack, dust ring, crumbles into chunks |
| Rare | **Thunder Lance** | Projectile | Fast lightning spear | Bright yellow-white spear (crossed ribbons), crackling trail, spark burst on hit |
| Epic | **Frost Bloom** | AoE | Ice flower that slows everyone nearby | Ground rune circle, crystal petals open outward, cold mist ring |
| Epic | **Shadow Swap** | Movement | Teleport behind the nearest enemy | Purple-black smoke puff where you vanish, dark ribbon trail, puff where you appear |
| Legendary | **Blood Moon Slash** | Melee | Wide crescent slash, red glow | Big red crescent: white-hot edge, crimson body, near-black smear, red sparks (LIHFOLK crescent recipe) |
| Legendary | **Star Cannon** | Projectile | Charge-up beam | Gathering light orb at the hand, then a thick gold-white beam with rings along it |
| Ascended | **Storm Sovereign** | AoE | Lightning strikes around you | Dark cloud ring overhead, 5–6 branching bolts strike the ground, scorch marks |
| Ascended | **Inferno Wings** | Movement | Fire wings: leap and slam down | Flame wings on the back during the leap, fire shock ring + crater glow on landing |
| Mythic | **Void Eclipse** | AoE | Black sphere that pulls players in | Black sphere with a purple rim, swirling ribbons spiralling inward, distortion ring |
| Mythic | **Celestial Dragon** | Projectile | Dragon of light flies forward | Long glowing white-gold dragon ribbon with a head, trailing stars |
| Divine | **Heaven's Judgment** | AoE | Pillar of light crashes down after a short warning | Gold warning circle on the ground, then a huge white-gold pillar, halo rings, light shards |
| Secret | **Zero Hour** | AoE | Freezes time around you for 1.5 s | Screen goes greyscale, clock-face rings spread out, frozen particles hang in the air, rainbow shatter at the end |

- Every rarity from Common to Ascended has **2 abilities of different types**, so every event has something to boost.
- Stats (damage, cooldown, range, hitbox) come later, in the code config `Abilities.luau`.

## VFX built in Blender

**Who:** Claude drives Blender 5.2 with Python scripts (headless). The build scripts are the source of truth; each change is a small edit and a rerun.

**How Roblox VFX work:** Blender makes the **shapes** (meshes) and **painted textures**. Studio puts them together with particles, beams, lights and camera shake, timed to the attack animation. *(LIHFOLK: Mesh VFX Packs Built in Blender; Slash VFX Recipes)*

**Shared mesh kit** (built once, recoloured per ability, which saves memory on phones):
| Mesh | Used by |
|---|---|
| Crescent (thick + thin) | Blood Moon Slash, Ember Fist swing |
| Shock ring (flat) | Ember Fist, Frost Jab, Stone Wall, Inferno Wings, Heaven's Judgment, Zero Hour |
| Sphere shell | Void Eclipse, Star Cannon charge |
| Spear / bolt (crossed ribbons) | Thunder Lance, Storm Sovereign |
| Shards / crystal petals | Frost Jab, Frost Bloom, Heaven's Judgment |
| Tapered pillar | Heaven's Judgment, Star Cannon beam |
| Rock chunks + slab | Pebble Toss, Stone Wall |
| Swirl ribbon | Void Eclipse, Gale Step, Shadow Swap |
| Wing, dragon ribbon, clock rings | Inferno Wings, Celestial Dragon, Zero Hour (one-offs) |

**Rules** *(LIHFOLK)*:
- 1 Blender unit = 1 stud. Export `.glb`. In Studio: Import 3D with **Merge Meshes off**.
- Every VFX mesh in Studio: Anchored, CanCollide / CanTouch / CanQuery **off**, CastShadow off.
- Textures stay white/grey and are recoloured in Studio, so one texture serves many abilities.
- Slashes stay in front of the character (±100° of where they face). Every frame has 3 tones: white edge, main colour, dark smear.
- Spawn VFX on each client from one small "ability used" event, and pool the meshes (never create and destroy per hit).
- Each effect also gets a **low** version (2–3 layers) for phones and crowded fights.
- Previews are rendered at game camera distance with the Standard view transform. A preview is a check, not the result: judge every effect in Studio at game speed, on a phone too.

## Build order
1. Shared mesh kit + preview renders.
2. MVP abilities first: **Ember Fist, Thunder Lance, Blood Moon Slash** (one melee, one projectile, one big slash).
3. The rest in rarity order.

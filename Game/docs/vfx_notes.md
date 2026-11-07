# VFX notes for future skills

Short lessons from building skills end to end (Blender → Open Cloud → Studio). Add to this after each skill.

## Frost Jab (Uncommon melee, 2026-11-06)

Preset: `Game/presets/ice_melee.lua`. Code: `src/client/Abilities/FrostJabVFX.luau`.
Scripts: `assets/vfx/_src/*frost_jab*.py`, `tools/build_frost_jab_templates.luau`.

### What worked

- **Rig check first.** Reading every joint and part size from the live Training Dummy and comparing it with the Blender rig (to 0.0001 studs) meant the Studio playback matched Blender to 0.22° on every limb.
- **Full stop at the anticipation apex.** Give every channel flat Bezier handles on the wind-up frame, then let the hips, torso and arm lead the strike by fractions of a frame. Auto-clamped handles alone leave a cusp in the fist's path.
- **Sample the motion path 100× per frame** when checking for zig-zags. At 10× per frame, a smooth stop-and-reverse looks like a cusp.
- **Normalize quaternions when exporting.** Bezier-blended quaternion channels drift off unit length between keys (to 0.92 on a fast snap). Blender normalizes them for display; the exporter must do the same.
- **Mesh IDs from Model uploads.** Studio can't load the uploaded FBX package ("not authorized"). Download it with the same API key (Open Cloud asset-delivery), un-gzip it and read the `rbxassetid://` string (`upload_frost_jab_assets.py`).
- **Imported meshes are centred on their bounding box.** Record the Blender origin's offset from the box centre (`frost_jab_meshes.json`) and store it on each template as `OriginFromCentre`.
- **Emitters on BaseParts emit from the part's volume.** Mist on the ring mesh, glints on the torso and flakes on the head need no extra attachments, which helps the instance budget.
- **Timestamped capture for comparisons.** Run the cast at 0.1×, take window screenshots named by UTC milliseconds (PowerShell `PrintWindow`), and pick each reference moment by game time. That lands within 0.006 s of every panel.
- **Proving server rules needs a Studio-only server hook.** `ServerStorage.Dev.AbilityTestHook` is a BindableFunction, not a remote, and is only created in Studio. It's how you test things the cooldown forbids, such as a double hit inside a slow.

### What to avoid

- **Duplicate keys in a CONFIG table.** `MAIN` was both a colour and a layer block; the later one silently won and broke `Color3.fromHex`. Keep colours under `PALETTE`.
- **Setting `Attachment.WorldPosition` before parenting.** It becomes a local offset, so the flash and light appeared about 15 studs away. Parent first.
- **A grace delay on the marker fallback.** When the "Hit" marker didn't fire (a test rig), a 0.08 s grace put the flash 2 frames late. Let the timer race the marker instead.
- **Huge or bright flashes with Bloom on.** 11-stud flares, glow 7 and light 5 whited out the frame. The star should carry the flash at about the target's size (6 studs, brightness ~1.1).
- **Long, fast shard flights.** 6–9 studs in 0.4 s left the frame in 0.03 s. 2–3.5 studs up and out over 0.6 s reads like the reference.
- **Generic hit flashes in another skill's palette.** The shared orange `HitEffect` flash had to be skipped for Frost Jab (`CombatController.OWN_HIT_FLASH`).
- **Enum names:** it's `Enum.EasingStyle.Exponential`, not `Expo`.
- **The first VFX cast of a Play session creates `workspace.ClientVFX`.** Measure the cleanup count (descendants before vs 3 s after) from the second cast.
- **The 3 s cooldown hides the "no stacking" case.** One player can't re-hit inside a 1.5 s slow, so test it with the server hook.

## Thunder Lance stage 7B: sky lightning strike on a character hit (2026-11-08)

The spear's full notes come with section 9. This part covers the strike add-on (`Prompts/thunder_lance_lighting_strike_prompt`).
Preset keys: `Game/presets/lightning_projectile.lua` (`STRIKE` block). Code: `src/client/Abilities/ThunderLanceVFX.luau` (`ThunderLanceVFX.Strike`), `src/client/VFX/LightningBolt.luau` (`Layers`, `Branches`, `Hold`, `Intensity`, `Dim`, `Prewarm`), `AbilityService.skyStrike`, remote `AbilityStrike`.
Textures: `assets/vfx/textures/crater.png`, `crater_glow.png` (`build_thunder_lance_textures.py`, `ONLY = (...)`).

### What worked

- **The server picks the spot, once, at the hit.** It raycasts down from the target's root (20 studs, characters excluded) and sends `AbilityStrike(target, groundPos, serverTime, seed)` right after `AbilityHit`. A target that dies, resets or leaves still gets the strike exactly there; nothing waits for the target.
- **One `Random` per layer, all from the server seed.** The charge redraws per render frame, so its random calls vary per client. With its own `Random(seed + 1)` the main bolt (`seed + 2`) is still the same on every screen.
- **Strokes as redraws plus dips.** Each stroke draws a new shape at a lower `Intensity` (1, 0.8, 0.65), and `Dim(0.35)` between strokes avoids a full blackout. It's ~0.29 s in total, and the Vault's "weaker later strokes" reads as real lightning.
- **Layered Beams per segment.** Outer gold 3.0 at 0.6 transparency, yellow 1.4, white core 0.5, each with a ZOffset. Branches draw only the middle and core layers, which keeps the strike at 90 Beams.
- **`LightEmission` below 1 for the coloured outer layers** (gold 0.25, yellow 0.7, core 1). With everything additive, the gold disappeared into white against the sky and bloom.
- **Glowing crack decal = a `SurfaceGui` image** (`LightInfluence` 0, `Brightness` 3) on the crater plate. A Decal can't glow.
- **Debris moved by code, not physics.** Anchored chips on a closed-form arc land on the floor and fade. That needs no VectorForce or Attachment per chip (14 instances, not 42), and they follow `TIME_SCALE` exactly.
- **Prewarming the bolt pool** (`LightningBolt.Prewarm(130)` on a cast) means the first cast creates the whole pool and later casts add 0 instances. Without it, the pool grew by 7 Beams on the 5th cast.
- **A killable test target:** clone a tagged Training Dummy into `ServerStorage.Dev` first, then move it into Workspace. CombatService's "dummies never die" setup only runs on dummies already in Workspace, so the clone can die. Destroy it after the test.

### What to avoid

- **Scheduling the next layer exactly when the last one fades.** The bolt's fade ended at 0.44 s and the ground arcs started at 0.45 s. At normal speed, a frame of overlap made 102 Beams (budget 90). Release the old layer explicitly when the next one starts.
- **Timestamping a capture after `PrintWindow`.** It takes ~100 ms, so every frame looked ~0.03 game seconds late at 0.25×. Stamp before grabbing.
- **Grabbing "the" Studio window** when a local server test is open: there are now "Server - Roblox Studio" / "Client - ..." windows too. `capture_studio_window.ps1` takes a title filter.
- **A test camera framed for the target only.** A 40-studs-up charge and a 45-stud bolt need the camera ~45 studs back and FOV 70.
- **Unlimited full-screen flashes.** The spear's flash, 3 strokes and the screen flash all land inside 0.5 s. Cap screen flashes at 3 per rolling second and keep `REDUCE_FLASHING` (Vault: WCAG 2.3.1).

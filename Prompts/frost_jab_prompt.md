# FROST JAB: build the full skill (animation + VFX + gameplay). I only review.

## 0. The ability
| Tier | Name | Type | Effect | VFX |
|---|---|---|---|---|
| Uncommon | Frost Jab | Melee | Icy punch that slows briefly | Blue-white flash, a few ice shards burst forward, frost ring on the target |

The attached images are the reference. Match them. When the reference and this file disagree, the reference wins for LOOK, and this file wins for RULES and NUMBERS.

Starting values (put them all in CONFIG; don't invent new gameplay numbers without asking me):
- Duration 0.45 s. Hit frame at 0.15 s. Cooldown 3 s. Damage 8.
- Hit area: a box 5 wide × 5 tall × 6 long in front of the attacker's HumanoidRootPart.
- Slow: target WalkSpeed × 0.6 for 1.5 s. Does not stack; a new hit refreshes the timer.
- Palette: core #F2FBFF, main #A8E6FF, deep #4FA3D9. No other colours.

## 1. Who does what
- I do NO manual work. You use the tools listed below. My job is to review what you show me and reply "ok" or give a fix.
- Work in the STAGES in section 7. At the end of each stage: run its checks, fix anything that fails, show me the proof, then STOP and wait for my "ok".
- If something truly needs me (a login, an API key, one click Roblox won't allow scripts to do), stop and give me numbered steps that take under 2 minutes.
- Never say something is done, exported, uploaded or tested unless you actually did it and checked the result. If a check failed or you skipped it, say so.

## 2. Tools: check these first (Stage 0)
1. Blender MCP: run get_scene_info. Use only ONE open Blender window for the whole task.
2. Roblox Studio MCP (Studio's built-in MCP server, or the Roblox studio-rust-mcp-server): read game.Workspace with run_code.
3. Open Cloud: ROBLOX_API_KEY in .env with Assets read/write permission, plus my creator user ID or group ID.
4. Screenshots: Blender MCP's viewport screenshot for Blender. For Studio, take an OS screenshot of the Studio window from the shell (for example PowerShell on Windows, screencapture on macOS), then open the image with the Read tool so you actually look at it.
5. Python with Pillow, for contact sheets, GIFs and flipbook packing.
6. If the "animate-roblox-characters" skill is installed, follow its animation phases for Stage 2. The rules below still apply on top of it.
If anything is missing, tell me exactly how to set it up and wait.

## 3. Project rules
- Read the existing skills first (EmberFist, PebbleToss, GaleStep, or whatever exists) and copy their folder layout, module pattern, remote setup and CONFIG style. Reuse presets/ if a similar effect exists.
- Code goes in the project files (Rojo/src if the project uses it). Templates go in ReplicatedStorage/VFX/FrostJab. Never leave test objects in Workspace; they go in ServerStorage/Dev.
- Blender work is saved to assets/frost_jab.blend after every stage. Never overwrite the original rig file.
- 1 stud = 1 Blender unit. 30 fps everywhere.

## 4. How to make the ANIMATION (rules)
Rig
- Use the REAL R15 rig from my game. Read every Motor6D (Part0, Part1, C0, C1) and every part's size from Studio with run_code. Build or match the Blender armature to those numbers, with the same joint names and hierarchy. Convert Roblox Y-up to Blender Z-up correctly.
- If a matching armature already exists in assets/ (from earlier skills), check it against Studio before reusing it.
- Never rename, add or remove bones. Never move the root or HumanoidRootPart in the animation (no root motion).

Order of work: block, then spline, then polish
1. BLOCKING: key poses only, with CONSTANT (stepped) interpolation. Make poses for: ready stance, anticipation, the hit, overshoot, recovery, and back to stance.
2. Screenshot every key pose from the SIDE and a 3/4 FRONT view, next to the matching reference panel. Fix poses before moving on. Bad poses can't be fixed later with curves.
3. SPLINING: switch to Bezier. Anticipation → hit must take 2–3 frames (fast). After the hit, hold for 2 frames and then ease out slowly.
4. POLISH in the Graph Editor: offset the timing so the hips move first, then the torso 1 frame later, then the shoulder and arm 1–2 frames after that (overlap). Add a small overshoot on the hit and settle back.

Checks to run with a script on every animation (print the numbers):
- Elbows and knees bend 0–150° and only in their natural direction. No backwards bends.
- Wrists rotate no more than 60° away from the forearm direction, and the fist faces the target on the hit frame.
- Feet: a planted foot may not move more than 0.05 studs while planted. Report the largest drift.
- Root drift: 0.
- The first and last frames are the same ready pose (within 1°), so it blends cleanly.
- The punching hand moves in a smooth arc. Turn on Blender Motion Paths for the hand bone and screenshot it. No zig-zags or sudden direction changes.
- The hit frame is when the punching hand is furthest forward. Report that frame number and check it matches CONFIG (0.15 s = frame 4–5).

Proof to show me:
- Side and 3/4 screenshots of every key pose next to the reference.
- An animated GIF rendered from Blender (not a screen recording), side view, 30 fps, plus a 0.25× speed version.
- The script check results.

Getting it into Roblox
- Build a KeyframeSequence in Studio with run_code from the Blender data. Sample EVERY frame and convert each bone's pose into Motor6D transforms relative to the rest pose. Add a KeyframeMarker named "Hit" on the hit frame.
- To test in Studio, use KeyframeSequenceProvider:RegisterKeyframeSequence.
- Proof: play the animation in Studio and screenshot frames 0, the anticipation, the hit and the recovery next to the same Blender frames. If any limb differs by more than about 5°, the conversion is wrong. Fix the conversion; don't change the poses to cover it up.
- To publish: try uploading the animation as .rbxm with Open Cloud (assetType Animation). If Roblox refuses that, save it in the rig's AnimSaves and give me the one-click publish step. Put the final asset ID in CONFIG.

## 5. How to make the VFX (rules)
Layers: every effect is built from these 4 roles, in this order
1. FLASH: 0.05–0.1 s, the brightest part, very large, gone almost instantly.
2. MAIN: the effect's main shapes (here, the ice shards). It peaks fast, then fades slowly.
3. SECONDARY: supporting shapes (here, the frost ring on the target and cold mist).
4. RESIDUAL: small leftovers that linger 0.5–1.5 s (sparkles, frost dust, a frost mark on the target).
Each layer is a separate object with its own CONFIG block. Nothing pops in or out: everything scales or fades.

Blender: meshes
- Low poly: under 300 triangles for the whole skill. Flat or slightly smoothed shading, as the reference shows.
- Every VFX mesh gets UVs laid out so a gradient texture runs along its length (or around it, for rings).
- Origin at the point where the effect is attached (the base of a shard, the centre of a ring). Apply all transforms.
- Make 3–5 variants of anything that repeats (like shards), so random choices don't look copy-pasted.
- Export each mesh as its own file. Screenshot all of them next to the rig for scale.

Blender: textures and flipbooks
- White or greyscale on a transparent background. Colour is ALWAYS added in Roblox, never baked into the texture.
- Render with an orthographic camera facing the plane, Film set to Transparent, a black-and-white view transform (Standard, not AgX/Filmic), and no lights affecting emission shaders.
- Sizes: 256 for sparkles and glows, 512 for streaks and rings, 1024 for flipbooks.
- Flipbooks: animate the shader (noise and distortion moving over time). Render 16 frames, then pack them into a 4×4 grid with Pillow in reading order. Show me frames 1, 5, 9 and 13 enlarged.
- Check every texture on a dark AND a light background, and check the edges for halos (white fringes). Fix the alpha if you find them.

Roblox: building the effect
- All templates live in ReplicatedStorage/VFX/FrostJab. Positions come from Attachments placed on the rig (RightHand, the target's HumanoidRootPart), never from hard-coded positions in the world.
- ParticleEmitters: Enabled = false, fired with :Emit(count) at the right moment. LightEmission 1 for glow layers. Size and Transparency curves need at least 3 points (grow fast, then shrink or fade slowly). Use ZOffset so layers stack in the right order. Use Squash for streak-like particles. LockedToPart only for effects that should follow the body.
- Flipbook emitters: FlipbookLayout must match the grid, FlipbookMode OneShot, and the framerate set so the flipbook ends exactly when the particle dies.
- MeshPart effects: Anchored, CanCollide/CanQuery/CanTouch false, CastShadow false, Massless. Animate with TweenService (Size, CFrame, Transparency). Use the easing style from CONFIG (Quint/Expo Out for pops, Sine for fades).
- Lights: one PointLight on the flash, fading to 0 within 0.2 s.
- Every time value is multiplied by CONFIG.TIME_SCALE, so 0.25× slow-motion tests use the exact same code.
- Budget: no more than 120 particles alive and 15 VFX instances per cast.

Networking and cleanup
- The attacker's client plays the animation and the startup VFX immediately (no waiting on the server).
- The SERVER decides the hit. Then it tells ALL clients through one RemoteEvent to play the on-hit VFX (ring and shards on the target). Send only IDs and positions, never Instances you created on the client. Use workspace:GetServerTimeNow() timestamps so late clients skip effects that have already finished.
- Clean up everything with Debris or a timer. Test: count the descendants of Workspace before a cast and 3 s after it. The numbers must match.

## 6. How to make the GAMEPLAY (rules)
- The server owns everything. The client only sends "I pressed the skill". The server checks the cooldown, that the player is alive, and a rate limit (no more than 1 request per 0.25 s).
- Hit detection on the server at the hit time: workspace:GetPartBoundsInBox using the CONFIG box in front of the attacker, ignoring the attacker. Each target can be hit at most once per cast.
- Slow: store it as an attribute or status (for example SlowMultiplier and SlowEndsAt) and calculate WalkSpeed from it in one place. It must ALWAYS be removed when it runs out, even if the target dies, resets or leaves. A new hit refreshes the timer; it never multiplies again.
- Check your code against my existing remote and security patterns (use the roblox-security skill if installed).

## 7. Stages (stop after each one)
- Stage 0: Tools check (section 2) and reading the project (section 3). Show me what you found and your plan.
- Stage 1: Rig match. Screenshot the Studio rig next to the Blender armature, front view, plus a table of the joint positions compared.
- Stage 2: Animation blocking. Show the key pose screenshots next to the reference. STOP.
- Stage 3: Animation spline and polish. Show the GIFs, the motion path and the script check results. STOP.
- Stage 4: Roblox animation. Show the Studio vs Blender comparison and the asset ID (or the one-click step).
- Stage 5: VFX assets (meshes, textures, flipbook). Show the contact sheets.
- Stage 6: VFX build and gameplay code. Add the chat command /vfxtest frost, which loops the skill at TIME_SCALE 0.25 against a Training Dummy.
- Stage 7: Compare with the reference. Screenshot the moments that match each reference panel and stitch them side by side with the panels into ONE image (use Pillow). List the 3 biggest differences, fix them, and re-shoot. Then show proof of: the slow working (WalkSpeed before, during and after), no stacking on a double hit, the cleanup count, and a miss when the target is just outside the box.

## 8. Finally
- List every file, asset ID, script and instance you created.
- Report anything you couldn't do or aren't sure about.
- Save the final CONFIG as presets/ice_melee.lua, and add a short "what worked / what to avoid" note to docs/vfx_notes.md for future skills.

## Reference links (read if needed)
- Roblox Studio MCP: https://github.com/Roblox/studio-rust-mcp-server
- Open Cloud asset upload (Animation as .rbxm): https://create.roblox.com/docs/cloud/guides/usage-assets
- AI Roblox animation skill (phases, audits, GIF checks): https://github.com/dillydog580/animate-roblox-characters
- Blender → Roblox export pitfalls: https://nilo.io/articles/export-animation-blender-roblox
- Mesh flipbooks in Roblox: https://devforum.roblox.com/t/what-are-mesh-flipbooks/2656999

"""Spin for Abilities - Frost Jab, stage 5: ice textures + cold mist flipbook (Blender 5.2).

Run inside Blender with Game/assets/frost_jab.blend open:
    exec(open(r"<this file>").read())
White/grey + straight alpha on a transparent background; colour is ALWAYS added in Roblox
(palette core #F2FBFF, main #A8E6FF, deep #4FA3D9). Static textures are drawn per pixel with numpy
(the project's method, as build_gale_step_textures.py / build_pebble_toss_textures.py). The flipbook
is an animated noise shader on a plane in its own scene ("FrostJab_Flipbook"): orthographic camera
facing the plane, Film Transparent, Standard view transform, pure emission (no lights), EEVEE,
16 frames packed into a 4x4 grid in reading order.
Every texture gets its colour bled into the transparent pixels (RGB of a=0 pixels = the colour of
the nearest visible pixels), so Roblox's filtering never pulls black/odd colours into the edges
(the halo / fringe check in report()).

Reused, not rebuilt (already uploaded for Gale Step and the same shape the frost reference shows):
    sparkle.png    4-point diamond glint          rbxassetid://76795312198770
    soft_glow.png  soft round glow                 rbxassetid://134061496595746

Outputs (Game/assets/vfx/textures/):
    frost_flare.png          256x256   6-ray ice flash: long uneven rays, hot core (flash layer)
    frost_snowflake.png      256x256   6-arm snowflake with side branches (residual, panels 8-11)
    frost_shard.png          512x512   crystal gradient for the shard / spike meshes: V = 0 (bottom
                                       row) = base, darker grey and a little see-through -> V = 1
                                       (top row) = tip, white; fine vertical ice striations; tiles
                                       seamlessly in U (around the shard)
    frost_ring.png           512x512   ring band for frost_ring: U = around (tiles seamlessly),
                                       V = across: inner edge (bottom) soft and faint -> frosty body
                                       -> crisp bright rim near the outer edge (top), streaks along U
    frost_mist_flipbook.png  1024x1024 4x4 = 16 frames of a cold mist puff: billows out, curls and
                                       thins into wisps; frames also kept as previews/frost_jab/mist_##.png
"""
import bpy, math, os
import numpy as np

TEX_DIR = r"C:\Roblox\Spin for ability\Game\assets\vfx\textures"
FRAME_DIR = r"C:\Roblox\Spin for ability\Game\assets\vfx\previews\frost_jab"
FLIP_SCENE = "FrostJab_Flipbook"
FLIP_FRAMES, FLIP_CELL = 16, 256


# --- helpers (as in build_gale_step_textures.py) ---------------------------------------------------
def save_png(path, rgba):
    """rgba: float array (h, w, 4) in 0..1, row 0 = top."""
    h, w, _ = rgba.shape
    name = os.path.basename(path)
    old = bpy.data.images.get(name)
    if old:
        bpy.data.images.remove(old)
    img = bpy.data.images.new(name, width=w, height=h, alpha=True)
    img.pixels.foreach_set(np.flipud(np.clip(rgba, 0, 1)).astype(np.float32).ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    return path


def load_png(path):
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return np.flipud(px.reshape(h, w, 4))


def grid(w, h):
    """x in -1..1 left->right, y in -1..1 top->bottom (pixel centres)."""
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    return (x + 0.5) / w * 2 - 1, (y + 0.5) / h * 2 - 1


def smoothstep(e0, e1, v):
    t = np.clip((v - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def periodic_noise(u, freqs, seed):
    """Smooth noise that tiles exactly at u = 0 / 1: a sum of sines with whole-number frequencies."""
    rnd = np.random.default_rng(seed)
    out = np.zeros_like(u)
    total = 0.0
    for f in freqs:
        amp = 1.0 / math.sqrt(f)
        out += amp * np.sin(2 * math.pi * (f * u + rnd.random()))
        total += amp
    return out / total * 0.5 + 0.5


def bleed(rgba, passes=24):
    """Fill the RGB of (nearly) transparent pixels with the alpha-weighted average of their visible
    neighbours, growing outward; alpha is untouched. Stops dark/odd fringes when Roblox filters."""
    rgb, a = rgba[..., :3].copy(), rgba[..., 3]
    known = a > 0.02
    w = known.astype(np.float32)
    acc = rgb * w[..., None]
    for _ in range(passes):
        pad_acc = np.pad(acc, ((1, 1), (1, 1), (0, 0)), mode="edge")
        pad_w = np.pad(w, 1, mode="edge")
        s_acc = sum(pad_acc[1 + dy:pad_acc.shape[0] - 1 + dy, 1 + dx:pad_acc.shape[1] - 1 + dx]
                    for dy in (-1, 0, 1) for dx in (-1, 0, 1))
        s_w = sum(pad_w[1 + dy:pad_w.shape[0] - 1 + dy, 1 + dx:pad_w.shape[1] - 1 + dx]
                  for dy in (-1, 0, 1) for dx in (-1, 0, 1))
        grow = (~known) & (s_w > 0)
        rgb[grow] = s_acc[grow] / s_w[grow][..., None]
        known = known | grow
        w = known.astype(np.float32)
        acc = rgb * w[..., None]
    rgb[~known] = 1.0
    return np.dstack([rgb, a])


# --- static textures -----------------------------------------------------------------------------
def frost_flare(n=256):
    """6 uneven rays (two long diagonals, like the blue flash reference) + hot core + soft halo."""
    x, y = grid(n, n)
    r = np.sqrt(x * x + y * y)
    ang = np.arctan2(y, x)
    alpha = np.zeros_like(x)
    # (angle deg, length, half-width at the root in radians-ish)
    for deg, length, width in ((28, 0.97, 0.16), (208, 0.92, 0.16), (95, 0.78, 0.14), (275, 0.72, 0.14),
                               (152, 0.64, 0.12), (332, 0.60, 0.12)):
        d = np.angle(np.exp(1j * (ang - math.radians(deg))))     # wrapped angle difference
        taper = np.clip(1 - r / length, 0, 1)
        w = width * taper ** 0.6 + 1e-3
        ray = np.exp(-(d * np.maximum(r, 0.05) / (w * 0.6)) ** 2) * taper ** 0.9
        alpha = np.maximum(alpha, ray)
    core = np.exp(-(r / 0.18) ** 2)
    halo = np.exp(-(r / 0.40) ** 2) * 0.5
    alpha = np.clip(np.maximum(alpha, np.maximum(core, halo)), 0, 1) * smoothstep(1.0, 0.94, r)
    shade = np.clip(0.75 + 0.25 * np.maximum(core * 1.2, smoothstep(0.6, 0.0, r)), 0, 1)
    return np.dstack([shade, shade, shade, alpha])


def _segment_dist(x, y, ax, ay, bx, by):
    px, py = x - ax, y - ay
    vx, vy = bx - ax, by - ay
    t = np.clip((px * vx + py * vy) / (vx * vx + vy * vy), 0, 1)
    return np.sqrt((px - t * vx) ** 2 + (py - t * vy) ** 2), t


def frost_snowflake(n=256):
    """6 arms, each with 2 pairs of side branches; thick crisp lines, small hexagon core."""
    x, y = grid(n, n)
    alpha = np.zeros_like(x)
    for k in range(6):
        a = math.pi / 2 + k * math.pi / 3
        ca, sa = math.cos(a), math.sin(a)
        segs = [((0, 0), (0.86 * ca, 0.86 * sa), 0.050)]
        for at, length in ((0.42, 0.28), (0.64, 0.18)):
            bx, by = at * ca, at * sa
            for side in (-1, 1):
                b = a + side * math.radians(55)
                segs.append(((bx, by), (bx + length * math.cos(b), by + length * math.sin(b)), 0.036))
        for (ax, ay), (bx, by), half in segs:
            d, t = _segment_dist(x, y, ax, ay, bx, by)
            alpha = np.maximum(alpha, smoothstep(0.012, 0.0, d - half * (1 - 0.45 * t)))
    r = np.sqrt(x * x + y * y)
    hexa = np.max(np.stack([np.abs(x * math.cos(t) + y * math.sin(t)) for t in
                            (math.pi / 6, math.pi / 2, 5 * math.pi / 6)]), axis=0)
    alpha = np.maximum(alpha, smoothstep(0.17, 0.155, hexa))
    alpha *= smoothstep(1.0, 0.95, r)
    shade = np.clip(0.8 + 0.2 * smoothstep(0.7, 0.0, r), 0, 1)
    return np.dstack([shade * np.ones_like(x), shade * np.ones_like(x), shade * np.ones_like(x), alpha])


def frost_shard(n=512):
    """Rows: top = tip (V = 1), bottom = base (V = 0). Columns: U around the shard (tiles)."""
    x, y = grid(n, n)
    u = (x + 1) / 2
    v = 1 - (y + 1) / 2                                          # 1 at the top row
    stria = periodic_noise(u, (3, 5, 8, 13, 21), 11)             # vertical streaks, constant along V
    fine = periodic_noise(u, (34, 55), 12)
    grad = smoothstep(0.0, 1.0, v)
    shade = 0.55 + 0.35 * grad + 0.10 * (stria - 0.5) + 0.06 * (fine - 0.5)
    shade = np.clip(shade + 0.25 * smoothstep(0.82, 1.0, v), 0, 1)   # white-hot tip
    alpha = np.clip(0.78 + 0.22 * grad + 0.08 * (stria - 0.5), 0, 1)
    return np.dstack([shade, shade, shade, alpha])


def frost_ring(n=512):
    """Rows: top = outer edge (V = 1), bottom = inner edge (V = 0). Columns: U around the ring."""
    x, y = grid(n, n)
    u = (x + 1) / 2
    v = 1 - (y + 1) / 2
    streak = periodic_noise(u, (4, 7, 11, 17, 29, 41), 21)
    wob = (periodic_noise(u, (5, 9, 14), 22) - 0.5) * 0.06      # rim is not ruler-straight
    body = smoothstep(0.0, 0.55, v) * 0.55 * (0.65 + 0.7 * streak)
    rim = smoothstep(0.70 + wob, 0.84 + wob, v) * smoothstep(0.98, 0.90 + wob, v)
    alpha = np.clip(np.maximum(body, rim), 0, 1)
    shade = np.clip(0.62 + 0.38 * np.maximum(rim, 0.5 * streak * smoothstep(0.3, 0.8, v)), 0, 1)
    return np.dstack([shade, shade, shade, alpha])


# --- flipbook: animated cold mist shader --------------------------------------------------------------
def flip_params(f):
    """Frame f (0..15): billow out fast (0-5), curl + drift (4-10), thin into wisps and fade (9-15)."""
    t = f / (FLIP_FRAMES - 1)
    return {
        "radius": 0.30 + 0.62 * (1 - (1 - t) ** 2),              # expands fast, then slows
        "swirl": 0.4 + 2.4 * t,                                  # curls as it spreads
        "evolve": 6.0 * t,                                       # noise W: the billows change shape
        "dissolve": 0.10 + 0.55 * max(0.0, (f - 7) / 8) ** 1.3,   # eats the puff into wisps
        "gain": 0.9 * min(1.0, (f + 2) / 3) * (1.0 - 0.6 * max(0.0, (f - 11) / 4)),
    }


def flip_material():
    name = "FrostJab_Mist"
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.surface_render_method = "BLENDED"
    nt = mat.node_tree
    nt.nodes.clear()
    N, L = nt.nodes, nt.links

    def val(label, v):
        n = N.new("ShaderNodeValue")
        n.label = n.name = label
        n.outputs[0].default_value = v
        return n.outputs[0]

    def math_(op, a, b=None):
        n = N.new("ShaderNodeMath")
        n.operation = op
        for i, s in enumerate((a, b)):
            if s is None:
                continue
            if isinstance(s, (int, float)):
                n.inputs[i].default_value = s
            else:
                L.new(s, n.inputs[i])
        return n.outputs[0]

    def smooth(v, lo, hi):
        n = N.new("ShaderNodeMapRange")
        n.interpolation_type = "SMOOTHSTEP"
        n.clamp = True
        for sock, x in ((n.inputs["Value"], v), (n.inputs["From Min"], lo), (n.inputs["From Max"], hi)):
            if isinstance(x, (int, float)):
                sock.default_value = x
            else:
                L.new(x, sock)
        return n.outputs["Result"]

    P = {k: val(k, v) for k, v in flip_params(0).items()}
    tc = N.new("ShaderNodeTexCoord")
    p = N.new("ShaderNodeVectorMath")
    p.operation = "MULTIPLY_ADD"
    L.new(tc.outputs["UV"], p.inputs[0])
    p.inputs[1].default_value = (2, 2, 0)
    p.inputs[2].default_value = (-1, -1, 0)
    rlen = N.new("ShaderNodeVectorMath")
    rlen.operation = "LENGTH"
    L.new(p.outputs[0], rlen.inputs[0])
    r = rlen.outputs["Value"]
    # swirl: rotate by swirl * (1 - r) so the middle turns more than the edge
    rot = N.new("ShaderNodeVectorRotate")
    rot.rotation_type = "Z_AXIS"
    L.new(p.outputs[0], rot.inputs["Vector"])
    L.new(math_("MULTIPLY", P["swirl"], math_("SUBTRACT", 1.0, r)), rot.inputs["Angle"])
    # billows: 4D noise (W evolves), then a second noise warps it for wispy edges
    warp = N.new("ShaderNodeTexNoise")
    warp.noise_dimensions = "4D"
    warp.inputs["Scale"].default_value = 2.2
    warp.inputs["Detail"].default_value = 2.0
    L.new(rot.outputs[0], warp.inputs["Vector"])
    L.new(math_("ADD", P["evolve"], 10.0), warp.inputs["W"])
    wv = N.new("ShaderNodeVectorMath")
    wv.operation = "MULTIPLY_ADD"
    L.new(warp.outputs["Color"], wv.inputs[0])
    wv.inputs[1].default_value = (0.45, 0.45, 0)
    L.new(rot.outputs[0], wv.inputs[2])
    noise = N.new("ShaderNodeTexNoise")
    noise.noise_dimensions = "4D"
    noise.inputs["Scale"].default_value = 3.0
    noise.inputs["Detail"].default_value = 4.0
    noise.inputs["Roughness"].default_value = 0.55
    L.new(wv.outputs[0], noise.inputs["Vector"])
    L.new(P["evolve"], noise.inputs["W"])
    # round puff that grows with `radius`, soft edge
    puff = math_("SUBTRACT", 1.0, smooth(r, math_("MULTIPLY", P["radius"], 0.55), P["radius"]))
    dens = math_("MULTIPLY", puff, smooth(noise.outputs["Fac"], 0.30, 0.85))
    alpha = math_("MULTIPLY", smooth(dens, P["dissolve"], math_("ADD", P["dissolve"], 0.25)), P["gain"])
    alpha = math_("MINIMUM", alpha, 1.0)
    shade = math_("MINIMUM", math_("ADD", math_("MULTIPLY", dens, 0.35), 0.7), 1.0)
    emit = N.new("ShaderNodeEmission")
    L.new(shade, emit.inputs["Color"])
    emit.inputs["Strength"].default_value = 1.0
    transp = N.new("ShaderNodeBsdfTransparent")
    mix = N.new("ShaderNodeMixShader")
    L.new(alpha, mix.inputs["Fac"])
    L.new(transp.outputs[0], mix.inputs[1])
    L.new(emit.outputs[0], mix.inputs[2])
    out = N.new("ShaderNodeOutputMaterial")
    L.new(mix.outputs[0], out.inputs["Surface"])
    return mat


def flip_scene():
    old = bpy.data.scenes.get(FLIP_SCENE)
    if old:
        for ob in list(old.objects):
            data = ob.data
            bpy.data.objects.remove(ob, do_unlink=True)
            if isinstance(data, bpy.types.Mesh) and data.users == 0:
                bpy.data.meshes.remove(data)
            elif isinstance(data, bpy.types.Camera) and data.users == 0:
                bpy.data.cameras.remove(data)
        bpy.data.scenes.remove(old)
    sc = bpy.data.scenes.new(FLIP_SCENE)
    sc.render.fps = 30
    sc.frame_start, sc.frame_end = 0, FLIP_FRAMES - 1
    try:
        sc.render.engine = "BLENDER_EEVEE"
    except TypeError as e:
        print("engine:", e)
    sc.render.resolution_x = sc.render.resolution_y = FLIP_CELL
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    world = bpy.data.worlds.get("FrostJab_FlipbookWorld") or bpy.data.worlds.new("FrostJab_FlipbookWorld")
    world.color = (0, 0, 0)
    sc.world = world

    me = bpy.data.meshes.new("FrostJab_MistPlane")
    me.from_pydata([(-1, -1, 0), (1, -1, 0), (1, 1, 0), (-1, 1, 0)], [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new(name="UVMap")
    for loop, co in zip(uv.data, ((0, 0), (1, 0), (1, 1), (0, 1))):
        loop.uv = co
    plane = bpy.data.objects.new("FrostJab_MistPlane", me)
    sc.collection.objects.link(plane)
    mat = flip_material()
    me.materials.append(mat)

    cam = bpy.data.objects.new("FrostJab_MistCam", bpy.data.cameras.new("FrostJab_MistCam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 2.0
    cam.location = (0, 0, 5)
    sc.collection.objects.link(cam)
    sc.camera = cam

    nodes = mat.node_tree.nodes
    for f in range(FLIP_FRAMES):
        for k, v in flip_params(f).items():
            sock = nodes[k].outputs[0]
            sock.default_value = v
            sock.keyframe_insert("default_value", frame=f)
    return sc


def render_flipbook():
    sc = flip_scene()
    os.makedirs(FRAME_DIR, exist_ok=True)
    frames = []
    win = bpy.context.window
    main_scene = win.scene
    win.scene = sc                    # material animation is only evaluated for the window's scene
    try:
        for f in range(FLIP_FRAMES):
            sc.frame_set(f)
            sc.render.filepath = os.path.join(FRAME_DIR, f"mist_{f + 1:02d}.png")
            bpy.ops.render.render(write_still=True)
            frames.append(bleed(load_png(sc.render.filepath)))
            save_png(sc.render.filepath, frames[-1])
    finally:
        win.scene = main_scene
    sheet = np.zeros((FLIP_CELL * 4, FLIP_CELL * 4, 4), np.float32)
    for i, fr in enumerate(frames):
        row, col = divmod(i, 4)                                   # reading order
        sheet[row * FLIP_CELL:(row + 1) * FLIP_CELL, col * FLIP_CELL:(col + 1) * FLIP_CELL] = fr
    return sheet, frames


def report(name, im):
    """Size, coverage, alpha on the border (must be ~0 or the sprite gets cut off), and the halo check:
    the grey of semi-transparent edge pixels vs the grey inside. A dark or bright edge band = halo."""
    a = im[..., 3]
    g = im[..., :3].mean(axis=2)
    edge = max(a[0].max(), a[-1].max(), a[:, 0].max(), a[:, -1].max())
    ring_px = (a > 0.02) & (a < 0.35)
    inner = a > 0.8 if np.any(a > 0.8) else a > 0.5
    zero = a <= 0.02

    def span(mask):
        return f"{g[mask].min():.2f}..{g[mask].max():.2f}" if np.any(mask) else "none"

    print(f"{name}.png  {im.shape[1]}x{im.shape[0]}  alpha max {a.max():.2f}  covered {np.mean(a > 0.05) * 100:.0f}%"
          f"  border alpha {edge:.2f}  edge grey {span(ring_px)}  inside grey {span(inner)}"
          f"  transparent-pixel RGB {span(zero)}")


def build():
    os.makedirs(TEX_DIR, exist_ok=True)
    made = {"frost_flare": frost_flare(), "frost_snowflake": frost_snowflake(), "frost_shard": frost_shard(),
            "frost_ring": frost_ring()}
    for name, im in made.items():
        im = bleed(im)
        save_png(os.path.join(TEX_DIR, name + ".png"), im)
        report(name, im)
    sheet, frames = render_flipbook()
    save_png(os.path.join(TEX_DIR, "frost_mist_flipbook.png"), sheet)
    report("frost_mist_flipbook", sheet)
    for i, fr in enumerate(frames):
        a = fr[..., 3]
        print(f"  frame {i + 1:2d}: covered {np.mean(a > 0.05) * 100:4.1f}%  alpha max {a.max():.2f}"
              f"  border {max(a[0].max(), a[-1].max(), a[:, 0].max(), a[:, -1].max()):.2f}")
    bpy.ops.wm.save_mainfile()


build()

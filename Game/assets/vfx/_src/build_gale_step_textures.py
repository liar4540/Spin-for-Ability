"""Spin for Abilities - Gale Step, stage 3: wind textures + swirl flipbook (Blender 5.2).

Run inside Blender with Game/assets/gale_step.blend open:
    exec(open(r"<this file>").read())
White/grey + straight alpha, transparent background, tinted in Studio (#E9FBFF / #7FE6FF / #2FA8D8).
Static textures are drawn per pixel with numpy (same method as build_pebble_toss_textures.py).
The flipbook is an animated swirl/noise shader on a plane in its own scene ("GaleStep_Flipbook"),
rendered frame by frame with EEVEE and packed into a 4x4 grid.

Outputs (Game/assets/vfx/textures/):
    wind_gradient.png        1024x256  streak along U: solid at the LEFT (U = 0), fading out to the
                                       right, soft top/bottom edges, 3 thin streak lines inside
    wind_streaks.png         512x512   5 horizontal speed lines, solid LEFT, fading out RIGHT
    sparkle.png              256x256   sharp 4-point diamond sparkle, bright centre
    soft_glow.png            256x256   soft round radial glow
    wind_wisp.png            256x256   thin curved wind sliver, head at the TOP, fading tail below
                                       (ParticleEmitter Orientation = VelocityParallel: up = travel)
    wind_swirl_flipbook.png  1024x1024 4x4 grid = 16 frames (left to right, top to bottom) of a gust
                                       that sweeps in, curls into a 2-arm spiral and dissolves
    flipbook frames also kept as previews/gale_step/flipbook_##.png
"""
import bpy, math, os
import numpy as np

TEX_DIR = r"C:\Roblox\Spin for ability\Game\assets\vfx\textures"
FRAME_DIR = r"C:\Roblox\Spin for ability\Game\assets\vfx\previews\gale_step"
FLIP_SCENE = "GaleStep_Flipbook"
FLIP_FRAMES, FLIP_CELL = 16, 256


# --- helpers (as in build_pebble_toss_textures.py) -----------------------------------------------
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


def value_noise_1d(n, cells, seed):
    rnd = np.random.default_rng(seed)
    g = rnd.random(cells + 2).astype(np.float32)
    t = np.linspace(0, cells, n, endpoint=False, dtype=np.float32)
    i = t.astype(int)
    f = t - i
    f = f * f * (3 - 2 * f)
    return g[i] * (1 - f) + g[i + 1] * f


def smoothstep(e0, e1, v):
    t = np.clip((v - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


# --- static textures -----------------------------------------------------------------------------
def wind_gradient(w=1024, h=256):
    """Streak along U. Alpha: solid for the first 15 %, then (1 - t)^1.4 to nothing at U = 1; soft
    top/bottom edges; a brighter core band; 3 thin lines that run past the body before ending."""
    x, y = grid(w, h)
    u = (x + 1) / 2
    v = np.abs(y)                                               # 0 centre .. 1 edge
    head = smoothstep(0.0, 0.02, u)
    t = np.clip((u - 0.15) / 0.85, 0, 1)
    along = head * (1 - t) ** 1.4
    # body: soft edges, slight wobble so the edge is not ruler-straight
    wob = (value_noise_1d(w, 9, 3)[None, :] - 0.5) * 0.08
    body = smoothstep(0.92, 0.45, v + wob) * along
    core = smoothstep(0.38, 0.0, v) * along
    lines = np.zeros_like(u)
    for cy, thick, end in ((-0.55, 0.035, 0.80), (0.10, 0.03, 0.95), (0.62, 0.03, 0.70)):
        tl = np.clip(u / end, 0, 1)
        lines = np.maximum(lines, smoothstep(0.012, 0.0, np.abs(y - cy) - thick * (1 - tl)) * head * (1 - tl) ** 0.9)
    alpha = np.clip(np.maximum(body * 0.8, lines) + core * 0.2, 0, 1)
    shade = np.clip(0.72 + 0.28 * np.maximum(core, lines), 0, 1)
    return np.dstack([shade, shade, shade, alpha])


def wind_streaks(n=512):
    """5 horizontal speed lines, thick and solid at the left, tapering and fading to the right."""
    x, y = grid(n, n)
    u = (x + 1) / 2
    alpha = np.zeros_like(x)
    # (centre y, thickness at the left, start u, end u)
    for cy, thick, u0, u1 in ((-0.62, 0.035, 0.06, 0.74), (-0.30, 0.060, 0.00, 1.00), (0.00, 0.075, 0.02, 0.96),
                              (0.30, 0.050, 0.10, 0.86), (0.60, 0.035, 0.16, 0.68)):
        t = np.clip((u - u0) / (u1 - u0), 0, 1)
        half = thick * (1 - t) ** 0.8
        line = smoothstep(0.0, 0.01, half - np.abs(y - cy))
        alpha = np.maximum(alpha, line * smoothstep(u0, u0 + 0.008, u) * (1 - t) ** 1.5 * (u <= u1))
    shade = 0.85 + 0.15 * (1 - u)
    return np.dstack([shade, shade, shade, alpha])


def sparkle(n=256):
    """4-point diamond: concave-sided star |x|^p + |y|^p <= 1 (p = 0.55), vertical points longer,
    a bright round core and a faint halo; nothing touches the border."""
    x, y = grid(n, n)
    sx, sy = np.abs(x) / 0.62, np.abs(y) / 0.92
    star = (sx ** 0.55 + sy ** 0.55)
    shape = smoothstep(1.0, 0.94, star)
    r = np.sqrt(x * x + y * y)
    core = np.clip(1 - r / 0.16, 0, 1) ** 1.6
    halo = np.clip(1 - r / 0.45, 0, 1) ** 3 * 0.35
    alpha = np.clip(np.maximum(shape, np.maximum(core, halo)), 0, 1)
    # grey towards the points, brightening smoothly to pure white in the middle (no hard disc)
    shade = np.clip(0.72 + 0.28 * smoothstep(0.95, 0.15, star) + 0.3 * core, 0, 1)
    return np.dstack([shade, shade, shade, alpha])


def soft_glow(n=256):
    x, y = grid(n, n)
    r = np.sqrt(x * x + y * y)
    alpha = np.exp(-(r / 0.42) ** 2) * smoothstep(1.0, 0.85, r)
    return np.dstack([np.ones_like(r), np.ones_like(r), np.ones_like(r), alpha])


def wind_wisp(n=256):
    """Thin curved sliver along a gentle arc: head (solid, widest) near the top, tapering tail curling
    down and to the side, fading out. Long axis vertical so VelocityParallel aligns it with travel."""
    x, y = grid(n, n)
    alpha = np.zeros_like(x)
    # centre line: x = bend * (s^2), s = 0 at the head (top) .. 1 at the tail (bottom)
    y0, y1, bend = -0.85, 0.85, 0.45
    s = np.clip((y - y0) / (y1 - y0), 0, 1)
    cx = -0.12 + bend * s * s
    half = 0.10 * np.sin(np.pi * np.clip(s * 0.85 + 0.05, 0, 1)) ** 0.7 * (1 - s) ** 0.4
    d = np.abs(x - cx) / np.sqrt(1 + (2 * bend * s * 2 / (y1 - y0)) ** 2)
    body = smoothstep(0.0, 0.012, half - d) * (y >= y0) * (y <= y1)
    fade = smoothstep(0.0, 0.06, s) * (1 - s) ** 1.2
    alpha = body * fade
    shade = 0.8 + 0.2 * (1 - s)
    return np.dstack([shade * np.ones_like(x), shade * np.ones_like(x), shade * np.ones_like(x), alpha])


# --- flipbook: animated swirl shader ---------------------------------------------------------------
def flip_params(f):
    """Shader inputs for frame f (0..15): sweep in (0-3), curl tighter (3-9), dissolve (8-15)."""
    t = f / (FLIP_FRAMES - 1)
    appear = min(1.0, (f + 2) / 4)
    fade = 1.0 - 0.55 * max(0.0, (f - 11) / 4)
    return {
        "spin": -0.9 - 3.2 * t,                                  # whole gust turns as it curls
        "twist": 1.2 + 6.0 * t,                                  # arms wind tighter -> spiral
        "r_out": 0.95 - 0.22 * t,                                # contracts inward
        "r_in": 0.62 - 0.45 * min(1.0, f / 5) + 0.30 * max(0.0, (f - 9) / 6),  # sweeps in, hole re-opens
        "dissolve": 0.06 + 0.62 * max(0.0, (f - 8) / 7) ** 1.2,  # threshold eats the strands away
        "gain": 1.8 * appear * fade,
    }


def flip_material():
    name = "GaleStep_Swirl"
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

    def math_(op, a, b=None, c=None):
        n = N.new("ShaderNodeMath")
        n.operation = op
        for i, s in enumerate((a, b, c)):
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
    # rotate each point by spin + twist * (1 - r)^2 -> straight arms become curling spiral arms
    ang = math_("ADD", P["spin"], math_("MULTIPLY", P["twist"], math_("POWER", math_("SUBTRACT", 1.0, r), 2.0)))
    rot = N.new("ShaderNodeVectorRotate")
    rot.rotation_type = "Z_AXIS"
    L.new(p.outputs[0], rot.inputs["Vector"])
    L.new(ang, rot.inputs["Angle"])
    sep = N.new("ShaderNodeSeparateXYZ")
    L.new(rot.outputs[0], sep.inputs[0])
    theta = math_("ARCTAN2", sep.outputs["Y"], sep.outputs["X"])
    # 2 crescent arms: x = fract(theta / pi) runs 0..1 across each half turn; crisp leading edge at
    # x = 0 (the side the gust turns toward), long fading tail behind it -> anime swoosh profile
    x = math_("FRACT", math_("DIVIDE", theta, math.pi))
    profile = math_("MULTIPLY", smooth(x, 0.0, 0.035), math_("POWER", math_("SUBTRACT", 1.0, x), 5.0))
    lopsided = math_("MULTIPLY_ADD", math_("COSINE", theta), 0.2, 0.8)     # one arm a bit stronger
    arms = math_("MULTIPLY", profile, lopsided)
    # fine streak lines that follow the swirl: 3D noise on (unit direction * 1.4, r * 26)
    unit = N.new("ShaderNodeVectorMath")
    unit.operation = "NORMALIZE"
    L.new(rot.outputs[0], unit.inputs[0])
    comb = N.new("ShaderNodeVectorMath")
    comb.operation = "MULTIPLY_ADD"
    L.new(unit.outputs[0], comb.inputs[0])
    comb.inputs[1].default_value = (1.4, 1.4, 0)
    rz = N.new("ShaderNodeCombineXYZ")
    L.new(math_("MULTIPLY", r, 26.0), rz.inputs["Z"])
    L.new(rz.outputs[0], comb.inputs[2])
    noise = N.new("ShaderNodeTexNoise")
    noise.noise_dimensions = "3D"
    noise.inputs["Scale"].default_value = 1.6
    noise.inputs["Detail"].default_value = 3.0
    noise.inputs["Roughness"].default_value = 0.5
    L.new(comb.outputs[0], noise.inputs["Vector"])
    streak = smooth(noise.outputs["Fac"], 0.42, 0.62)
    band = math_("MULTIPLY", smooth(r, P["r_in"], math_("ADD", P["r_in"], 0.16)),
                 math_("SUBTRACT", 1.0, smooth(r, math_("SUBTRACT", P["r_out"], 0.22), P["r_out"])))
    body = math_("MULTIPLY", arms, band)
    dens = math_("MULTIPLY", body, math_("MULTIPLY_ADD", streak, 0.6, 0.55))
    alpha = math_("MULTIPLY", smooth(dens, P["dissolve"], math_("ADD", P["dissolve"], 0.18)), P["gain"])
    alpha = math_("MINIMUM", alpha, 1.0)
    # brightest right behind the leading edge (white core), greyer in the tail
    shade = math_("MINIMUM", math_("MULTIPLY_ADD", body, 0.35, 0.68), 1.0)
    emit = N.new("ShaderNodeEmission")
    L.new(shade, emit.inputs["Color"])                          # grey -> RGB
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
    world = bpy.data.worlds.get("GaleStep_FlipbookWorld") or bpy.data.worlds.new("GaleStep_FlipbookWorld")
    world.color = (0, 0, 0)
    sc.world = world

    me = bpy.data.meshes.new("GaleStep_SwirlPlane")
    me.from_pydata([(-1, -1, 0), (1, -1, 0), (1, 1, 0), (-1, 1, 0)], [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new(name="UVMap")
    for loop, co in zip(uv.data, ((0, 0), (1, 0), (1, 1), (0, 1))):
        loop.uv = co
    plane = bpy.data.objects.new("GaleStep_SwirlPlane", me)
    sc.collection.objects.link(plane)
    mat = flip_material()
    me.materials.append(mat)

    cam = bpy.data.objects.new("GaleStep_SwirlCam", bpy.data.cameras.new("GaleStep_SwirlCam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 2.0
    cam.location = (0, 0, 5)
    sc.collection.objects.link(cam)
    sc.camera = cam

    # key every shader input on every frame (so the scene scrubs in Blender too)
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
    # the material animation is only evaluated for the window's scene: switch to it while rendering
    win = bpy.context.window
    main_scene = win.scene
    win.scene = sc
    try:
        for f in range(FLIP_FRAMES):
            sc.frame_set(f)
            sc.render.filepath = os.path.join(FRAME_DIR, f"flipbook_{f + 1:02d}.png")
            bpy.ops.render.render(write_still=True)
            frames.append(load_png(sc.render.filepath))
    finally:
        win.scene = main_scene
    sheet = np.zeros((FLIP_CELL * 4, FLIP_CELL * 4, 4), np.float32)
    for i, fr in enumerate(frames):
        row, col = divmod(i, 4)
        sheet[row * FLIP_CELL:(row + 1) * FLIP_CELL, col * FLIP_CELL:(col + 1) * FLIP_CELL] = fr
    return sheet, frames


def report(name, im):
    a = im[..., 3]
    edge = max(a[0].max(), a[-1].max(), a[:, 0].max(), a[:, -1].max())
    print(f"{name}.png  {im.shape[1]}x{im.shape[0]}  alpha max {a.max():.2f}  covered {np.mean(a > 0.05) * 100:.0f}%"
          f"  alpha on the border {edge:.2f}  grey {im[..., :3][a > 0.05].min():.2f}..{im[..., :3].max():.2f}")


def build():
    os.makedirs(TEX_DIR, exist_ok=True)
    made = {"wind_gradient": wind_gradient(), "wind_streaks": wind_streaks(), "sparkle": sparkle(),
            "soft_glow": soft_glow(), "wind_wisp": wind_wisp()}
    for name, im in made.items():
        save_png(os.path.join(TEX_DIR, name + ".png"), im)
        report(name, im)
    sheet, frames = render_flipbook()
    save_png(os.path.join(TEX_DIR, "wind_swirl_flipbook.png"), sheet)
    report("wind_swirl_flipbook", sheet)
    for i, fr in enumerate(frames):
        a = fr[..., 3]
        print(f"  frame {i + 1:2d}: covered {np.mean(a > 0.05) * 100:4.1f}%  alpha max {a.max():.2f}"
              f"  border {max(a[0].max(), a[-1].max(), a[:, 0].max(), a[:, -1].max()):.2f}")
    bpy.ops.wm.save_mainfile()


build()

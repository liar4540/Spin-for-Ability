"""Spin for Abilities - Thunder Lance, stage 5 (+ stage 7B crater): VFX textures, rendered in Blender (5.2).

Run inside Blender with Game/assets/thunder_lance.blend open:
    exec(open(r"<this file>").read())
To build only some of them (the others are already uploaded; re-rendering would change their bytes):
    ONLY = ("crater", "crater_glow"); exec(open(r"<this file>").read())
Each texture is a procedural shader (emission for brightness, mixed with Transparent by the alpha
mask) on a plane that fills an ORTHOGRAPHIC camera, rendered with Cycles, Film Transparent and the
Standard view transform (no AgX / Filmic), in its own scene "ThunderLance_Textures" (removed after).
Then, as for Frost Jab: white textures get pure white RGB (brightness lives in the alpha), the scorch
keeps its dark grey, and every texture's colour is bled into its transparent pixels so Roblox's
filtering can't pull dark or odd colours into the edges (halo / fringe check in report()).
Colour is ALWAYS added in Roblox (palette white #FFFDF0, yellow #FFE14D, deep gold #FFB000; electric
blue #9FD8FF only on small sparks; the dark-gold afterimage #4A3200 only on the trail bolt).

Outputs (Game/assets/vfx/textures/):
    star_flash.png  512x512  8-point star: 4 long rays + 4 short diagonal rays, hot core, soft glow
                             (release flash 5 studs, impact flash 8 studs)
    spark.png       256x256  hot round spark with a faint cross; stretched by ParticleEmitter Squash
    glow_line.png   512x128  soft line: constant along U (tiles), bright centre fading to 0 across V;
                             for the lightning Beams and the spear's inner glow Beam, and the UV fade of
                             ribbon_helix (V along the ribbon) and shock_ring (V across the band)
    streak.png      512x512  wind streaks for the spear Trail: thin lines along U, bright at U = 0
                             (the head) fading toward U = 1 (the tail), soft edges across V
    scorch.png      512x512  scorch mark, coloured dark grey: darkest at the centre, crack lines,
                             a ragged soft edge (Decal on the floor at the hit)
    crater.png      512x512  stage 7B sky strike: crater 10 studs across, coloured dark grey: a dark
                             centre, 10 jagged radial cracks, a ragged soft edge
    crater_glow.png 512x512  the same cracks only, white (tinted #FFB000 in Roblox, glowing, fading)
Every texture keeps a transparent margin (Vault: 16 px at 512, 8 px at 256).
"""
import bpy, os
import numpy as np

TEX_DIR = r"C:\Roblox\Spin for ability\Game\assets\vfx\textures"
SCENE = "ThunderLance_Textures"
SAMPLES = 32


# --- a tiny expression builder over shader Math nodes ----------------------------------------------
class Expr:
    def __init__(self, nt):
        self.nt = nt
        self.x = self.y = None

    def _math(self, op, a, b=None, clamp=False):
        n = self.nt.nodes.new("ShaderNodeMath")
        n.operation = op
        n.use_clamp = clamp
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = float(v)
            else:
                self.nt.links.new(v, n.inputs[i])
        return n.outputs[0]

    def add(self, a, b): return self._math("ADD", a, b)
    def sub(self, a, b): return self._math("SUBTRACT", a, b)
    def mul(self, a, b): return self._math("MULTIPLY", a, b)
    def div(self, a, b): return self._math("DIVIDE", a, b)
    def pow(self, a, b): return self._math("POWER", a, b)
    def abs(self, a): return self._math("ABSOLUTE", a)
    def sqrt(self, a): return self._math("SQRT", a)
    def cos(self, a): return self._math("COSINE", a)
    def sin(self, a): return self._math("SINE", a)
    def atan2(self, a, b): return self._math("ARCTAN2", a, b)
    def exp(self, a): return self._math("EXPONENT", a)
    def clamp(self, a): return self._math("ADD", a, 0.0, clamp=True)

    def gauss(self, v, width):
        """exp(-(v / width)^2)"""
        q = self.div(v, width)
        return self.exp(self.mul(self.mul(q, q), -1.0))

    def ramp_down(self, v, start, end):
        """1 at v <= start, 0 at v >= end, smooth in between (smoothstep)."""
        n = self.nt.nodes.new("ShaderNodeMapRange")
        n.interpolation_type = "SMOOTHSTEP"
        n.clamp = True
        self.nt.links.new(v, n.inputs["Value"])
        n.inputs["From Min"].default_value, n.inputs["From Max"].default_value = start, end
        n.inputs["To Min"].default_value, n.inputs["To Max"].default_value = 1.0, 0.0
        return n.outputs["Result"]

    def ramp_up(self, v, start, end):
        return self.sub(1.0, self.ramp_down(v, start, end))

    def noise(self, sx, sy, scale, detail, offset=0.0):
        vec = self.nt.nodes.new("ShaderNodeCombineXYZ")
        self.nt.links.new(self.mul(self.x, sx), vec.inputs[0])
        self.nt.links.new(self.mul(self.y, sy), vec.inputs[1])
        vec.inputs[2].default_value = offset
        n = self.nt.nodes.new("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        self.nt.links.new(vec.outputs[0], n.inputs["Vector"])
        return n.outputs["Fac"]

    def voronoi_edge(self, scale, offset=0.0):
        vec = self.nt.nodes.new("ShaderNodeCombineXYZ")
        self.nt.links.new(self.x, vec.inputs[0])
        self.nt.links.new(self.y, vec.inputs[1])
        vec.inputs[2].default_value = offset
        n = self.nt.nodes.new("ShaderNodeTexVoronoi")
        n.feature = "DISTANCE_TO_EDGE"
        n.inputs["Scale"].default_value = scale
        self.nt.links.new(vec.outputs[0], n.inputs["Vector"])
        return n.outputs["Distance"]


def material(name, build):
    """Plane material: x, y in -1..1 from the plane's UV; build(e) returns (grey, alpha) sockets."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    e = Expr(nt)
    uv = nt.nodes.new("ShaderNodeUVMap")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(uv.outputs["UV"], sep.inputs[0])
    e.x = e.sub(e.mul(sep.outputs["X"], 2.0), 1.0)
    e.y = e.sub(e.mul(sep.outputs["Y"], 2.0), 1.0)
    grey, alpha = build(e)
    emit = nt.nodes.new("ShaderNodeEmission")
    if isinstance(grey, (int, float)):
        emit.inputs["Color"].default_value = (grey, grey, grey, 1)
    else:
        rgb = nt.nodes.new("ShaderNodeCombineColor")
        for i in range(3):
            nt.links.new(grey, rgb.inputs[i])
        nt.links.new(rgb.outputs[0], emit.inputs["Color"])
    transparent = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(e.clamp(alpha), mix.inputs["Fac"])
    nt.links.new(transparent.outputs[0], mix.inputs[1])
    nt.links.new(emit.outputs[0], mix.inputs[2])
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    return mat


# --- the five textures --------------------------------------------------------------------------
def polar(e):
    r = e.sqrt(e.add(e.mul(e.x, e.x), e.mul(e.y, e.y)))
    return r, e.atan2(e.y, e.x)


def star_flash(e):
    r, th = polar(e)
    # rays narrow toward their tips: the cosine power grows with the distance from the centre
    long_ray = e.pow(e.abs(e.cos(e.mul(th, 2.0))), e.add(14.0, e.mul(r, 140.0)))
    short_ray = e.pow(e.abs(e.sin(e.mul(th, 2.0))), e.add(20.0, e.mul(r, 200.0)))
    long_ray = e.mul(long_ray, e.ramp_down(r, 0.0, 0.92))
    short_ray = e.mul(e.mul(short_ray, e.ramp_down(r, 0.0, 0.55)), 0.75)
    core = e.gauss(r, 0.07)
    glow = e.mul(e.gauss(r, 0.30), 0.45)
    return 1.0, e.add(e.add(core, glow), e.add(long_ray, short_ray))


def spark(e):
    r, th = polar(e)
    cross = e.mul(e.mul(e.pow(e.abs(e.cos(e.mul(th, 2.0))), 40.0), e.ramp_down(r, 0.0, 0.8)), 0.35)
    return 1.0, e.add(e.add(e.gauss(r, 0.2), e.mul(e.gauss(r, 0.45), 0.4)), cross)


def glow_line(e):
    ay = e.abs(e.y)
    body = e.mul(e.ramp_down(ay, 0.3, 0.86), 0.6)
    core = e.mul(e.gauss(e.y, 0.22), 0.4)
    return 1.0, e.mul(e.add(body, core), e.ramp_down(ay, 0.62, 0.86))  # 0 by 8 px from the edge (128 px tall)


def streak(e):
    lines = e.ramp_up(e.noise(0.6, 9.0, 1.0, 1.0), 0.5, 0.66)
    lengths = e.ramp_up(e.noise(1.4, 9.0, 1.0, 0.0, offset=5.0), 0.38, 0.6)
    head_to_tail = e.mul(e.ramp_down(e.x, -0.9, 0.86), e.ramp_up(e.x, -0.93, -0.8))
    across = e.ramp_down(e.abs(e.y), 0.55, 0.92)
    core = e.mul(e.gauss(e.y, 0.12), 0.45)
    return 1.0, e.mul(e.mul(e.add(e.mul(lines, lengths), core), head_to_tail), across)


def scorch(e):
    r, _ = polar(e)
    wobble = e.mul(e.sub(e.noise(1.0, 1.0, 2.2, 3.0, offset=2.0), 0.5), 0.3)
    rr = e.add(r, wobble)
    base = e.ramp_down(rr, 0.35, 0.9)
    crack = e.mul(e.ramp_down(e.voronoi_edge(3.2, offset=1.3), 0.0, 0.045), e.ramp_down(rr, 0.15, 0.75))
    alpha = e.add(e.mul(base, 0.85), e.mul(crack, 0.25))
    # linear grey: 0.012 at the centre (sRGB ~0.10) -> 0.045 at the edge (sRGB ~0.23), cracks darker
    grey = e.sub(e.add(0.012, e.mul(e.ramp_up(r, 0.05, 0.85), 0.033)), e.mul(crack, 0.01))
    return grey, alpha


def crater_cracks(e):
    """10 jagged cracks running out from the centre (shared, so crater_glow lies exactly on crater)."""
    r, th = polar(e)
    wobble = e.mul(e.sub(e.noise(1.0, 1.0, 3.0, 4.0, offset=7.0), 0.5), 1.6)
    rays = e.pow(e.abs(e.cos(e.add(e.mul(th, 5.0), wobble))), 70.0)
    rays = e.mul(e.mul(rays, e.ramp_up(r, 0.06, 0.16)), e.ramp_down(r, 0.5, 0.9))
    # short side cracks between the rays, nearer the rim
    web = e.mul(e.ramp_down(e.voronoi_edge(5.0, offset=3.1), 0.0, 0.03), e.mul(e.ramp_up(r, 0.3, 0.45), e.ramp_down(r, 0.6, 0.8)))
    return e.clamp(e.add(rays, e.mul(web, 0.7))), r


def crater(e):
    cracks, r = crater_cracks(e)
    wobble = e.mul(e.sub(e.noise(1.0, 1.0, 2.6, 3.0, offset=11.0), 0.5), 0.25)
    rr = e.add(r, wobble)
    base = e.ramp_down(rr, 0.3, 0.92)
    alpha = e.add(e.mul(base, 0.9), e.mul(cracks, 0.3))
    # linear grey: 0.006 at the centre (sRGB ~0.07) -> 0.04 at the edge (sRGB ~0.21), cracks darker
    grey = e.sub(e.add(0.006, e.mul(e.ramp_up(r, 0.05, 0.8), 0.034)), e.mul(cracks, 0.006))
    return grey, alpha


def crater_glow(e):
    cracks, r = crater_cracks(e)
    # the lines plus a soft halo round them, hottest near the centre
    halo = e.mul(e.mul(e.gauss(r, 0.18), 0.35), e.ramp_up(r, 0.04, 0.1))
    return 1.0, e.add(e.mul(cracks, e.add(0.55, e.mul(e.ramp_down(r, 0.1, 0.8), 0.45))), halo)


TEXTURES = [("star_flash", 512, 512, star_flash, True), ("spark", 256, 256, spark, True),
            ("glow_line", 512, 128, glow_line, True), ("streak", 512, 512, streak, True),
            ("scorch", 512, 512, scorch, False), ("crater", 512, 512, crater, False),
            ("crater_glow", 512, 512, crater_glow, True)]


# --- render + post ------------------------------------------------------------------------------
def make_scene():
    old = bpy.data.scenes.get(SCENE)
    if old:
        bpy.data.scenes.remove(old)
    sc = bpy.data.scenes.new(SCENE)
    try:
        sc.render.engine = "CYCLES"
    except TypeError as e:
        print("engine:", e)
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = False
    sc.cycles.pixel_filter_type = "BLACKMAN_HARRIS"
    sc.cycles.filter_width = 1.0
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.view_settings.exposure, sc.view_settings.gamma = 0.0, 1.0
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.resolution_percentage = 100
    me = bpy.data.meshes.new("_tl_tex_plane")
    me.from_pydata([(-1, -1, 0), (1, -1, 0), (1, 1, 0), (-1, 1, 0)], [], [(0, 1, 2, 3)])
    uvl = me.uv_layers.new(name="UVMap")
    for loop, uv in zip(me.loops, [(0, 0), (1, 0), (1, 1), (0, 1)]):
        uvl.data[loop.index].uv = uv
    plane = bpy.data.objects.new("_tl_tex_plane", me)
    sc.collection.objects.link(plane)
    cam_data = bpy.data.cameras.new("_tl_tex_cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("_tl_tex_cam", cam_data)
    cam.location = (0, 0, 5)
    sc.collection.objects.link(cam)
    sc.camera = cam
    return sc, plane, cam_data


def render(sc, plane, cam_data, name, w, h, build):
    """The plane is stretched to the image's aspect and fills the camera exactly."""
    sc.render.resolution_x, sc.render.resolution_y = w, h
    plane.scale = (1, h / w, 1)
    cam_data.ortho_scale = 2.0  # the wider side (here always X) spans the plane's 2 units
    mat = material("_tl_tex_" + name, build)
    plane.data.materials.clear()
    plane.data.materials.append(mat)
    path = os.path.join(TEX_DIR, name + ".png")
    sc.render.filepath = path
    with bpy.context.temp_override(scene=sc):
        bpy.ops.render.render(write_still=True, scene=sc.name)
    bpy.data.materials.remove(mat)
    return path


def load_png(path):
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return np.flipud(px.reshape(h, w, 4))


def save_png(path, rgba):
    h, w, _ = rgba.shape
    img = bpy.data.images.new(os.path.basename(path), width=w, height=h, alpha=True)
    img.pixels.foreach_set(np.flipud(np.clip(rgba, 0, 1)).astype(np.float32).ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def bleed(rgba, passes=24):
    """Fill the RGB of (nearly) transparent pixels with the alpha-weighted average of their visible
    neighbours, growing outward; alpha is untouched (as build_frost_jab_textures.py)."""
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
    rgb[~known] = rgb[known].mean(axis=0) if np.any(known) else 1.0
    return np.dstack([rgb, a])


def report(name, im, margin, tiles_u=False):
    """Size, coverage, the alpha inside the margin band (must be ~0), and the halo check: the grey of
    semi-transparent edge pixels vs the grey inside. A dark or bright edge band = halo."""
    a = im[..., 3]
    g = im[..., :3].mean(axis=2)
    band = max(a[:margin].max(), a[-margin:].max())  # top and bottom rows (across V)
    if not tiles_u:  # a texture that tiles along U runs edge to edge there on purpose
        band = max(band, a[:, :margin].max(), a[:, -margin:].max())
    ring_px = (a > 0.02) & (a < 0.35)
    inner = a > 0.8 if np.any(a > 0.8) else a > 0.5
    zero = a <= 0.02

    def span(mask):
        return f"{g[mask].min():.2f}..{g[mask].max():.2f}" if np.any(mask) else "none"

    print(f"{name}.png  {im.shape[1]}x{im.shape[0]}  alpha max {a.max():.2f}  covered {np.mean(a > 0.05) * 100:.0f}%"
          f"  margin({margin}px) alpha {band:.3f}  edge grey {span(ring_px)}  inside grey {span(inner)}"
          f"  transparent-pixel RGB {span(zero)}")
    return band


def build():
    os.makedirs(TEX_DIR, exist_ok=True)
    sc, plane, cam_data = make_scene()
    try:
        only = globals().get("ONLY")
        for name, w, h, fn, white in TEXTURES:
            if only and name not in only:
                continue
            path = render(sc, plane, cam_data, name, w, h, fn)
            im = load_png(path)
            if white:
                im[..., :3] = 1.0  # white art: brightness is the alpha; colour comes from Roblox
            im = bleed(im)
            save_png(path, im)
            report(name, im, 16 if min(w, h) >= 512 else 8, tiles_u=name == "glow_line")
    finally:
        objs = [o for o in sc.collection.objects]
        datas = [o.data for o in objs]
        for o in objs:
            bpy.data.objects.remove(o, do_unlink=True)
        for d in datas:
            for coll in (bpy.data.meshes, bpy.data.cameras):
                if d in list(coll) and d.users == 0:
                    coll.remove(d)
        bpy.data.scenes.remove(sc)
    bpy.ops.wm.save_mainfile()


build()

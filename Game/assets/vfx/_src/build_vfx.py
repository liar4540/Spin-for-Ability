"""Spin for Abilities - shared VFX mesh kit (Blender 5.2, headless).

Run from anywhere:
    blender -b --factory-startup --python build_vfx.py -- [--only name1,name2] [--no-preview]

Outputs (next to this folder):
    ../meshes/<name>.glb          one mesh per file, 1 Blender unit = 1 stud
    ../meshes/_gate_report.json   LIHFOLK quality gate result per mesh
    ../previews/kit_sheet.png     every mesh side by side (shape check)
    ../previews/blood_moon_slash.png   Blood Moon Slash layer test at game distance

Conventions (vault: 11 Abilities):
    * Blender +Y = the character's forward (Roblox LookVector) after .glb import; Blender +Z = up.
    * Ribbons (crescents, rings, bolts, swirls, pillar) are open surfaces with
      U along the length / around, V across. Textures stay white; colour comes from Studio.
    * Build script is the source of truth: change a number here and rerun.
"""
import bpy, bmesh, math, os, sys, json, random, zlib
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MESH_DIR = os.path.join(ROOT, "meshes")
PREVIEW_DIR = os.path.join(ROOT, "previews")
LIHFOLK = os.path.join(os.path.expanduser("~"), ".claude", "plugins", "cache", "lihfolk", "lihfolk",
                       "2.5.0", "skills", "roblox-blender-modeling", "scripts")
sys.path.append(LIHFOLK)
import lihfolk_bpy as lf  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = None
if "--only" in argv:
    ONLY = set(argv[argv.index("--only") + 1].split(","))
PREVIEW = "--no-preview" not in argv


def rng_for(name):
    """Seed per asset, so adding a mesh never changes the others."""
    return random.Random(zlib.crc32(name.encode()))


# ------------------------------------------------------------------ helpers

def new_object(name, bm, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def ribbon(bm, rows, closed_u=False):
    """rows: list of (u, [(pos, v), ...]) columns along U, each with the same number of points across V.
    Builds quads with per-loop UVs. closed_u joins the last column back to the first (rings)."""
    uv = bm.loops.layers.uv.verify()
    cols = []
    for u, pts in rows:
        cols.append([(bm.verts.new(p), u, v) for p, v in pts])
    n = len(cols)
    last = n if closed_u else n - 1
    for i in range(last):
        a = cols[i]
        b = cols[(i + 1) % n]
        ub = b[0][1] if not (closed_u and i == n - 1) else 1.0
        for j in range(len(a) - 1):
            quad = [(a[j][0], a[j][1], a[j][2]), (b[j][0], ub, b[j][2]),
                    (b[j + 1][0], ub, b[j + 1][2]), (a[j + 1][0], a[j][1], a[j + 1][2])]
            f = bm.faces.new([q[0] for q in quad])
            for loop, q in zip(f.loops, quad):
                loop[uv].uv = (q[1], q[2])
    return bm


# ------------------------------------------------------------------ the kit

def crescent(name, radius=7.0, width=2.2, span_deg=200.0, segs=72, across=4):
    """Slash arc in the XY plane, centred on +Y (forward). U: 0 = tail, 1 = head. V: 0 = inner, 1 = outer.
    Width profile from the LIHFOLK crescent recipe: sin(pi * u^1.36)^0.7, peaking just past the middle."""
    bm = bmesh.new()
    span = math.radians(span_deg)
    rows = []
    for i in range(segs + 1):
        u = i / segs
        theta = -span / 2 + span * u            # tail on the left, head on the right
        w = width * max(0.03, math.sin(math.pi * (u ** 1.36)) ** 0.7)
        pts = []
        for j in range(across + 1):
            v = j / across
            r = radius - w * (1 - v)
            pts.append((Vector((r * math.sin(theta), r * math.cos(theta), 0.0)), v))
        rows.append((u, pts))
    ribbon(bm, rows)
    return new_object(name, bm), "card"


def shock_ring(name, inner=0.75, outer=1.0, segs=64):
    """Flat ring in the XY plane, radius 1 (scale it in Studio). U around, V: 0 inner -> 1 outer."""
    bm = bmesh.new()
    rows = []
    for i in range(segs):
        u = i / segs
        a = 2 * math.pi * u
        c, s = math.cos(a), math.sin(a)
        rows.append((u, [(Vector((inner * c, inner * s, 0)), 0.0),
                         (Vector(((inner + outer) / 2 * c, (inner + outer) / 2 * s, 0)), 0.5),
                         (Vector((outer * c, outer * s, 0)), 1.0)]))
    ribbon(bm, rows, closed_u=True)
    return new_object(name, bm), "card"


def sphere_shell(name):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=1.0, calc_uvs=True)
    return new_object(name, bm), "closed"


def bolt(name, length=6.0, width=0.45, segs=24, rough=0.35):
    """Lightning spear along +Y as two crossed ribbons (reads from any side). Jagged by seeded midpoint
    displacement. U: 0 = back -> 1 = tip, V across. Pointed tip, thinner tail."""
    rnd = rng_for(name)
    pts = [Vector((0, 0, 0)), Vector((0, length, 0))]
    for _ in range(4):                          # midpoint displacement, 16 segments
        out = [pts[0]]
        for a, b in zip(pts, pts[1:]):
            m = (a + b) / 2
            amp = rough * (b - a).length
            m += Vector((rnd.uniform(-amp, amp), 0, rnd.uniform(-amp, amp)))
            out += [m, b]
        pts = out
    pts[0] = Vector((0, 0, 0)); pts[-1] = Vector((0, length, 0))
    bm = bmesh.new()
    n = len(pts) - 1
    for side in (Vector((1, 0, 0)), Vector((0, 0, 1))):
        rows = []
        for i, p in enumerate(pts):
            u = i / n
            w = width * (0.35 + 0.65 * math.sin(math.pi * min(1, u * 1.15)) ** 0.5) * (1 - u ** 6)
            w = max(w, 0.01)
            rows.append((u, [(p - side * w / 2, 0.0), (p, 0.5), (p + side * w / 2, 1.0)]))
        ribbon(bm, rows)
    return new_object(name, bm), "card"


def shard(name, length=1.0, radius=0.16, sides=6):
    """Crystal shard pointing +Z: hexagonal bipyramid, long top, short bottom. Flat shaded."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.verify()
    top = bm.verts.new((0, 0, length))
    bot = bm.verts.new((0, 0, -0.18 * length))
    ring = [bm.verts.new((radius * math.cos(2 * math.pi * i / sides), radius * math.sin(2 * math.pi * i / sides), 0))
            for i in range(sides)]
    for i in range(sides):
        a, b = ring[i], ring[(i + 1) % sides]
        u0, u1 = i / sides, (i + 1) / sides
        for verts, uvs in (([a, b, top], [(u0, 0.4), (u1, 0.4), ((u0 + u1) / 2, 1.0)]),
                           ([b, a, bot], [(u1, 0.4), (u0, 0.4), ((u0 + u1) / 2, 0.0)])):
            f = bm.faces.new(verts)
            for loop, t in zip(f.loops, uvs):
                loop[uv].uv = t
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object(name, bm, smooth=False), "closed"


def pillar(name, r_bottom=1.0, r_top=0.8, height=1.0, segs=32):
    """Open tapered tube standing on the origin, height 1 (scale in Studio). U around, V up."""
    bm = bmesh.new()
    rows = []
    for i in range(segs):
        u = i / segs
        a = 2 * math.pi * u
        c, s = math.cos(a), math.sin(a)
        rows.append((u, [(Vector((r_bottom * c, r_bottom * s, 0)), 0.0),
                         (Vector(((r_bottom + r_top) / 2 * c, (r_bottom + r_top) / 2 * s, height / 2)), 0.5),
                         (Vector((r_top * c, r_top * s, height)), 1.0)]))
    ribbon(bm, rows, closed_u=True)
    return new_object(name, bm), "card"


def rock(name, radius=1.0, jitter=0.18):
    """Low-poly rock chunk, flat shaded, seeded jitter."""
    rnd = rng_for(name)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=radius, calc_uvs=True)
    for v in bm.verts:
        v.co *= 1 + rnd.uniform(-jitter, jitter)
    for v in bm.verts:                          # a little flatter, like a chunk
        v.co.z *= 0.75
    return new_object(name, bm, smooth=False), "closed"


def slab(name, w=4.0, d=1.0, h=6.0):
    """Stone Wall slab: chunky box, uneven top, origin at the bottom centre."""
    rnd = rng_for(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0, calc_uvs=True)
    for v in bm.verts:
        v.co.x *= w; v.co.y *= d; v.co.z = (v.co.z + 0.5) * h
        if v.co.z > h - 1e-6:
            v.co.z += rnd.uniform(-0.6, 0.4)
    return new_object(name, bm, smooth=False), "closed"


def swirl(name, turns=1.5, r0=1.0, r1=0.35, rise=0.6, width=0.28, segs=96):
    """Spiral ribbon around +Z, shrinking inward (pull-in / wind swirl). U along, V across (vertical)."""
    bm = bmesh.new()
    rows = []
    for i in range(segs + 1):
        u = i / segs
        a = 2 * math.pi * turns * u
        r = r0 + (r1 - r0) * u
        z = rise * u
        w = width * math.sin(math.pi * u) ** 0.6
        w = max(w, 0.005)
        p = Vector((r * math.cos(a), r * math.sin(a), z))
        rows.append((u, [(p - Vector((0, 0, w / 2)), 0.0), (p + Vector((0, 0, w / 2)), 1.0)]))
    ribbon(bm, rows)
    return new_object(name, bm), "card"


KIT = {
    "crescent_thick": lambda n: crescent(n, radius=7.0, width=2.2, span_deg=200),
    "crescent_thin": lambda n: crescent(n, radius=7.0, width=0.9, span_deg=160),
    "shock_ring": lambda n: shock_ring(n),
    "sphere_shell": lambda n: sphere_shell(n),
    "bolt": lambda n: bolt(n),
    "shard": lambda n: shard(n),
    "pillar": lambda n: pillar(n),
    "rock": lambda n: rock(n),
    "slab": lambda n: slab(n),
    "swirl": lambda n: swirl(n),
}


# ------------------------------------------------------------------ materials (preview only)

def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_lin(h):
    h = h.lstrip("#")
    return tuple(srgb_to_linear(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4)) + (1.0,)


def emission_mat(name, hex_color, strength=4.0, alpha_from_u=None, alpha_scale=1.0):
    """Emissive, alpha-blended. alpha_from_u = exponent k: alpha = u^k (bright head, fading tail)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    col = hex_lin(hex_color)
    for key, val in (("Base Color", (0, 0, 0, 1)), ("Emission Color", col), ("Emission Strength", strength)):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = val
    if alpha_from_u is not None:
        tc = nt.nodes.new("ShaderNodeTexCoord")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        pw = nt.nodes.new("ShaderNodeMath"); pw.operation = "POWER"; pw.inputs[1].default_value = alpha_from_u
        edge = nt.nodes.new("ShaderNodeMath"); edge.operation = "PINGPONG"; edge.inputs[1].default_value = 0.5
        edge2 = nt.nodes.new("ShaderNodeMath"); edge2.operation = "MULTIPLY"; edge2.inputs[1].default_value = 2.0
        mul = nt.nodes.new("ShaderNodeMath"); mul.operation = "MULTIPLY"
        sc = nt.nodes.new("ShaderNodeMath"); sc.operation = "MULTIPLY"; sc.inputs[1].default_value = alpha_scale
        nt.links.new(tc.outputs["UV"], sep.inputs[0])
        nt.links.new(sep.outputs["X"], pw.inputs[0])
        nt.links.new(sep.outputs["Y"], edge.inputs[0])      # V: soft edges across the ribbon
        nt.links.new(edge.outputs[0], edge2.inputs[0])
        nt.links.new(pw.outputs[0], mul.inputs[0])
        nt.links.new(edge2.outputs[0], mul.inputs[1])
        nt.links.new(mul.outputs[0], sc.inputs[0])
        nt.links.new(sc.outputs[0], bsdf.inputs["Alpha"])
    try:
        m.surface_render_method = "BLENDED"
    except Exception:
        pass
    return m


# ------------------------------------------------------------------ preview scenes

def stage(engine):
    sc = bpy.context.scene
    sc.render.engine = engine
    sc.view_settings.view_transform = "Standard"          # LIHFOLK: no AgX / Filmic for Roblox previews
    sc.render.resolution_x, sc.render.resolution_y = 1600, 900
    w = bpy.data.worlds.new("World") if not sc.world else sc.world
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = hex_lin("#14161C")
    bg.inputs[1].default_value = 1.0
    return sc


def camera(location, target, lens=35, ortho=None):
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    bpy.context.scene.collection.objects.link(cam)
    cam.location = location
    d = Vector(target) - Vector(location)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    if ortho:
        cam.data.type = "ORTHO"; cam.data.ortho_scale = ortho
    else:
        cam.data.lens = lens
    bpy.context.scene.camera = cam
    return cam


def render(path):
    sc = bpy.context.scene
    sc.render.filepath = path
    sc.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)
    print("rendered", path)


def try_bloom(sc):
    """Blender 5 compositor: node group + Glare (Bloom). Best effort (LIHFOLK: Blender 5 Python Gotchas)."""
    try:
        ng = bpy.data.node_groups.new("Comp", "CompositorNodeTree")
        ng.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
        rl = ng.nodes.new("CompositorNodeRLayers")
        gl = ng.nodes.new("CompositorNodeGlare")
        out = ng.nodes.new("NodeGroupOutput")
        for key, val in (("Type", "Bloom"), ("Threshold", 1.2), ("Strength", 0.6), ("Size", 0.5)):
            try:
                gl.inputs[key].default_value = val
            except Exception:
                pass
        ng.links.new(rl.outputs["Image"], gl.inputs["Image"])
        ng.links.new(gl.outputs["Image"], out.inputs[0])
        sc.compositing_node_group = ng
    except Exception as e:  # preview still works without bloom
        print("bloom skipped:", e)


def kit_sheet(objs):
    sc = stage("BLENDER_WORKBENCH")
    sh = sc.display.shading
    sh.light = "STUDIO"; sh.color_type = "OBJECT"
    sh.show_backface_culling = False
    sc.display.shading.background_type = "WORLD"
    palette = ["#FF6A3D", "#FFD23F", "#3DE0FF", "#A64DFF", "#FFF1C4", "#7BD65A", "#FF4FD8", "#B0B4BE", "#8A6B4E", "#3D8BFF"]
    placed = []
    x = 0.0
    for i, ob in enumerate(objs):
        d = max(ob.dimensions)
        s = 3.0 / d if d > 0 else 1.0                # every mesh shown about 3 studs big
        dup = ob.copy(); dup.data = ob.data; sc.collection.objects.link(dup)
        dup.scale = (s, s, s)
        col, row = i % 5, i // 5
        dup.location = (col * 4.5, -row * 4.5, 0)
        dup.rotation_euler = (math.radians(-35), 0, math.radians(25))
        dup.color = hex_lin(palette[i % len(palette)])
        placed.append(dup)
        ob.hide_render = True
    camera((9.0, -2.25, 30.0), (9.0, -2.25, 0.0), ortho=24)
    render(os.path.join(PREVIEW_DIR, "kit_sheet.png"))
    for d in placed:
        bpy.data.objects.remove(d)
    for ob in objs:
        ob.hide_render = False


def blood_moon_preview(kit):
    """Layer test for Blood Moon Slash (LIHFOLK crescent recipe: white edge, element body, dark smear)."""
    for ob in kit.values():
        ob.hide_render = True
    sc = stage("BLENDER_EEVEE")
    try_bloom(sc)
    # floor + a simple 5-stud character stand-in at the origin, facing +Y
    bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=60)
    floor = new_object("Floor", bm)
    fm = bpy.data.materials.new("FloorMat"); fm.use_nodes = True
    fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = hex_lin("#2A2D36")
    floor.data.materials.append(fm)
    bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=0.9, radius2=0.9, depth=5.0)
    dummy = new_object("Character", bm)
    dummy.location = (0, 0, 2.5)
    dm = bpy.data.materials.new("DummyMat"); dm.use_nodes = True
    dm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = hex_lin("#9AA0AA")
    dummy.data.materials.append(dm)
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 2.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    sc.collection.objects.link(sun)

    chest = 3.2
    # Diagonal swing: pitch the arc plane up in front (+X rotation turns the plane's normal toward the
    # camera behind the character), then roll it about the forward axis for a top-right to bottom-left cut.
    # Without this the flat arc is seen edge-on from the game camera and reads as a thin line.
    swing = Matrix.Rotation(math.radians(-20), 4, "Y") @ Matrix.Rotation(math.radians(40), 4, "X")
    layers = [
        # (mesh, material, scale, offset along the swing normal, yaw lag in degrees)
        # Dark smear: deep crimson (not near-black: it vanished on the dark floor), over the inner half, lagging.
        ("crescent_thick", emission_mat("Smear", "#5A0812", 1.2, alpha_from_u=0.5, alpha_scale=0.85), 0.93, 0.04, -18),
        ("crescent_thick", emission_mat("Body", "#E0182D", 5.0, alpha_from_u=1.4, alpha_scale=0.95), 1.0, 0.0, 0),
        ("crescent_thin", emission_mat("Edge", "#FFFFFF", 10.0, alpha_from_u=3.0, alpha_scale=1.0), 1.03, 0.06, 3),
    ]
    normal = (swing @ Vector((0, 0, 1, 0))).to_3d()
    for name, mat, s, off, lag in layers:
        src = kit[name]
        dup = src.copy(); dup.data = src.data.copy(); sc.collection.objects.link(dup)
        dup.data.materials.clear(); dup.data.materials.append(mat)
        m = Matrix.Translation(Vector((0, 0, chest)) + normal * off) @ swing @ Matrix.Rotation(math.radians(lag), 4, "Z")
        dup.matrix_world = m @ Matrix.Diagonal((s, s, s, 1))
        dup.visible_shadow = False
        dup.hide_render = False
    # faint ground ring (LIHFOLK: transparency 0.65-0.8)
    ring = kit["shock_ring"].copy(); ring.data = kit["shock_ring"].data.copy(); sc.collection.objects.link(ring)
    ring.data.materials.clear(); ring.data.materials.append(emission_mat("Ground", "#E0182D", 0.8, alpha_from_u=0.0, alpha_scale=0.18))
    ring.scale = (5, 5, 5); ring.location = (0, 3.0, 0.05); ring.visible_shadow = False; ring.hide_render = False
    # small sparks thrown forward from the head of the arc, along the swing
    rnd = rng_for("blood_moon_sparks")
    head = swing @ Vector((7.0 * math.sin(math.radians(100)), 7.0 * math.cos(math.radians(100)), 0, 1))
    head = head.to_3d() + Vector((0, 0, chest))
    for i in range(12):
        sp = kit["shard"].copy(); sp.data = kit["shard"].data; sc.collection.objects.link(sp)
        if i == 0:
            sp.data.materials.clear(); sp.data.materials.append(emission_mat("Spark", "#FF6060", 8.0))
        sp.location = head + Vector((rnd.uniform(-0.5, 2.2), rnd.uniform(-0.5, 2.0), rnd.uniform(-1.5, 0.8)))
        sp.rotation_euler = (math.radians(rnd.uniform(0, 360)), math.radians(90), rnd.uniform(0, 6.28))
        sp.scale = (0.3, 0.3, rnd.uniform(0.35, 0.7))
        sp.visible_shadow = False; sp.hide_render = False
    # game camera: third person, behind and above the character (Roblox default is ~12-15 studs)
    camera((0.0, -14.0, 10.0), (0.0, 3.0, 2.5), lens=30)
    render(os.path.join(PREVIEW_DIR, "blood_moon_slash.png"))


# ------------------------------------------------------------------ main

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    lf.setup_scene()
    os.makedirs(MESH_DIR, exist_ok=True)
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    white = bpy.data.materials.new("VFX_White")
    report = {}
    kit = {}
    for name, build in KIT.items():
        if ONLY and name not in ONLY:
            continue
        ob, kind = build(name)
        ob.data.materials.append(white)
        lf.apply_transforms(ob)
        passed, fails, r = lf.gate(ob, cls="small", foliage_card=(kind == "card"))
        report[name] = {"kind": kind, "passed": passed, "fails": fails, "tris": r["tris"],
                        "dimensions": r["dimensions"], "uv_out_of_0_1": r.get("uv_out_of_0_1")}
        print(f"[gate] {name:15s} {'PASS' if passed else 'FAIL'} tris={r['tris']} dims={r['dimensions']} {fails}")
        lf.export_glb(ob, os.path.join(MESH_DIR, name + ".glb"))
        kit[name] = ob
    with open(os.path.join(MESH_DIR, "_gate_report.json"), "w") as f:
        json.dump(report, f, indent=2)
    if PREVIEW and not ONLY:
        kit_sheet(list(kit.values()))
        blood_moon_preview(kit)
    bad = [n for n, r in report.items() if not r["passed"]]
    print("SUMMARY", len(report), "meshes,", len(bad), "failed", bad)


main()

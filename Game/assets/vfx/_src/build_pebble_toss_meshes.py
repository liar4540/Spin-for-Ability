"""Spin for Abilities - Pebble Toss, stage 3: rock + 5 chip meshes (Blender 5.2).

Run inside Blender (MCP or Text Editor), after the rig/throw scripts (it leaves them alone):
    exec(open(r"<this file>").read())

Visual source of truth: images/abilities/pebble toss.png ("Rock Model (Small, spinning)",
"Rock Chips (On Hit)"): clean low-poly, flat-shaded, grey.
1 Blender unit = 1 stud. Everything lives in the collection "PebbleToss_Meshes".

    Rock   faceted boulder, 12-20 faces, about 0.8 studs across, #8A8A90, origin at its centre
    Chip1-5 sharp angular shards, 0.15-0.30 studs long, same grey
    total under 200 triangles, all transforms applied, flat shading

Outputs:
    Game/assets/pebble_rock.fbx, Game/assets/pebble_chip_1..5.fbx   one FBX per mesh
        (import in Studio's 3D Importer with File Dimensions = Studs: 1 unit = 1 stud)
    Game/assets/vfx/meshes/pebble_meshes.json   vertices + triangles of every mesh (Roblox axes)
    Game/src/shared/Config/PebbleTossMeshes.luau the same data for VFXTemplateService, which carves
        the Rock/Chip templates in Studio with CSG (no mesh upload needed)
    saves Game/assets/pebble_toss.blend
"""
import bpy, bmesh, json, math, os, random
from mathutils import Vector, Matrix

ASSETS = r"C:\Roblox\Spin for ability\Game\assets"
JSON_OUT = os.path.join(ASSETS, "vfx", "meshes", "pebble_meshes.json")
COLL = "PebbleToss_Meshes"
GREY_HEX = "8A8A90"
ROCK_SIZE = 0.8
ROCK_MERGE_DEG = 16
ROCK_POINTS = 11
CHIP_LENGTHS = [0.16, 0.20, 0.24, 0.27, 0.30]
SEED = 7


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_linear(h):
    return tuple(srgb_to_linear(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4))


def grey_material():
    mat = bpy.data.materials.get("Pebble_Grey") or bpy.data.materials.new("Pebble_Grey")
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    rgb = hex_linear(GREY_HEX)
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Roughness"].default_value = 0.85
    mat.diffuse_color = (*[srgb_to_linear(0) + c for c in rgb], 1)
    return mat


def fresh_collection():
    coll = bpy.data.collections.get(COLL)
    if coll:
        for ob in list(coll.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
    else:
        coll = bpy.data.collections.new(COLL)
        bpy.context.scene.collection.children.link(coll)
    return coll


def hull_object(name, points, coll, dissolve_deg=0.0):
    """Convex hull of the points -> flat-shaded mesh object, origin at its bounding-box centre."""
    bm = bmesh.new()
    for p in points:
        bm.verts.new(p)
    bmesh.ops.convex_hull(bm, input=bm.verts[:])
    if dissolve_deg > 0:
        bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(dissolve_deg), verts=bm.verts[:], edges=bm.edges[:])
    lo = Vector((min(v.co.x for v in bm.verts), min(v.co.y for v in bm.verts), min(v.co.z for v in bm.verts)))
    hi = Vector((max(v.co.x for v in bm.verts), max(v.co.y for v in bm.verts), max(v.co.z for v in bm.verts)))
    centre = (lo + hi) / 2
    for v in bm.verts:
        v.co -= centre
    for f in bm.faces:
        f.smooth = False
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    return ob


def build_rock(coll, rng):
    # ROCK_POINTS points spread evenly over a sphere (Fibonacci), each nudged and pushed in/out,
    # squashed a little: the hull has big uneven facets like the reference rock
    pts = []
    golden = math.pi * (3 - math.sqrt(5))
    for k in range(ROCK_POINTS):
        z = 1 - 2 * (k + 0.5) / ROCK_POINTS
        rad = math.sqrt(1 - z * z)
        a = k * golden + rng.uniform(-0.35, 0.35)
        z += rng.uniform(-0.12, 0.12)
        r = 0.5 * (1 + rng.uniform(-0.15, 0.12))
        pts.append(Vector((math.cos(a) * rad * r, math.sin(a) * rad * r * 0.92, z * r * 0.85)))
    # merge neighbouring faces that are nearly flat to each other into bigger facets
    ob = hull_object("Rock", pts, coll, dissolve_deg=ROCK_MERGE_DEG)
    # scale so the widest side is ROCK_SIZE, then apply
    dims = ob.dimensions
    s = ROCK_SIZE / max(dims)
    ob.data.transform(Matrix.Scale(s, 4))
    ob.data.update()
    return ob


def build_chip(coll, rng, i, length):
    # a sharp shard: long tip, short back tip, 3-4 jittered points round the middle
    axis_pts = [Vector((0, 0, length * 0.62)), Vector((0, 0, -length * 0.38))]
    ring = []
    n = 3 + (i % 2)
    for k in range(n):
        a = 2 * math.pi * k / n + rng.uniform(-0.35, 0.35)
        r = length * rng.uniform(0.22, 0.36)
        ring.append(Vector((math.cos(a) * r, math.sin(a) * r * rng.uniform(0.5, 0.9), rng.uniform(-0.12, 0.12) * length)))
    ob = hull_object(f"Chip{i + 1}", axis_pts + ring, coll)
    # tilt each variant differently so they don't read as copies, bake it in
    ob.data.transform(Matrix.Rotation(rng.uniform(-0.6, 0.6), 4, "X") @ Matrix.Rotation(rng.uniform(0, math.pi), 4, "Z"))
    # re-centre after the tilt
    vs = [v.co for v in ob.data.vertices]
    c = (Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs))) +
         Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))) / 2
    ob.data.transform(Matrix.Translation(-c))
    ob.data.update()
    # longest side = the target length exactly
    ob.data.transform(Matrix.Scale(length / max(ob.dimensions), 4))
    ob.data.update()
    return ob


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def to_roblox(ob):
    """Vertices in Roblox axes (Blender (x, y, z) -> Roblox (x, z, -y)) + fan-triangulated faces."""
    verts = [[round(v.co.x, 5), round(v.co.z, 5), round(-v.co.y, 5)] for v in ob.data.vertices]
    tris = []
    for p in ob.data.polygons:
        vs = list(p.vertices)
        for k in range(1, len(vs) - 1):
            tris.append([vs[0], vs[k], vs[k + 1]])
    return {"verts": verts, "tris": tris, "size": [round(d, 4) for d in (ob.dimensions.x, ob.dimensions.z, ob.dimensions.y)]}


def export_fbx(ob, path):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    loc = ob.location.copy()
    ob.location = (0, 0, 0)                                  # export each mesh centred on its origin
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types={"MESH"},
                             apply_scale_options="FBX_SCALE_UNITS", axis_forward="-Z", axis_up="Y",
                             mesh_smooth_type="FACE", use_mesh_modifiers=True, bake_anim=False)
    ob.location = loc
    ob.select_set(False)


LUAU_OUT = r"C:\Roblox\Spin for ability\Game\src\shared\Config\PebbleTossMeshes.luau"


def write_luau(data):
    """Same data as the JSON, as the Luau module VFXTemplateService carves the templates from."""
    def num(x):
        s = f"{x:.5f}".rstrip("0").rstrip(".")
        return "0" if s in ("-0", "") else s
    blocks = []
    for name, m in data.items():
        verts = ", ".join("{" + ", ".join(num(c) for c in v) + "}" for v in m["verts"])
        tris = ", ".join("{" + ", ".join(str(i) for i in t) + "}" for t in m["tris"])
        blocks.append(f"\t{name} = {{\n\t\tVerts = {{ {verts} }},\n\t\tTris = {{ {tris} }},\n\t}},")
    src = (
        "--!strict\n"
        "-- GENERATED - do not edit by hand. Pebble Toss rock + 5 chips (Roblox axes, studs, centred).\n"
        "-- Source: Game/assets/vfx/meshes/pebble_meshes.json, made in Blender by\n"
        "-- Game/assets/vfx/_src/build_pebble_toss_meshes.py (also exports the FBX files in Game/assets).\n"
        "-- Tris index Verts from 0. VFXTemplateService carves these shapes out of blocks with CSG at\n"
        "-- server start (no mesh upload needed): each triangle's plane becomes one cut.\n\n"
        "export type MeshData = { Verts: { { number } }, Tris: { { number } } }\n\n"
        "local PebbleTossMeshes: { [string]: MeshData } = {\n" + "\n".join(blocks) + "\n}\n\n"
        "return PebbleTossMeshes\n"
    )
    with open(LUAU_OUT, "w", newline="\n") as fh:
        fh.write(src)


def build():
    rng = random.Random(SEED)
    coll = fresh_collection()
    mat = grey_material()
    rock = build_rock(coll, rng)
    chips = [build_chip(coll, rng, i, L) for i, L in enumerate(CHIP_LENGTHS)]
    meshes = [rock] + chips
    for ob in meshes:
        ob.data.materials.append(mat)

    # layout for the screenshot: well away from the rig (which stands at the origin)
    rock.location = (8.0, 0, ROCK_SIZE / 2)
    for i, ch in enumerate(chips):
        ch.location = (8.8 + i * 0.42, 0, ch.dimensions.z / 2)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(6.6, 0, 0.5))
    cube = bpy.context.active_object
    cube.name = "ScaleCube_1x1x1"
    for c in cube.users_collection:
        c.objects.unlink(cube)
    coll.objects.link(cube)

    data = {}
    for ob in meshes:
        export_fbx(ob, os.path.join(ASSETS, "pebble_rock.fbx" if ob is rock else f"pebble_chip_{ob.name[-1]}.fbx"))
        data[ob.name] = to_roblox(ob)
    os.makedirs(os.path.dirname(JSON_OUT), exist_ok=True)
    with open(JSON_OUT, "w") as fh:
        json.dump({"color": "#" + GREY_HEX, "meshes": data}, fh, separators=(",", ":"))
    write_luau(data)
    bpy.ops.wm.save_mainfile()
    return meshes


meshes = build()
total = 0
for ob in meshes:
    t = tri_count(ob)
    total += t
    d = ob.dimensions
    print(f"{ob.name:6s} faces={len(ob.data.polygons):2d} tris={t:2d} size=({d.x:.3f}, {d.y:.3f}, {d.z:.3f}) "
          f"scale={tuple(round(s, 3) for s in ob.scale)} rot={tuple(round(r, 3) for r in ob.rotation_euler)}")
print("total triangles", total)

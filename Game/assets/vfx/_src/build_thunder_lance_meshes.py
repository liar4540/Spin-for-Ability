"""Spin for Abilities - Thunder Lance, stage 5: VFX meshes (collection "ThunderLance_Meshes").

Run inside Blender with Game/assets/thunder_lance.blend open:
    exec(open(r"<this file>").read())
1 Blender unit = 1 stud. Every mesh is built at the origin with identity transforms (nothing to apply).
The spear points along +Y here, which is the Roblox part's LookVector (-Z) after the FBX axis change,
so a MeshPart's CFrame faces where the spear flies.

    spear_core    diamond-tipped lance, 6 studs long, 0.35 thick (shaft radius 0.175), tapered tail;
                  hexagonal section, the head a flattened diamond (0.6 wide, 0.28 deep).
                  ORIGIN AT THE GRIP: 2 studs from the tail, 4 from the tip (prompt, blueprint panel 2).
                  UV: V along the length (0 = tail, 1 = tip), U around.
    ribbon_helix  two thin flat ribbons wound as a double helix, 1.5 turns over the spear's 6 studs,
                  radius 0.4; both the width and the radius taper to the ends so the ribbons start and
                  finish on the spear. Same origin (the grip) and axis as spear_core.
                  UV: V along each ribbon (0..1), U across it -> glow_line.png fades toward V = 0 and 1,
                  so the ribbon's texture fades out at both ends.
    shock_ring    thin flat annulus in XY (normal +Z = Roblox +Y), outer diameter 1 stud, band 0.08;
                  origin at the centre; scaled 1 -> 6 studs in Roblox.
                  UV: U around the ring (seam at +X), V across the band -> glow_line.png (soft edges).
Exports one FBX per mesh into Game/assets/ (Blender Z-up -> Roblox Y-up, as Frost Jab), writes the
origin offsets to Game/assets/vfx/thunder_lance_meshes.json (Roblox imports centre a mesh on its
bounding box, so the grip's offset from the box centre is recorded) and saves the .blend.
Budget: under 400 triangles for the three together (prompt).
"""
import bpy, bmesh, json, math, os
from mathutils import Vector

ASSETS = r"C:\Roblox\Spin for ability\Game\assets"
META = os.path.join(ASSETS, "vfx", "thunder_lance_meshes.json")
COLL = "ThunderLance_Meshes"
TRI_BUDGET = 400
LENGTH, GRIP_FROM_TAIL, SHAFT_R = 6.0, 2.0, 0.175
HELIX_TURNS, HELIX_R = 1.5, 0.4

# palette (linear) for the preview material only: white #FFFDF0, yellow #FFE14D, deep gold #FFB000
WHITE, YELLOW, GOLD = (1.0, 0.98, 0.87, 1), (1.0, 0.75, 0.074, 1), (1.0, 0.434, 0.0, 1)


def fresh_collection():
    coll = bpy.data.collections.get(COLL)
    if coll:
        for ob in list(coll.objects):
            me = ob.data
            bpy.data.objects.remove(ob, do_unlink=True)
            if me and me.users == 0:
                bpy.data.meshes.remove(me)
    else:
        coll = bpy.data.collections.new(COLL)
        bpy.context.scene.collection.children.link(coll)
    return coll


def preview_material():
    """Colour along UV V (gold at V = 0 -> yellow -> white at V = 1), so the previews show the UV
    direction. Only for previews; Roblox ignores it (textures are white, colour is set in code)."""
    name = "ThunderLance_UVPreview"
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    uv = nt.nodes.new("ShaderNodeUVMap")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = GOLD
    ramp.color_ramp.elements[1].color = WHITE
    ramp.color_ramp.elements.new(0.5).color = YELLOW
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.4
    bsdf.inputs["Emission Strength"].default_value = 0.5
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(uv.outputs["UV"], sep.inputs[0])
    nt.links.new(sep.outputs["Y"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Emission Color"])
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    mat.diffuse_color = YELLOW
    return mat


def to_object(name, bm, coll, mat, smooth):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    return ob


def face(bm, uvl, verts, uvs):
    f = bm.faces.new(verts)
    for loop, uv in zip(f.loops, uvs):
        loop[uvl].uv = uv
    return f


def spear_core(coll, mat):
    """Rings along +Y (tail at -2, tip at +4); end caps are fans to a single point. 6 sides."""
    sides = 6
    y0 = -GRIP_FROM_TAIL
    # (y, radius across X, radius across Z)
    rings = [(y0 + 0.55, 0.08, 0.08), (y0 + 1.6, 0.15, 0.15), (y0 + 4.55, SHAFT_R, SHAFT_R),
             (y0 + 4.9, 0.30, 0.14)]
    tail, tip = Vector((0, y0, 0)), Vector((0, y0 + LENGTH, 0))
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    ring_verts = []
    for y, rx, rz in rings:
        ring_verts.append([bm.verts.new((rx * math.cos(a), y, rz * math.sin(a)))
                           for a in (math.tau * i / sides for i in range(sides))])
    vt, vp = bm.verts.new(tail), bm.verts.new(tip)
    v_of = lambda y: (y - y0) / LENGTH
    for i in range(sides):
        j = (i + 1) % sides
        u0, u1 = i / sides, (i + 1) / sides
        a, b = ring_verts[0][i], ring_verts[0][j]
        face(bm, uvl, (vt, b, a), ((u0 + 0.5 / sides, 0), (u1, v_of(rings[0][0])), (u0, v_of(rings[0][0]))))
        for k in range(len(rings) - 1):
            a0, b0 = ring_verts[k][i], ring_verts[k][j]
            a1, b1 = ring_verts[k + 1][i], ring_verts[k + 1][j]
            va, vb = v_of(rings[k][0]), v_of(rings[k + 1][0])
            face(bm, uvl, (a0, b0, b1, a1), ((u0, va), (u1, va), (u1, vb), (u0, vb)))
        a, b = ring_verts[-1][i], ring_verts[-1][j]
        face(bm, uvl, (a, b, vp), ((u0, v_of(rings[-1][0])), (u1, v_of(rings[-1][0])), (u0 + 0.5 / sides, 1)))
    return to_object("spear_core", bm, coll, mat, smooth=False)


def ribbon_helix(coll, mat, segments=24, width=0.13):
    """Two strands half a turn apart. Each is a strip of `segments` quads whose width lies on the
    helix's cylinder (perpendicular to the strand's direction); width and radius go to ~0 at the ends."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    y0 = -GRIP_FROM_TAIL
    for strand in range(2):
        phase = math.pi * strand
        left, right = [], []
        for s in range(segments + 1):
            t = s / segments
            taper = math.sin(math.pi * t) ** 0.6
            r = HELIX_R * (0.25 + 0.75 * taper)
            ang = phase + math.tau * HELIX_TURNS * t
            y = y0 + LENGTH * t
            radial = Vector((math.cos(ang), 0, math.sin(ang)))
            centre = Vector((0, y, 0)) + radial * r
            # tangent of the helix, then the width direction on the cylinder surface
            dang = math.tau * HELIX_TURNS / LENGTH
            tangent = Vector((-math.sin(ang) * r * dang, 1, math.cos(ang) * r * dang)).normalized()
            across = tangent.cross(radial).normalized()
            half = 0.5 * width * max(taper, 0.04)
            left.append(bm.verts.new(centre - across * half))
            right.append(bm.verts.new(centre + across * half))
        for s in range(segments):
            v0, v1 = s / segments, (s + 1) / segments
            face(bm, uvl, (left[s], right[s], right[s + 1], left[s + 1]), ((0, v0), (1, v0), (1, v1), (0, v1)))
    return to_object("ribbon_helix", bm, coll, mat, smooth=True)


def shock_ring(coll, mat, segments=32, outer=0.5, band=0.08):
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    inner = outer - band
    ins, outs = [], []
    for i in range(segments):
        a = math.tau * i / segments
        d = Vector((math.cos(a), math.sin(a), 0))
        ins.append(bm.verts.new(d * inner))
        outs.append(bm.verts.new(d * outer))
    for i in range(segments):
        j = (i + 1) % segments
        u0, u1 = i / segments, (i + 1) / segments
        face(bm, uvl, (ins[i], outs[i], outs[j], ins[j]), ((u0, 0), (u0, 1), (u1, 1), (u1, 0)))
    return to_object("shock_ring", bm, coll, mat, smooth=False)


def export_fbx(ob, path):
    bpy.context.view_layer.update()
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types={"MESH"},
                             apply_scale_options="FBX_SCALE_UNITS", axis_forward="-Z", axis_up="Y",
                             mesh_smooth_type="FACE", use_mesh_modifiers=True, bake_anim=False)
    ob.select_set(False)


def tris(me):
    return sum(len(p.vertices) - 2 for p in me.polygons)


def build():
    if bpy.context.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    coll = fresh_collection()
    mat = preview_material()
    meshes = [spear_core(coll, mat), ribbon_helix(coll, mat), shock_ring(coll, mat)]
    meta, total = {}, 0
    for ob in meshes:
        me = ob.data
        n = tris(me)
        total += n
        lo = Vector([min(v.co[i] for v in me.vertices) for i in range(3)])
        hi = Vector([max(v.co[i] for v in me.vertices) for i in range(3)])
        centre = (lo + hi) / 2
        # Blender (x, y, z) -> Roblox (x, z, -y): the origin's offset from the bounding-box centre
        off = -centre
        size = hi - lo
        meta[ob.name] = {"tris": n, "sizeRoblox": [round(size.x, 4), round(size.z, 4), round(size.y, 4)],
                         "originFromCentreRoblox": [round(off.x, 4), round(off.z, 4), round(-off.y, 4)]}
        export_fbx(ob, os.path.join(ASSETS, ob.name + ".fbx"))
        uses = {}
        for p in me.polygons:
            for k in p.edge_keys:
                uses[k] = uses.get(k, 0) + 1
        open_edges = sum(1 for c in uses.values() if c < 2)  # ribbons and the ring are open strips on purpose
        print(f"{ob.name:13s} {n:3d} tris  size (Roblox X,Y,Z) {meta[ob.name]['sizeRoblox']}  origin from box "
              f"centre {meta[ob.name]['originFromCentreRoblox']}  UV layers {len(me.uv_layers)}  "
              f"open edges {open_edges}  -> {ob.name}.fbx")
    meta["_note"] = ("Roblox axes. Imported meshes are centred on their bounding box; the Blender origin "
                     "(spear grip, ring centre) sits at originFromCentreRoblox from that centre.")
    with open(META, "w") as fh:
        json.dump(meta, fh, indent=1)
    print(f"total {total} tris (budget {TRI_BUDGET}) {'OK' if total < TRI_BUDGET else 'OVER'}")
    bpy.ops.wm.save_mainfile()
    print("saved .blend and", META)


build()

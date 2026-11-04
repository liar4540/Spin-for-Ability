"""Spin for Abilities - Gale Step, stage 2: wind meshes (collection "GaleStep_Meshes").

Run inside Blender with Game/assets/gale_step.blend open (after build_gale_step_anim.py):
    exec(open(r"<this file>").read())
1 Blender unit = 1 stud. Every mesh is built at the origin with identity transforms (nothing to
apply), flat-ribbon geometry meant for MeshPart.DoubleSided = true, UV U running ALONG the shape
(0 = head, 1 = tail, for wind_gradient.png: solid at U = 0, fading out at U = 1) and V across it.

    wind_crescent_a  gentle 70 deg arc, chord 4 studs, symmetric taper, flat (lies in XY)
    wind_crescent_b  hooked 130 deg arc, chord 4 studs, fat head near U = 0.3, rises 0.4 along Z
    wind_ring        flat annulus in XY: 5 studs across (outer r 2.5), 0.4 wide (inner r 2.1)
    wind_spiral      1.5-turn ribbon rising 0 -> 5 studs, radius 3 at the bottom -> 2 at the top,
                     band up to 0.8 tall, tapering to points at both ends; origin at the base centre

Origins: crescents on the middle of the stroke, ring at its centre, spiral at its base centre.
Exports one FBX per mesh into Game/assets/ (Blender Z-up -> Roblox Y-up, like the Pebble Toss FBXs),
then saves the .blend.
"""
import bpy, bmesh, math, os
from mathutils import Vector

ASSETS = r"C:\Roblox\Spin for ability\Game\assets"
COLL = "GaleStep_Meshes"
TRI_BUDGET = 500


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
    """Emission along U (#E9FBFF head -> #2FA8D8 tail, fading out) so the stage 2 render shows the
    UV direction. Only for previews; Roblox ignores it."""
    name = "GaleStep_UVPreview"
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    uv = nt.nodes.new("ShaderNodeUVMap")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.815, 0.965, 1.0, 1)     # #E9FBFF (linear)
    ramp.color_ramp.elements[1].color = (0.028, 0.391, 0.687, 1)   # #2FA8D8 (linear)
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 1.0
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(uv.outputs["UV"], sep.inputs[0])
    nt.links.new(sep.outputs[0], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], emit.inputs["Color"])
    nt.links.new(emit.outputs[0], out.inputs["Surface"])
    mat.diffuse_color = (0.5, 0.9, 1.0, 1)
    return mat


def ribbon(name, centre, edge, coll, mat, tips=True, facing_up=True):
    """Build a ribbon from N stations. centre[i] is the stroke line, edge[i] = (outer, inner) offsets
    from it. With tips=True the first and last stations collapse to a single vertex (a point).
    UV: U = i / (N - 1) along, V = 1 on the outer edge, 0 on the inner one."""
    n = len(centre)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    verts = []
    for i in range(n):
        u = i / (n - 1)
        if tips and i in (0, n - 1):
            v = bm.verts.new(centre[i])
            verts.append(((v, (u, 0.5)), (v, (u, 0.5))))
        else:
            o, inn = edge[i]
            verts.append(((bm.verts.new(centre[i] + o), (u, 1.0)), (bm.verts.new(centre[i] + inn), (u, 0.0))))
    for i in range(n - 1):
        (a, ua), (b, ub) = verts[i]
        (c, uc), (d, ud) = verts[i + 1]
        quad = [(a, ua), (b, ub), (d, ud), (c, uc)]
        seen, poly = set(), []
        for v, t in quad:
            if v not in seen:
                seen.add(v)
                poly.append((v, t))
        if len(poly) < 3:
            continue
        # split every quad into 2 tris so the count is exact
        tris = [poly] if len(poly) == 3 else [[poly[0], poly[1], poly[2]], [poly[0], poly[2], poly[3]]]
        for tri in tris:
            f = bm.faces.new([v for v, _ in tri])
            for loop, (_, t) in zip(f.loops, tri):
                loop[uv].uv = t
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # flat shapes face up (+Z), the spiral band faces out from its axis
    facing = sum(((f.normal.z if facing_up else f.normal.dot(Vector((f.calc_center_median().x, f.calc_center_median().y, 0))))
                  for f in bm.faces), 0.0)
    if facing < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    return ob


def crescent(name, arc_deg, width, peak_shift, rise, coll, mat, chord=4.0, stations=25):
    """Arc in XY bulging +Y, chord along X; outer (convex) edge crisp, width grows inward."""
    th = math.radians(arc_deg)
    R = chord / (2 * math.sin(th / 2))
    centre, edge = [], []
    for i in range(stations):
        t = i / (stations - 1)
        phi = -th / 2 + th * t
        p = Vector((R * math.sin(phi), R * math.cos(phi) - R, rise * (t - 0.5)))
        n = Vector((math.sin(phi), math.cos(phi), 0))
        w = width * math.sin(math.pi * t ** peak_shift) ** 0.8
        centre.append(p)
        edge.append((n * w * 0.35, -n * w * 0.65))
    # centre the stroke on its bounding box so the origin sits in the middle of the swoosh
    lo =Vector([min(c[k] for c in centre) for k in range(3)])
    hi = Vector([max(c[k] for c in centre) for k in range(3)])
    off = (lo + hi) / 2
    centre = [c - off for c in centre]
    return ribbon(name, centre, edge, coll, mat)


def ring(name, outer_r, width, coll, mat, segments=48):
    centre, edge = [], []
    r = outer_r - width / 2
    for i in range(segments + 1):                       # seam: first and last station overlap
        a = 2 * math.pi * i / segments
        n = Vector((math.cos(a), math.sin(a), 0))
        centre.append(n * r)
        edge.append((n * width / 2, -n * width / 2))
    return ribbon(name, centre, edge, coll, mat, tips=False)


def spiral(name, turns, height, r0, r1, band, coll, mat, per_turn=32):
    n = int(turns * per_turn) + 1
    centre, edge = [], []
    for i in range(n):
        t = i / (n - 1)
        a = 2 * math.pi * turns * t
        radial = Vector((math.cos(a), math.sin(a), 0))
        r = r0 + (r1 - r0) * t
        w = band * math.sin(math.pi * t) ** 0.6
        up = (Vector((0, 0, 1)) + radial * 0.35).normalized()   # band leans out a little, like a cone
        centre.append(radial * r + Vector((0, 0, height * t)))
        edge.append((up * w / 2, -up * w / 2))
    # keep the base on Z = 0 and the top on Z = height (the band's ends are points)
    return ribbon(name, centre, edge, coll, mat, facing_up=False)


def export_fbx(ob, path):
    bpy.context.view_layer.update()   # the rebuild just removed objects; refresh the layer first
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types={"MESH"},
                             apply_scale_options="FBX_SCALE_UNITS", axis_forward="-Z", axis_up="Y",
                             mesh_smooth_type="FACE", use_mesh_modifiers=True, bake_anim=False)
    ob.select_set(False)


def build():
    coll = fresh_collection()
    mat = preview_material()
    meshes = [
        crescent("wind_crescent_a", 70, 0.38, 1.0, 0.0, coll, mat),
        crescent("wind_crescent_b", 130, 0.48, 0.6, 0.4, coll, mat),
        ring("wind_ring", 2.5, 0.4, coll, mat),
        spiral("wind_spiral", 1.5, 5.0, 3.0, 2.0, 0.8, coll, mat),
    ]
    total = 0
    for ob in meshes:
        assert ob.location.length == 0 and ob.rotation_euler.to_matrix().is_identity and tuple(ob.scale) == (1, 1, 1)
        tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        total += tris
        export_fbx(ob, os.path.join(ASSETS, ob.name + ".fbx"))
        d = ob.dimensions
        print(f"{ob.name:16s} tris {tris:3d}  size {d.x:.2f} x {d.y:.2f} x {d.z:.2f}  -> {ob.name}.fbx")
    print(f"total tris {total} (budget {TRI_BUDGET})")
    assert total < TRI_BUDGET
    bpy.ops.wm.save_mainfile()
    return meshes


build()

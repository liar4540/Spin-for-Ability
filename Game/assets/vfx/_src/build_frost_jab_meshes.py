"""Spin for Abilities - Frost Jab, stage 5: ice meshes (collection "FrostJab_Meshes").

Run inside Blender with Game/assets/frost_jab.blend open:
    exec(open(r"<this file>").read())
1 Blender unit = 1 stud. Low poly, FLAT shaded (crisp facets like images/abilities/Ice shardsjpg.jpg).
Every mesh is built at the origin with identity transforms (nothing to apply).

    ice_shard_a..d  4 crystal variants (so random picks don't look copy-pasted): a narrow base, a
                    widest ring part-way up, a point at the tip (sometimes off-centre). Long axis +Z;
                    ORIGIN AT THE BASE (where a shard is attached / launched from).
                    UV: V runs ALONG the shard (0 = base, 1 = tip), U around it -> frost_shard.png.
    frost_ring      flat annulus in XY, 5 studs across (outer r 2.5), 0.6 wide; origin at the centre.
                    UV: U AROUND the ring (0..1, seam at +X), V across it (0 = inner, 1 = outer
                    edge) -> frost_ring.png.
    frost_crown     12 small ice spikes standing on a 2.3-stud circle, leaning outward 20-40 deg,
                    0.45-0.95 tall; origin at the centre (on the ground). UV: V along each spike
                    (0 = base, 1 = tip) -> frost_shard.png, like the shards.
Exports one FBX per mesh into Game/assets/ (Blender Z-up -> Roblox Y-up, as the Gale Step / Pebble
Toss FBXs), then saves the .blend. Total triangles must stay under 300 for the whole skill.
"""
import bpy, bmesh, math, os, random
from mathutils import Vector

ASSETS = r"C:\Roblox\Spin for ability\Game\assets"
COLL = "FrostJab_Meshes"
TRI_BUDGET = 300

# palette (linear) for the preview material only: core #F2FBFF, main #A8E6FF, deep #4FA3D9
CORE, MAIN, DEEP = (0.888, 0.965, 1.0, 1), (0.392, 0.791, 1.0, 1), (0.078, 0.366, 0.693, 1)


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
    """Colour along UV V (deep at V = 0 -> main -> core at V = 1) so the stage 5 render shows the UV
    direction; lit (plus a little emission) so the flat facets read. Only for previews; Roblox
    ignores it."""
    name = "FrostJab_UVPreview"
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    uv = nt.nodes.new("ShaderNodeUVMap")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = DEEP
    ramp.color_ramp.elements[1].color = CORE
    mid = ramp.color_ramp.elements.new(0.5)
    mid.color = MAIN
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.35
    bsdf.inputs["Emission Strength"].default_value = 0.35
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(uv.outputs["UV"], sep.inputs[0])
    nt.links.new(sep.outputs["Y"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Emission Color"])
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    mat.diffuse_color = MAIN
    return mat


def to_object(name, bm, coll, mat):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    return ob


def add_tri(bm, uv_layer, verts, uvs):
    face = bm.faces.new(verts)
    for loop, uv in zip(face.loops, uvs):
        loop[uv_layer].uv = uv
    return face


def crystal(name, coll, mat, sides, length, radius, waist, base_scale, tip_offset, seed):
    """Base fan (sides tris) + wall quads split in 2 (2 * sides) + tip fan (sides) = 4 * sides tris.
    waist: height of the widest ring as a fraction of the length. Rings get a small random wobble in
    radius and angle so the facets are uneven, like a real crystal."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    phase = rnd.uniform(0, math.tau)
    base_ring, mid_ring = [], []
    for i in range(sides):
        a = phase + math.tau * i / sides + rnd.uniform(-0.12, 0.12)
        d = Vector((math.cos(a), math.sin(a), 0))
        base_ring.append(bm.verts.new(d * radius * base_scale * rnd.uniform(0.85, 1.1)))
        mid_ring.append(bm.verts.new(d * radius * rnd.uniform(0.85, 1.12) + Vector((0, 0, length * waist))))
    base_c = bm.verts.new((0, 0, 0))
    tip = bm.verts.new((tip_offset[0], tip_offset[1], length))
    vb, vm = 0.0, waist
    for i in range(sides):
        j = (i + 1) % sides
        u0, u1 = i / sides, (i + 1) / sides
        um = (u0 + u1) / 2
        add_tri(bm, uvl, (base_c, base_ring[j], base_ring[i]), ((um, 0), (u1, vb), (u0, vb)))  # bottom
        add_tri(bm, uvl, (base_ring[i], base_ring[j], mid_ring[j]), ((u0, vb), (u1, vb), (u1, vm)))
        add_tri(bm, uvl, (base_ring[i], mid_ring[j], mid_ring[i]), ((u0, vb), (u1, vm), (u0, vm)))
        add_tri(bm, uvl, (mid_ring[i], mid_ring[j], tip), ((u0, vm), (u1, vm), (um, 1.0)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return to_object(name, bm, coll, mat)


def ring(name, coll, mat, outer_r=2.5, width=0.6, segments=32):
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    inner_r = outer_r - width
    inner, outer = [], []
    for i in range(segments + 1):                       # seam: first and last station overlap (U 0 / 1)
        a = math.tau * i / segments
        d = Vector((math.cos(a), math.sin(a), 0))
        inner.append(bm.verts.new(d * inner_r))
        outer.append(bm.verts.new(d * outer_r))
    for i in range(segments):
        u0, u1 = i / segments, (i + 1) / segments
        add_tri(bm, uvl, (inner[i], outer[i], outer[i + 1]), ((u0, 0), (u0, 1), (u1, 1)))
        add_tri(bm, uvl, (inner[i], outer[i + 1], inner[i + 1]), ((u0, 0), (u1, 1), (u1, 0)))
    for f in bm.faces:                                  # face up (+Z)
        if f.normal.z < 0:
            f.normal_flip()
    return to_object(name, bm, coll, mat)


def crown(name, coll, mat, count=12, radius=2.3, seed=7):
    """count 3-sided open pyramids (3 tris each), leaning outward."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    for k in range(count):
        a = math.tau * k / count + rnd.uniform(-0.12, 0.12)
        out = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-out.y, out.x, 0))
        base = out * radius * rnd.uniform(0.94, 1.04)
        h = rnd.uniform(0.45, 0.95)
        lean = math.radians(rnd.uniform(20, 40))
        w = rnd.uniform(0.16, 0.24)
        axis = (out * math.sin(lean) + Vector((0, 0, math.cos(lean)))).normalized()
        tip = bm.verts.new(base + axis * h)
        corners = [bm.verts.new(base + (side * math.cos(t) + out * math.sin(t)) * w)
                   for t in (math.radians(rnd.uniform(-10, 10)) + i * math.tau / 3 for i in range(3))]
        for i in range(3):
            j = (i + 1) % 3
            add_tri(bm, uvl, (corners[i], corners[j], tip), ((i / 3, 0), ((i + 1) / 3, 0), ((i + 0.5) / 3, 1)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return to_object(name, bm, coll, mat)


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


def build():
    if bpy.context.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    coll = fresh_collection()
    mat = preview_material()
    meshes = [
        crystal("ice_shard_a", coll, mat, sides=5, length=1.6, radius=0.30, waist=0.62, base_scale=0.55,
                tip_offset=(0.05, 0.0), seed=1),
        crystal("ice_shard_b", coll, mat, sides=4, length=1.1, radius=0.34, waist=0.50, base_scale=0.65,
                tip_offset=(0.12, 0.05), seed=2),
        crystal("ice_shard_c", coll, mat, sides=6, length=2.0, radius=0.22, waist=0.72, base_scale=0.50,
                tip_offset=(0.0, 0.0), seed=3),
        crystal("ice_shard_d", coll, mat, sides=5, length=1.35, radius=0.28, waist=0.55, base_scale=0.60,
                tip_offset=(-0.08, 0.06), seed=4),
        ring("frost_ring", coll, mat),
        crown("frost_crown", coll, mat),
    ]
    total = 0
    for ob in meshes:
        assert ob.location.length == 0 and ob.rotation_euler.to_matrix().is_identity and tuple(ob.scale) == (1, 1, 1)
        me = ob.data
        tris = sum(len(p.vertices) - 2 for p in me.polygons)
        total += tris
        export_fbx(ob, os.path.join(ASSETS, ob.name + ".fbx"))
        lo = [min(v.co[i] for v in me.vertices) for i in range(3)]
        hi = [max(v.co[i] for v in me.vertices) for i in range(3)]
        uv = me.uv_layers[0].data
        us, vs = [l.uv[0] for l in uv], [l.uv[1] for l in uv]
        print(f"{ob.name:13s} tris {tris:3d}  bounds x {lo[0]:+.2f}..{hi[0]:+.2f}  y {lo[1]:+.2f}..{hi[1]:+.2f}"
              f"  z {lo[2]:+.2f}..{hi[2]:+.2f}  uv u {min(us):.2f}..{max(us):.2f} v {min(vs):.2f}..{max(vs):.2f}"
              f"  flat {not any(p.use_smooth for p in me.polygons)}  -> {ob.name}.fbx")
    print(f"total tris {total} (budget {TRI_BUDGET})")
    assert total < TRI_BUDGET
    write_offsets(meshes)
    bpy.ops.wm.save_mainfile()
    return meshes


def write_offsets(meshes):
    """Roblox centres an imported mesh on its bounding box, so the Blender origin (shard base, ring
    centre) is lost. Record, per mesh, the size and where the origin sits from the box centre, in
    Roblox axes (x, y, z) = Blender (x, z, -y), for the VFX code."""
    import json
    out = {}
    for ob in meshes:
        vs = [v.co for v in ob.data.vertices]
        lo = Vector([min(v[i] for v in vs) for i in range(3)])
        hi = Vector([max(v[i] for v in vs) for i in range(3)])
        c = (lo + hi) / 2
        size = hi - lo
        out[ob.name] = {"tris": sum(len(p.vertices) - 2 for p in ob.data.polygons),
                        "size": [round(size.x, 4), round(size.z, 4), round(size.y, 4)],
                        "origin_from_centre": [round(-c.x, 4), round(-c.z, 4), round(c.y, 4)]}
    path = os.path.join(ASSETS, "vfx", "frost_jab_meshes.json")
    with open(path, "w") as fh:
        json.dump(out, fh, indent=1)
    print("wrote", path)


build()

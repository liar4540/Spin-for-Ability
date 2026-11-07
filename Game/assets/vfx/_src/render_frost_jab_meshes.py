"""Spin for Abilities - Frost Jab stage 5 preview: every FrostJab_Meshes mesh next to the R15 rig.

Run inside Blender after build_frost_jab_meshes.py:
    exec(open(r"<this file>").read())
Moves the meshes into a row for the shot, renders with EEVEE on a 1-stud checker floor (front view
with the rig in its ready pose, and a top view of the ring + crown), then puts every transform back
(the .blend is not saved). The preview material colours each mesh along its UV V (deep -> main ->
core), so the gradient direction is visible: base -> tip on shards/spikes, inner -> outer on the ring.
Writes Game/assets/vfx/previews/frost_jab/meshes_front.png, meshes_top.png and a labels json; the
sheet is composed by compose_frost_jab_stage5.py.
"""
import bpy, math, json
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

OUT_DIR = r"C:\Roblox\Spin for ability\Game\assets\vfx\previews\frost_jab"
LAYOUT = {  # name: (location, rotation) for the shot only; the rig stands at the origin facing +Y
    "ice_shard_a": ((3.0, 0, 0.02), (0, 0, 0)),
    "ice_shard_b": ((4.3, 0, 0.02), (0, 0, 0)),
    "ice_shard_c": ((5.6, 0, 0.02), (0, 0, 0)),
    "ice_shard_d": ((6.9, 0, 0.02), (0, 0, 0)),
    "frost_ring": ((-6.0, 0, 0.02), (0, 0, 0)),
    "frost_crown": ((-6.0, 0, 0.02), (0, 0, 0)),
}
VIEWS = {  # name: (eye, target, lens, size)
    "front": (Vector((0.4, 24.0, 7.5)), Vector((0.4, 0, 1.8)), 40, (1800, 820)),
    "top": (Vector((-6.0, 0.01, 16.0)), Vector((-6.0, 0, 0)), 50, (820, 820)),
}


def checker_floor():
    bpy.ops.mesh.primitive_plane_add(size=300, location=(0, 0, 0))
    floor = bpy.context.active_object
    floor.name = "_preview_floor"
    mat = bpy.data.materials.new("_preview_floor")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tex = nt.nodes.new("ShaderNodeTexChecker")
    tex.inputs["Scale"].default_value = 150          # 300-stud plane -> 1-stud squares
    tex.inputs["Color1"].default_value = (0.020, 0.022, 0.027, 1)
    tex.inputs["Color2"].default_value = (0.030, 0.033, 0.040, 1)
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    floor.data.materials.append(mat)
    return floor, mat


def render():
    sc = bpy.context.scene
    saved_tf = {n: (bpy.data.objects[n].location.copy(), bpy.data.objects[n].rotation_euler.copy()) for n in LAYOUT}
    saved = (sc.camera, sc.render.engine, sc.render.resolution_x, sc.render.resolution_y, sc.frame_current,
             sc.render.film_transparent, sc.view_settings.view_transform, sc.render.filepath)
    temp = []
    floor, fmat = checker_floor()
    temp.append(floor)
    cam = bpy.data.objects.new("_preview_cam", bpy.data.cameras.new("_preview_cam"))
    sc.collection.objects.link(cam)
    temp.append(cam)
    sun = bpy.data.objects.new("_preview_sun", bpy.data.lights.new("_preview_sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(150))
    sc.collection.objects.link(sun)
    temp.append(sun)
    labels = {}
    try:
        for n, (loc, rot) in LAYOUT.items():
            bpy.data.objects[n].location, bpy.data.objects[n].rotation_euler = loc, rot
            bpy.data.objects[n].visible_shadow = False        # VFX cast no shadows in game either
        try:
            sc.render.engine = "BLENDER_EEVEE"
        except TypeError as e:
            print("engine:", e)
        sc.view_settings.view_transform = "Standard"
        sc.render.film_transparent = False
        sc.world.use_nodes = True
        bg = next(n for n in sc.world.node_tree.nodes if n.type == "BACKGROUND")
        bg.inputs["Color"].default_value = (0.03, 0.032, 0.038, 1)
        bg.inputs["Strength"].default_value = 1.0
        sc.camera = cam
        sc.frame_set(0)
        sc.render.image_settings.file_format = "PNG"
        for view, (eye, target, lens, (W, H)) in VIEWS.items():
            cam.data.lens = lens
            cam.location = eye
            cam.rotation_euler = (target - eye).to_track_quat("-Z", "Y").to_euler()
            sc.render.resolution_x, sc.render.resolution_y = W, H
            sc.render.filepath = f"{OUT_DIR}\\meshes_{view}.png"
            bpy.ops.render.render(write_still=True)
            if view != "front":
                continue
            items = [("R15 rig (ready pose)", None, Vector((0, 0, 5.9)))]
            for n in LAYOUT:
                ob = bpy.data.objects[n]
                corners = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
                top = max(c.z for c in corners)
                if n == "frost_crown":
                    continue
                if n == "frost_ring":
                    items.append(("frost_ring + frost_crown", ob, Vector((ob.location.x, 0, 1.3))))
                else:
                    items.append((n, ob, Vector((ob.location.x, 0, top + 0.45))))
            for name, ob, p in items:
                co = world_to_camera_view(sc, cam, p)
                text = name
                if ob is not None:
                    tris = sum(len(q.vertices) - 2 for q in ob.data.polygons)
                    d = ob.dimensions
                    if ob.name == "frost_ring":
                        crown_ob = bpy.data.objects["frost_crown"]
                        tris += sum(len(q.vertices) - 2 for q in crown_ob.data.polygons)
                        text += f"\n5.0 across, spikes {crown_ob.dimensions.z:.2f} tall, {tris} tris"
                    else:
                        text += f"\n{d.z:.2f} long, {max(d.x, d.y):.2f} wide, {tris} tris"
                labels[name] = (text, int(co.x * W), int((1 - co.y) * H))
    finally:
        for n, (loc, rot) in saved_tf.items():
            bpy.data.objects[n].location, bpy.data.objects[n].rotation_euler = loc, rot
        (sc.camera, sc.render.engine, sc.render.resolution_x, sc.render.resolution_y, f,
         sc.render.film_transparent, sc.view_settings.view_transform, sc.render.filepath) = saved
        sc.frame_set(f)
        for ob in temp:
            data = ob.data
            bpy.data.objects.remove(ob, do_unlink=True)
            if isinstance(data, bpy.types.Mesh):
                bpy.data.meshes.remove(data)
            elif isinstance(data, bpy.types.Camera):
                bpy.data.cameras.remove(data)
            else:
                bpy.data.lights.remove(data)
        bpy.data.materials.remove(fmat)
    return labels


LABELS = render()
with open(OUT_DIR + "\\meshes_labels.json", "w") as fh:
    json.dump(LABELS, fh)
print("rendered", LABELS)

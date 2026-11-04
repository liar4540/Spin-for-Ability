"""Spin for Abilities - Gale Step stage 2 preview: every GaleStep_Meshes mesh next to the R15 rig.

Run inside Blender after build_gale_step_meshes.py:
    exec(open(r"<this file>").read())
Moves the meshes into a row for the shot (crescents stood upright), renders with EEVEE on a 1-stud
checker floor, labels each one, then puts every transform back (the .blend is not saved).
Writes Game/assets/vfx/previews/gale_step_stage2_meshes.png.
"""
import bpy, math, json
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

OUT = r"C:\Roblox\Spin for ability\Game\assets\vfx\previews\gale_step_stage2_meshes.png"
LAYOUT = {  # name: (location, rotation) for the shot only
    "wind_crescent_a": ((-9.0, 0, 2.6), (math.radians(90), 0, 0)),
    "wind_crescent_b": ((-4.6, 0, 2.6), (math.radians(90), 0, 0)),
    "wind_ring": ((5.2, 0, 0.03), (0, 0, 0)),
    "wind_spiral": ((11.8, 0, 0.03), (0, 0, 0)),
}
W, H = 1800, 820


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
             sc.render.film_transparent, sc.view_settings.view_transform)
    temp = []
    floor, fmat = checker_floor()
    temp.append(floor)
    cam = bpy.data.objects.new("_preview_cam", bpy.data.cameras.new("_preview_cam"))
    cam.data.lens = 35
    sc.collection.objects.link(cam)
    temp.append(cam)
    sun = bpy.data.objects.new("_preview_sun", bpy.data.lights.new("_preview_sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    sc.collection.objects.link(sun)
    temp.append(sun)
    try:
        for n, (loc, rot) in LAYOUT.items():
            bpy.data.objects[n].location, bpy.data.objects[n].rotation_euler = loc, rot
            bpy.data.objects[n].visible_shadow = False        # VFX cast no shadows in game either
        eye, target = Vector((1.4, -30.0, 11.0)), Vector((1.4, 0, 2.0))
        cam.location = eye
        cam.rotation_euler = (target - eye).to_track_quat("-Z", "Y").to_euler()
        try:
            sc.render.engine = "BLENDER_EEVEE"
        except TypeError as e:
            print("engine:", e)
        sc.view_settings.view_transform = "Standard"
        sc.render.resolution_x, sc.render.resolution_y = W, H
        sc.render.film_transparent = False
        sc.world.use_nodes = True
        bg = next(n for n in sc.world.node_tree.nodes if n.type == "BACKGROUND")
        bg.inputs["Color"].default_value = (0.03, 0.032, 0.038, 1)
        bg.inputs["Strength"].default_value = 1.0
        sc.camera = cam
        sc.frame_set(0)
        sc.render.filepath = OUT
        sc.render.image_settings.file_format = "PNG"
        bpy.ops.render.render(write_still=True)
        # label anchors: a point above each object, in pixels (top-left origin)
        labels = []
        rig_top = Vector((0, 0, 5.6))
        items = [(n, bpy.data.objects[n]) for n in LAYOUT] + [("R15 rig\n5.4 studs tall", None)]
        for name, ob in items:
            if ob is None:
                p = rig_top
            else:
                corners = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
                p = Vector((sum(c.x for c in corners) / 8, 0, max(c.z for c in corners) + 0.5))
                d = ob.dimensions
                name = f"{name}\n{d.x:.1f} x {d.y:.1f} x {d.z:.1f} studs" if ob.name != "wind_spiral" else \
                       f"{name}\nr 3 -> 2, 5 tall, 1.5 turns"
                tris = sum(len(q.vertices) - 2 for q in ob.data.polygons)
                name += f", {tris} tris"
            co = world_to_camera_view(sc, cam, p)
            labels.append((name, int(co.x * W), int((1 - co.y) * H)))
    finally:
        for n, (loc, rot) in saved_tf.items():
            bpy.data.objects[n].location, bpy.data.objects[n].rotation_euler = loc, rot
        (sc.camera, sc.render.engine, sc.render.resolution_x, sc.render.resolution_y, f,
         sc.render.film_transparent, sc.view_settings.view_transform) = saved
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
with open(OUT + ".labels.json", "w") as fh:
    json.dump(LABELS, fh)
print("rendered", OUT, LABELS)

"""Spin for Abilities - Thunder Lance stage 5 preview: every ThunderLance_Meshes mesh next to the R15 rig.

Run inside Blender after build_thunder_lance_meshes.py:
    exec(open(r"<this file>").read())
Moves the meshes into a row for the shot (spear and ribbons turned to lie along X so the front camera
sees their whole length, the ring stood up to face the camera), renders with EEVEE on a 1-stud
checker floor next to the rig in its ready pose (frame 0), then puts every transform back (the .blend
is not saved). The preview material colours each mesh along its UV V (gold -> yellow -> white), so the
UV direction is visible: tail -> tip on the spear, end -> end on each ribbon, inner -> outer on the ring.
Writes Game/assets/vfx/previews/thunder_lance/meshes_front.png and meshes_labels.json; the sheet is
composed by compose_thunder_lance_stage5.py.
"""
import bpy, math, json
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

OUT_DIR = "C:/Roblox/Spin for ability/Game/assets/vfx/previews/thunder_lance"
LAYOUT = {  # name: (location, rotation) for the shot only; the rig stands at the origin facing +Y
    "spear_core": ((4.6, 0, 4.4), (0, 0, math.radians(-90))),     # grip at hand height, tip to the right
    "ribbon_helix": ((4.6, 0, 2.6), (0, 0, math.radians(-90))),
    "shock_ring": ((-3.2, 0, 2.6), (math.radians(90), 0, 0)),       # 1 stud across here; 1 -> 6 in Roblox
}
VIEWS = {  # name: (eye, target, lens, size)
    "front": (Vector((2.2, 26.0, 6.0)), Vector((2.2, 0, 2.8)), 40, (1800, 820)),
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
                items.append((n, ob, Vector((ob.location.x, 0, top + 0.5))))
            for name, ob, p in items:
                co = world_to_camera_view(sc, cam, p)
                text = name
                if ob is not None:
                    tris = sum(len(q.vertices) - 2 for q in ob.data.polygons)
                    d = ob.dimensions
                    if ob.name == "shock_ring":
                        text += f"\n{max(d):.2f} across (scaled 1 -> 6 studs in game), {tris} tris"
                    else:
                        text += f"\n{max(d):.2f} long, {sorted(d)[1]:.2f} wide, {tris} tris"
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

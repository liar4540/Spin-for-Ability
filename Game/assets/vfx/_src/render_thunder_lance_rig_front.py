"""Spin for Abilities - Thunder Lance stage 1: front render of ThunderLanceRig with a yellow ball on
every bone head (the joint positions), to sit next to the Studio capture.

Run inside Blender after build_thunder_lance_rig.py:
    exec(open(r"<this file>").read())
Writes Game/assets/vfx/previews/thunder_lance/blender_front.png (600x800, Workbench). Orthographic,
6.2 studs tall, camera centre 2.55 studs up, so the floor sits on row 729. The camera is on the rig's
front (+Y), so the rig's right arm is on the image's left, as in a Studio front view.
Markers, camera and materials are temporary and removed again; the .blend is not saved.
"""
import bpy, os
from mathutils import Vector

OUT = r"C:\Roblox\Spin for ability\Game\assets\vfx\previews\thunder_lance\blender_front.png"
RIG_NAME = "ThunderLanceRig"
ORTHO, CAM_Z = 6.2, 2.55

sc = bpy.context.scene
rig = bpy.data.objects[RIG_NAME]
temp, mats = [], []
yellow = bpy.data.materials.new("_tl_marker")
yellow.diffuse_color = (1.0, 0.86, 0.24, 1)
mats.append(yellow)
for b in rig.data.bones:
    if b.name == "HumanoidRootPart":
        continue
    head = rig.matrix_world @ b.head_local
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.11, location=head + Vector((0, 0.6, 0)))
    ob = bpy.context.active_object
    ob.name = f"_tl_marker_{b.name}"
    ob.data.materials.append(yellow)
    temp.append(ob)

cam_data = bpy.data.cameras.new("_tl_cam")
cam_data.type, cam_data.ortho_scale = "ORTHO", ORTHO
cam = bpy.data.objects.new("_tl_cam", cam_data)
sc.collection.objects.link(cam)
temp.append(cam)
cam.location = (0, 20, CAM_Z)
cam.rotation_euler = (Vector((0, 0, CAM_Z)) - cam.location).to_track_quat("-Z", "Y").to_euler()

saved = (sc.camera, sc.render.engine, sc.render.resolution_x, sc.render.resolution_y,
         sc.render.film_transparent, sc.render.filepath, rig.hide_render)
try:
    sc.render.engine = "BLENDER_WORKBENCH"
except TypeError as e:
    print("engine:", e)
sh = sc.display.shading
sh.light, sh.color_type = "STUDIO", "MATERIAL"
sc.render.resolution_x, sc.render.resolution_y = 600, 800
sc.render.film_transparent = False
sc.world.color = (0.035, 0.038, 0.045)
sc.render.image_settings.file_format = "PNG"
sc.camera = cam
rig.hide_render = True  # draw the body part meshes, not the bones
os.makedirs(os.path.dirname(OUT), exist_ok=True)
sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)

(sc.camera, sc.render.engine, sc.render.resolution_x, sc.render.resolution_y,
 sc.render.film_transparent, sc.render.filepath, rig.hide_render) = saved
for ob in temp:
    data = ob.data
    bpy.data.objects.remove(ob, do_unlink=True)
    if isinstance(data, bpy.types.Mesh):
        bpy.data.meshes.remove(data)
    elif isinstance(data, bpy.types.Camera):
        bpy.data.cameras.remove(data)
for m in mats:
    bpy.data.materials.remove(m)
print("saved", OUT, "| floor row", round(400 + CAM_Z * 800 / ORTHO))

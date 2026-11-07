"""Spin for Abilities - Thunder Lance stage 3: the right hand's Blender Motion Path, F8-F24.

Run inside Blender after build_thunder_lance_anim.py (STAGE = "spline"):
    exec(open(r"<this file>").read())
Turns on Motion Paths for the RightWrist bone (its tail = the hand's end), frames 8-24, then copies
the path's points (bone.motion_path.points, Blender's own path data) into a temporary tube so it
shows in a render, with a dot on every whole frame (bigger + labelled at 12, 15, 18, 24).
Renders previews/thunder_lance/motion_path_{side,top,34}.png at frame 15 (the release), body in X-ray. The Motion
Path stays on the rig in the .blend; the tube, dots, camera and materials are removed again.
"""
import bpy, os
from mathutils import Vector

OUT_DIR = r"C:\Roblox\Spin for ability\Game\assets\vfx\previews\thunder_lance"
RIG_NAME, BONE = "ThunderLanceRig", "RightWrist"
START, END, SHOW_FRAME = 8, 24, 15
VIEWS = {"side": (Vector((17, 0.4, 3.8)), Vector((0, 0.4, 3.2)), 9.0),
         "top": (Vector((0.5, 0.4, 22)), Vector((0.5, 0.4, 0)), 9.0),
         "34": (Vector((12.5, 9.5, 7.5)), Vector((0.3, 0.3, 3.2)), 9.0)}

sc = bpy.context.scene
rig = bpy.data.objects[RIG_NAME]
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="POSE")
for pb in rig.pose.bones:  # Blender 5: selection lives on the pose bone
    pb.select = pb.name == BONE
rig.data.bones.active = rig.data.bones[BONE]
viz = rig.pose.animation_visualization.motion_path
viz.type = "RANGE"
viz.frame_start, viz.frame_end = START, END
viz.bake_location = "TAILS"
bpy.ops.pose.paths_calculate(display_type="RANGE", range="SCENE", bake_location="TAILS")
bpy.ops.pose.paths_update()
mp = rig.pose.bones[BONE].motion_path
pts = [rig.matrix_world @ Vector(p.co) for p in mp.points]
first = mp.frame_start
bpy.ops.object.mode_set(mode="OBJECT")
print(f"motion path: {len(pts)} points, frames {first}-{first + len(pts) - 1}")
keep = [(first + i, p) for i, p in enumerate(pts) if START <= first + i <= END]

temp, mats = [], []


def mat(name, rgb, emit=0.0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    mats.append(m)
    return m


cu = bpy.data.curves.new("_tl_path", "CURVE")
cu.dimensions, cu.bevel_depth = "3D", 0.035
sp = cu.splines.new("POLY")
sp.points.add(len(keep) - 1)
for sp_pt, (_, p) in zip(sp.points, keep):
    sp_pt.co = (*p, 1)
path_ob = bpy.data.objects.new("_tl_path", cu)
path_ob.data.materials.append(mat("_tl_path", (1.0, 0.85, 0.2)))
sc.collection.objects.link(path_ob)
temp.append(path_ob)
dot_mat = mat("_tl_dot", (1.0, 1.0, 1.0))
key_mat = mat("_tl_key", (0.35, 0.8, 1.0))
for f, p in keep:
    big = f in (12, 15, 18, 24)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.11 if big else 0.06, location=p, segments=12, ring_count=8)
    ob = bpy.context.active_object
    ob.name = f"_tl_dot_{f}"
    ob.data.materials.append(key_mat if big else dot_mat)
    temp.append(ob)
    if big:
        txt = bpy.data.curves.new(f"_tl_lbl_{f}", "FONT")
        txt.body, txt.size = f"F{f}", 0.32
        tob = bpy.data.objects.new(f"_tl_lbl_{f}", txt)
        tob.location = p + Vector((0.12, 0, 0.16))
        tob.data.materials.append(key_mat)
        sc.collection.objects.link(tob)
        temp.append(tob)

cam_data = bpy.data.cameras.new("_tl_cam")
cam_data.type = "ORTHO"
cam = bpy.data.objects.new("_tl_cam", cam_data)
sc.collection.objects.link(cam)
temp.append(cam)
saved = (sc.camera, sc.render.engine, sc.render.resolution_x, sc.render.resolution_y, sc.render.filepath,
         sc.frame_current, rig.hide_render)
try:
    sc.render.engine = "BLENDER_WORKBENCH"
except TypeError as e:
    print("engine:", e)
sh = sc.display.shading
sh.light, sh.color_type = "STUDIO", "MATERIAL"
xray = (sh.show_xray, sh.xray_alpha)
sh.show_xray, sh.xray_alpha = True, 0.3  # see-through body, so the path behind the arm shows
sc.render.resolution_x, sc.render.resolution_y = 700, 700
sc.world.color = (0.035, 0.038, 0.045)
sc.camera = cam
rig.hide_render = True
spear = bpy.data.objects.get("TL_SpearStandIn")
spear_action = spear.animation_data.action if spear and spear.animation_data else None
if spear_action:  # the spear would hide the path (the poses sheet shows it); its keys set visibility
    spear.animation_data.action = None
if spear:
    spear.hide_render = True
sc.frame_set(SHOW_FRAME)
os.makedirs(OUT_DIR, exist_ok=True)
for view, (eye, look, scale) in VIEWS.items():
    cam.location = eye
    up = "Y" if view != "top" else "Y"
    cam.rotation_euler = (look - eye).to_track_quat("-Z", "Y").to_euler()
    cam_data.ortho_scale = scale
    for ob in temp:
        if ob.name.startswith("_tl_lbl_"):  # labels face the camera
            ob.rotation_euler = cam.rotation_euler
    sc.render.filepath = os.path.join(OUT_DIR, f"motion_path_{view}.png")
    bpy.ops.render.render(write_still=True)
    print("saved", sc.render.filepath)

(sc.camera, sc.render.engine, sc.render.resolution_x, sc.render.resolution_y, sc.render.filepath,
 _, rig.hide_render) = saved
sh.show_xray, sh.xray_alpha = xray
if spear_action:
    spear.animation_data.action = spear_action
sc.frame_set(saved[5])
datas = [ob.data for ob in temp]
for ob in temp:
    bpy.data.objects.remove(ob, do_unlink=True)
for data in datas:  # meshes, curves (path + labels), camera: free once nothing uses them
    for coll in (bpy.data.meshes, bpy.data.curves, bpy.data.cameras):
        if data in list(coll) and data.users == 0:
            coll.remove(data)
            break
for m in mats:
    bpy.data.materials.remove(m)
bpy.ops.wm.save_mainfile()
print("motion path kept on", BONE, "| .blend saved")

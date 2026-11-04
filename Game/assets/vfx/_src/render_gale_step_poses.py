"""Spin for Abilities - Gale Step: render pose check frames (Workbench) for the stage previews.

Run inside Blender after build_gale_step_anim.py:
    FRAMES = [0, 4, 12, 17]; exec(open(r"<this file>").read())      (FRAMES optional)
Writes Game/assets/vfx/previews/gale_step/pose_<view>_<frame>.png (600x800) from two cameras:
    side  - from the rig's right (+X), forward reads to the right
    34    - 3/4 front, from front-right and slightly above, forward still reads to the right
The floor, cameras and light are temporary and removed again; the .blend is not saved.
"""
import bpy, math, os
from mathutils import Vector

OUT_DIR = r"C:\Roblox\Spin for ability\Game\assets\vfx\previews\gale_step"
VIEWS = {"side": (Vector((15.5, 0.2, 3.6)), Vector((0, 0.2, 2.4))),
         "34": (Vector((10.4, 10.4, 5.0)), Vector((0, 0.2, 2.3)))}
frames = globals().get("FRAMES") or [0, 4, 6, 12, 17, 22, 36]


def render_poses():
    sc = bpy.context.scene
    os.makedirs(OUT_DIR, exist_ok=True)
    temp = []
    bpy.ops.mesh.primitive_plane_add(size=400, location=(0, 0, 0))
    floor = bpy.context.active_object
    floor.name = "_preview_floor"
    mat = bpy.data.materials.new("_preview_floor")
    mat.diffuse_color = (0.08, 0.085, 0.1, 1)
    floor.data.materials.append(mat)
    temp.append(floor)
    cam_data = bpy.data.cameras.new("_preview_cam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("_preview_cam", cam_data)
    sc.collection.objects.link(cam)
    temp.append(cam)

    saved = (sc.camera, sc.render.engine, sc.render.resolution_x, sc.render.resolution_y,
             sc.render.film_transparent, sc.frame_current)
    try:
        sc.render.engine = "BLENDER_WORKBENCH"
    except TypeError as e:
        print("engine:", e)
    sh = sc.display.shading
    sh.light, sh.color_type = "STUDIO", "MATERIAL"
    sh.show_shadows, sh.show_cavity = True, True
    sc.display.shadow_shift = 0.1
    sc.render.resolution_x, sc.render.resolution_y = 600, 800
    sc.render.film_transparent = False
    sc.world.color = (0.035, 0.038, 0.045)
    sc.render.image_settings.file_format = "PNG"
    sc.camera = cam
    rig = bpy.data.objects["GaleStepRig"]
    rig_hidden = rig.hide_render
    rig.hide_render = True  # bones never render, but keep the armature out of the way anyway

    paths = []
    for view, (eye, look_at) in VIEWS.items():
        cam.location = eye
        cam.rotation_euler = (look_at - eye).to_track_quat("-Z", "Y").to_euler()
        for f in frames:
            sc.frame_set(f)
            sc.render.filepath = os.path.join(OUT_DIR, f"pose_{view}_{f:02d}.png")
            bpy.ops.render.render(write_still=True)
            paths.append(sc.render.filepath)

    rig.hide_render = rig_hidden
    (sc.camera, sc.render.engine, sc.render.resolution_x, sc.render.resolution_y,
     sc.render.film_transparent, _) = saved
    sc.frame_set(saved[5])
    for ob in temp:
        data = ob.data
        bpy.data.objects.remove(ob, do_unlink=True)
        if isinstance(data, bpy.types.Mesh):
            bpy.data.meshes.remove(data)
        elif isinstance(data, bpy.types.Camera):
            bpy.data.cameras.remove(data)
    bpy.data.materials.remove(mat)
    return paths


print("\n".join(render_poses()))

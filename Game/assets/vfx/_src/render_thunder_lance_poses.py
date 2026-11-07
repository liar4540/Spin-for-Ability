"""Spin for Abilities - Thunder Lance: render pose check frames (Workbench) for the stage previews.

Run inside Blender after build_thunder_lance_anim.py:
    FRAMES = [0, 12, 15]; exec(open(r"<this file>").read())      (FRAMES optional)
Writes Game/assets/vfx/previews/thunder_lance/pose_<view>_<frame>.png (600x800) from two cameras:
    side  - from the rig's right (+X), forward reads to the right (like the reference sheet)
    34    - 3/4 front, from front-right and slightly above, forward still reads to the right
The yellow stand-in spear (TL_SpearStandIn) renders on the frames it is shown.
The floor, dummy, camera and light are temporary and removed again; the .blend is not saved.
"""
import bpy, math, os
from mathutils import Vector

OUT_DIR = r"C:\Roblox\Spin for ability\Game\assets\vfx\previews\thunder_lance"
RIG_NAME = "ThunderLanceRig"
DUMMY_Y = 40  # the Training Dummy, 40 studs ahead (blueprint panel 3); out of frame, kept for the floor shadow
VIEWS = {"side": (Vector((17.0, -0.3, 3.6)), Vector((0, -0.3, 2.6))),
         "34": (Vector((13.5, 9.5, 5.4)), Vector((0, -0.2, 2.6)))}  # 3/4 front, from front-right
frames = globals().get("FRAMES") or [0, 4, 8, 12, 13, 14, 15, 18, 24, 30]

# Training Dummy stand-in: (centre, size) in Blender axes, relative to its own root on the floor
DUMMY_PARTS = [((0, 0, 4.98), (1.16, 1.16, 1.18)), ((0, 0, 3.44), (1.94, 1.0, 2.1)),
               ((-1.47, 0, 3.0), (1.0, 1.0, 2.67)), ((1.47, 0, 3.0), (1.0, 1.0, 2.67)),
               ((-0.5, 0, 1.08), (0.99, 0.97, 2.15)), ((0.5, 0, 1.08), (0.99, 0.97, 2.15))]


def render_poses():
    sc = bpy.context.scene
    os.makedirs(OUT_DIR, exist_ok=True)
    temp, mats = [], []

    def material(name, rgb):
        mat = bpy.data.materials.new(name)
        mat.diffuse_color = (*rgb, 1)
        mats.append(mat)
        return mat

    bpy.ops.mesh.primitive_plane_add(size=400, location=(0, 0, 0))
    floor = bpy.context.active_object
    floor.name = "_preview_floor"
    floor.data.materials.append(material("_preview_floor", (0.08, 0.085, 0.1)))
    temp.append(floor)
    grey = material("_preview_dummy", (0.45, 0.46, 0.5))
    for i, (c, s) in enumerate(DUMMY_PARTS):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(c[0], c[1] + DUMMY_Y, c[2]))
        ob = bpy.context.active_object
        ob.name = f"_preview_dummy{i}"
        ob.scale = s
        ob.data.materials.append(grey)
        temp.append(ob)
    cam_data = bpy.data.cameras.new("_preview_cam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("_preview_cam", cam_data)
    sc.collection.objects.link(cam)
    temp.append(cam)

    saved = (sc.camera, sc.render.engine, sc.render.resolution_x, sc.render.resolution_y,
             sc.render.film_transparent, sc.frame_current, sc.render.filepath)
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
    rig = bpy.data.objects[RIG_NAME]
    rig_hidden = rig.hide_render
    rig.hide_render = True

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
     sc.render.film_transparent, _, sc.render.filepath) = saved
    sc.frame_set(saved[5])
    for ob in temp:
        data = ob.data
        bpy.data.objects.remove(ob, do_unlink=True)
        if isinstance(data, bpy.types.Mesh):
            bpy.data.meshes.remove(data)
        elif isinstance(data, bpy.types.Camera):
            bpy.data.cameras.remove(data)
    for mat in mats:
        bpy.data.materials.remove(mat)
    return paths


print("\n".join(render_poses()))

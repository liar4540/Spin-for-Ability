"""Combat animations, stage 2: quality check + previews (Blender 5.2, headless).

    blender.exe -b ..\\combat_anims.blend -P preview_qc_combat_anims.py -- [--video] [M1_1 ...]
Opens combat_anims.blend (never saves it). For every action:
  * QC: first/last pose == guard, HumanoidRootPart static, no bone scale, foot drift, hit-frame reach,
    hands inside the torso box (arm through body), elbow hinge sanity, max per-frame rotation (snaps).
  * renders a strip of the key moments (front 3/4 + side) to animations/previews/<name>_strip.png
  * --video: real-speed and 4x slow-motion mp4 to animations/previews/.
"""
import bpy, math, os, sys
import numpy as np
from mathutils import Vector, Matrix

ROOT = r"C:\NYP\Roblox\Spin For Abilities\Game\assets\animations"
OUT = os.path.join(ROOT, "previews")
os.makedirs(OUT, exist_ok=True)
FPS = 30
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
VIDEO = "--video" in args
ONLY = [a for a in args if not a.startswith("--")]

scene = bpy.context.scene
rig = bpy.data.objects["R15_Combat"]
PUNCH_HAND = {"M1_1": "RightHand", "M1_2": "LeftHand", "M1_3": "RightHand", "M1_4": "LeftHand",
              "Uppercut": "RightHand", "Downslam": "RightHand"}


def set_time(t):
    f = math.floor(t)
    scene.frame_set(f, subframe=t - f)


def part_ob(name):
    return bpy.data.objects[name]


def part_center(name):
    return part_ob(name).matrix_world.translation.copy()


def assign(act):
    rig.animation_data.action = act
    if act.slots:
        rig.animation_data.action_slot = act.slots[0]


# --- QC ---------------------------------------------------------------------------------------------
def inside_box(ob, p, shrink=0.0):
    """Is world point p inside the (bone-parented, unrotated mesh) box of object ob?"""
    local = ob.matrix_world.inverted() @ p
    half = Vector(ob.dimensions) / 2 - Vector((shrink, shrink, shrink))
    return all(abs(local[i]) < half[i] for i in range(3))


def qc(act):
    assign(act)
    end = act.frame_end
    hit = act["hit_frame_exact"]
    times = [i * 0.25 for i in range(int(end * 4) + 1)]
    if times[-1] != end:
        times.append(end)
    lines = []

    # guard reference = frame 0 of this action, compare the last frame against it
    def pose_snapshot():
        return {pb.name: pb.matrix_basis.copy() for pb in rig.pose.bones}
    set_time(0)
    first = pose_snapshot()
    set_time(end)
    last = pose_snapshot()
    worst = max(max(abs(x) for row in (first[n] - last[n]) for x in row) for n in first)
    lines.append(f"start==end pose: max matrix diff {worst:.4f} {'OK' if worst < 1e-3 else 'MISMATCH'}")

    # hit frame equals M1_1 frame 0 guard? (each move must start from the shared guard)
    guard_act = bpy.data.actions["M1_1"]
    assign(guard_act)
    set_time(0)
    guard = pose_snapshot()
    assign(act)
    gd = max(max(abs(x) for row in (guard[n] - first[n]) for x in row) for n in first)
    lines.append(f"starts on shared guard: diff {gd:.4f} {'OK' if gd < 1e-3 else 'MISMATCH'}")

    # scale / HRP / foot drift / snaps / clipping / elbows
    from bpy_extras import anim_utils
    cb = anim_utils.action_get_channelbag_for_slot(act, act.slots[0])
    paths = {fc.data_path for fc in cb.fcurves}
    lines.append(f"scale channels: {sum('scale' in p for p in paths)}  HumanoidRootPart channels: "
                 f"{sum('HumanoidRootPart' in p for p in paths)}")
    feet0 = None
    max_slide = {"Left": 0.0, "Right": 0.0}
    prev_q, max_step = {}, (0.0, "", 0)
    clip = []
    elbow_bad = []
    for t in times:
        set_time(t)
        # toe tip (front-bottom-centre of the foot box) must not move: heel may roll, toe stays
        toes = {}
        for side in ("Left", "Right"):
            ob = part_ob(f"{side}Foot")
            h = Vector(ob.dimensions) / 2
            toes[side] = ob.matrix_world @ Vector((0, h.y, -h.z))
        if feet0 is None:
            feet0 = toes
        for s in toes:
            max_slide[s] = max(max_slide[s], (toes[s] - feet0[s]).length)
        if t == int(t):
            for pb in rig.pose.bones:
                q = pb.rotation_quaternion.copy()
                if pb.name in prev_q:
                    ang = math.degrees(q.rotation_difference(prev_q[pb.name]).angle)
                    if ang > max_step[0]:
                        max_step = (ang, pb.name, t)
                prev_q[pb.name] = q
        for hand in ("LeftHand", "RightHand", "LeftLowerArm", "RightLowerArm"):
            if inside_box(part_ob("UpperTorso"), part_center(hand), shrink=0.05) or \
               inside_box(part_ob("Head"), part_center(hand), shrink=0.05):
                clip.append(f"{hand}@{t:g}")
        for side in ("Left", "Right"):
            e = rig.pose.bones[f"{side}Elbow"]
            rest = e.bone.matrix_local.to_3x3()
            D = rest @ e.rotation_quaternion.to_matrix() @ rest.inverted()
            # hinge: D should be a pure rotation about X with a positive (flexion) angle
            axis_err = max(abs(D[0][1]), abs(D[0][2]), abs(D[1][0]), abs(D[2][0]))
            ang = math.degrees(math.atan2(D[2][1], D[1][1]))
            if axis_err > 0.02 or ang < -2 or ang > 150:
                elbow_bad.append(f"{side}@{t:g}:{ang:.0f}deg")
    lines.append(f"toe slide: L {max_slide['Left']:.3f}  R {max_slide['Right']:.3f} studs "
                 f"{'OK' if max(max_slide.values()) < 0.02 else 'SLIDING'}")
    lines.append(f"largest 1-frame joint rotation: {max_step[0]:.0f} deg ({max_step[1]} into frame {max_step[2]:g})")
    lines.append(f"arm/hand inside torso or head: {', '.join(clip) if clip else 'none'}")
    lines.append(f"elbow hinge problems: {', '.join(elbow_bad) if elbow_bad else 'none'}")

    # hit reach
    hand = PUNCH_HAND.get(act.name)
    if hand:
        set_time(0)
        p0 = part_center(hand)
        set_time(hit)
        ph = part_center(hand)
        head = part_center("Head")
        best_t, best_y = 0, -9
        for t in times:
            set_time(t)
            y = part_center(hand).y
            if y > best_y:
                best_t, best_y = t, y
        lines.append(f"{hand} at hit ({hit:g}): fwd {ph.y:+.2f} (guard {p0.y:+.2f}), x {ph.x:+.2f}, "
                     f"z {ph.z:.2f} (head z {head.z:.2f}); furthest fwd {best_y:+.2f} at frame {best_t:g}")
    return lines


# --- rendering ---------------------------------------------------------------------------------------
def setup_render():
    scene.render.engine = "BLENDER_WORKBENCH"
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "MATERIAL"
    sh.show_shadows = True
    sh.show_cavity = False
    scene.render.resolution_x = scene.render.resolution_y = 420
    scene.render.film_transparent = False
    world = scene.world or bpy.data.worlds.new("W")
    scene.world = world
    if "Floor" not in bpy.data.objects:
        bpy.ops.mesh.primitive_plane_add(size=14, location=(0, 0, 0))
        fl = bpy.context.active_object
        fl.name = "Floor"
        m = bpy.data.materials.new("FloorMat")
        m.diffuse_color = (0.35, 0.37, 0.42, 1)
        fl.data.materials.append(m)
        # target marker: a thin post 3.5 studs ahead (hitbox offset)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=5, location=(0, 3.5, 2.5))
        post = bpy.context.active_object
        post.name = "TargetPost"
        pm = bpy.data.materials.new("PostMat")
        pm.diffuse_color = (0.8, 0.25, 0.2, 1)
        post.data.materials.append(pm)
    tgt = bpy.data.objects.get("CamTarget") or bpy.data.objects.new("CamTarget", None)
    if tgt.name not in scene.collection.objects:
        scene.collection.objects.link(tgt)
    tgt.location = (0, 0.7, 2.7)
    cams = {}
    for name, loc in (("Cam34", (5.2, 6.8, 3.9)), ("CamSide", (9.0, 0.9, 3.0)), ("CamTop", (0.01, 0.8, 11))):
        cd = bpy.data.cameras.new(name)
        cd.lens = 45
        cam = bpy.data.objects.new(name, cd)
        scene.collection.objects.link(cam)
        cam.location = loc
        c = cam.constraints.new("TRACK_TO")
        c.target = tgt
        c.track_axis, c.up_axis = "TRACK_NEGATIVE_Z", "UP_Y"
        cams[name] = cam
    return cams


def render_png(path):
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def load_px(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(img)
    return a


def save_px(a, path):
    h, w = a.shape[:2]
    img = bpy.data.images.new("strip", w, h, alpha=True)
    img.pixels[:] = a.ravel()
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def strip(act, cams):
    assign(act)
    keys = sorted({0.0, act["hit_frame_exact"], act.frame_end} |
                  {kp.co.x for fc in __import__("bpy_extras").anim_utils.action_get_channelbag_for_slot(
                      act, act.slots[0]).fcurves if "RightShoulder" in fc.data_path for kp in fc.keyframe_points})
    rows = []
    tmp = os.path.join(OUT, "_tmp.png")
    for cam_name in ("Cam34", "CamSide", "CamTop"):
        scene.camera = cams[cam_name]
        row = []
        for t in keys:
            set_time(t)
            render_png(tmp)
            px = load_px(tmp)
            if abs(t - act["hit_frame_exact"]) < 1e-6:  # red bar under the hit frame
                px[:8, :, :] = (0.9, 0.1, 0.1, 1)
            row.append(px)
        rows.append(np.concatenate(row, axis=1))
    os.remove(tmp)
    sheet = np.concatenate(rows[::-1], axis=0)  # images are bottom-up
    path = os.path.join(OUT, f"{act.name}_strip.png")
    save_px(sheet, path)
    print(f"  strip frames {', '.join(f'{k:g}' for k in keys)} -> {path}")


def video(act, cams, slow):
    assign(act)
    scene.camera = cams["Cam34"]
    r = scene.render
    r.resolution_x = r.resolution_y = 480
    r.image_settings.media_type = "VIDEO"
    r.image_settings.file_format = "FFMPEG"
    r.ffmpeg.format = "MPEG4"
    r.ffmpeg.codec = "H264"
    r.ffmpeg.constant_rate_factor = "HIGH"
    r.fps = FPS
    # slow motion: Blender time remap (old 1 -> new 4 frames)
    r.frame_map_old, r.frame_map_new = (1, 4) if slow else (1, 1)
    end = math.ceil(act.frame_end)
    scene.frame_start, scene.frame_end = 0, end * (4 if slow else 1)
    r.filepath = os.path.join(OUT, f"{act.name}{'_slow4x' if slow else ''}.mp4")
    bpy.ops.render.render(animation=True)
    r.frame_map_old = r.frame_map_new = 1
    r.image_settings.media_type = "IMAGE"
    r.resolution_x = r.resolution_y = 420
    print("  video", r.filepath)


cams = setup_render()
for act in sorted(bpy.data.actions, key=lambda a: a.name):
    if ONLY and act.name not in ONLY:
        continue
    if "hit_frame_exact" not in act:
        continue
    print(f"=== {act.name}: {act.frame_end / FPS:.2f}s ({act.frame_end:g} frames), hit {act['hit_time']:.2f}s "
          f"(frame {act['hit_frame_exact']:g}, marker {act.pose_markers['Hit'].frame})")
    for line in qc(act):
        print("  " + line)
    strip(act, cams)
    if VIDEO:
        video(act, cams, slow=False)
        video(act, cams, slow=True)

"""Combat animations, stage 3: export (Blender 5.2, headless). Never saves combat_anims.blend.

    blender.exe -b ..\\combat_anims.blend -P export_combat_anims.py
Writes, for every action with a "hit_time":
  1. Game/src/client/Animations/CombatKeyframes.luau - keyframes in the client/Abilities/Pose.luau
     format (one per frame @ 30 fps + one at the EXACT hit time carrying the "Hit" KeyframeMarker +
     one at the exact end time). Pose.Build(name, CombatKeyframes.M1_1.Keyframes) makes the
     KeyframeSequence to upload. Data only - nothing requires it yet.
  2. Game/assets/animations/fbx/<name>.fbx - armature only, bones renamed to the R15 PART names
     (LowerTorso, UpperTorso, ...; the names Roblox's FBX animation import matches) on a temporary
     copy of the rig, baked at 60 fps so 0.45 s = 27 frames lands exactly. Markers can't go in FBX.
Conversion to Roblox (same as export_pebble_toss_anim.py):
    Transform_roblox = M^T * (R_rest * basis * R_rest^-1) * M,  t_roblox = M^T * R_rest * location
"""
import bpy, math, os
from mathutils import Matrix
from bpy_extras import anim_utils

GAME = r"C:\NYP\Roblox\Spin For Abilities\Game"
LUAU = os.path.join(GAME, r"src\client\Animations\CombatKeyframes.luau")
FBX_DIR = os.path.join(GAME, r"assets\animations\fbx")
FPS = 30
JOINTS = ["Root", "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder",
          "LeftElbow", "LeftWrist", "RightHip", "RightKnee", "RightAnkle", "LeftHip", "LeftKnee", "LeftAnkle"]
M = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
scene = bpy.context.scene
rig = bpy.data.objects["R15_Combat"]
ACTIONS = sorted((a for a in bpy.data.actions if "hit_time" in a), key=lambda a: a.name)


def assign(ob, act):
    ob.animation_data.action = act
    ob.animation_data.action_slot = act.slots[0]


def set_time(t):
    f = math.floor(t)
    scene.frame_set(f, subframe=t - f)


def euler_xyz(R):
    b = math.asin(max(-1.0, min(1.0, R[0][2])))
    a = math.atan2(-R[1][2], R[2][2])
    c = math.atan2(-R[0][1], R[0][0])
    return tuple(math.degrees(v) for v in (a, b, c))


def rebuild(a, b, c):
    rx, ry, rz = (math.radians(v) for v in (a, b, c))
    return Matrix.Rotation(rx, 3, "X") @ Matrix.Rotation(ry, 3, "Y") @ Matrix.Rotation(rz, 3, "Z")


def fmt(v):
    return ", ".join(f"{x:.3f}".rstrip("0").rstrip(".") if abs(x) >= 5e-4 else "0" for x in v)


def export_luau():
    worst = 0.0
    blocks = []
    for act in ACTIONS:
        assign(rig, act)
        end, hit = act.frame_end, act["hit_frame_exact"]
        times = sorted(set(float(f) for f in range(0, math.floor(end) + 1)) | {hit, end})
        frames = []
        for t in times:
            set_time(t)
            poses = []
            for name in JOINTS:
                pb = rig.pose.bones[name]
                rest = pb.bone.matrix_local.to_3x3()
                D = rest @ pb.rotation_quaternion.normalized().to_matrix() @ rest.inverted()
                R = M.transposed() @ D @ M
                rot = euler_xyz(R)
                worst = max(worst, max(abs(x) for row in (rebuild(*rot) - R) for x in row))
                entry = f"Rot = Vector3.new({fmt(rot)})"
                if name == "Root":
                    entry += f", Pos = Vector3.new({fmt(M.transposed() @ (rest @ pb.location))})"
                poses.append(f"\t\t\t\t{name} = {{ {entry} }},")
            is_hit = abs(t - hit) < 1e-6
            note = f"frame {t:g}" + ("  HIT" if is_hit else "")
            markers = ' Markers = { "Hit" },' if is_hit else ""
            frames.append(f"\t\t\t{{ -- {note}\n\t\t\t\tTime = {t / FPS:.4f},{markers}\n"
                          f"\t\t\t\tStyle = Enum.EasingStyle.Linear,\n\t\t\t\tPose = {{\n"
                          + "\n".join(p.replace("\t\t\t\t", "\t\t\t\t\t", 1) for p in poses)
                          + "\n\t\t\t\t},\n\t\t\t},")
        blocks.append(f"\t{act.name} = {{\n\t\tLength = {act['length_seconds']:.2f},\n"
                      f"\t\tHitTime = {act['hit_time']:.2f},\n\t\tKeyframes = {{\n"
                      + "\n".join(frames) + "\n\t\t},\n\t},")
    names = ", ".join(a.name for a in ACTIONS)
    src = (
        "--!strict\n"
        "-- GENERATED - do not edit by hand. TSB-style combat animations (R15), one keyframe per frame @ 30 fps\n"
        "-- plus one at the exact hit time (KeyframeMarker \"Hit\") and one at the exact end.\n"
        "-- Source: Game/assets/animations/combat_anims.blend, made by assets/animations/_src/build_combat_anims.py\n"
        "-- and exported by export_combat_anims.py (change the poses there and rerun both).\n"
        f"-- Moves: {names}.\n"
        "-- Use: Pose.Build(name, CombatKeyframes[name].Keyframes) -> KeyframeSequence -> Save to Roblox,\n"
        "-- or Pose.Track(character, name, CombatKeyframes[name].Keyframes, animationId) in Studio.\n\n"
        "local Pose = require(script.Parent.Parent.Abilities.Pose)\n\n"
        "export type Move = { Length: number, HitTime: number, Keyframes: { Pose.Keyframe } }\n\n"
        "local MOVES: { [string]: Move } = {\n" + "\n".join(blocks) + "\n}\n\nreturn MOVES\n"
    )
    os.makedirs(os.path.dirname(LUAU), exist_ok=True)
    with open(LUAU, "w", newline="\n", encoding="utf-8") as fh:
        fh.write(src)
    print(f"wrote {LUAU}: {len(ACTIONS)} moves, worst Euler round-trip error {worst:.2e}")


def export_fbx():
    os.makedirs(FBX_DIR, exist_ok=True)
    # temporary part-named copy of the rig (the saved rig keeps its joint-named bones)
    data = rig.data.copy()
    exp = rig.copy()
    exp.data = data
    exp.name = "R15_Export"
    scene.collection.objects.link(exp)
    rename = {b.name: b["part1"] for b in data.bones if "part1" in b}
    bpy.context.view_layer.objects.active = exp
    for old, new in rename.items():
        data.bones[old].name = new
    exp.animation_data_create()
    fps0, fs0, fe0 = scene.render.fps, scene.frame_start, scene.frame_end
    scene.render.fps = 60
    for act in ACTIONS:
        dup = act.copy()
        dup.name = act.name + "_fbx60"
        cb = anim_utils.action_get_channelbag_for_slot(dup, dup.slots[0])
        for fc in cb.fcurves:
            for old, new in rename.items():
                fc.data_path = fc.data_path.replace(f'pose.bones["{old}"]', f'pose.bones["{new}"]')
            for kp in fc.keyframe_points:
                kp.co.x *= 2
                kp.handle_left.x *= 2
                kp.handle_right.x *= 2
            fc.update()
        for grp in cb.groups:
            grp.name = rename.get(grp.name, grp.name)
        assign(exp, dup)
        end60 = round(act.frame_end * 2)
        scene.frame_start, scene.frame_end = 0, end60
        dup.frame_start, dup.frame_end = 0, end60
        for ob in bpy.context.view_layer.objects:
            ob.select_set(ob == exp)
        path = os.path.join(FBX_DIR, f"{act.name}.fbx")
        bpy.ops.export_scene.fbx(
            filepath=path, use_selection=True, object_types={"ARMATURE"},
            add_leaf_bones=False, primary_bone_axis="Y", secondary_bone_axis="X",
            axis_forward="Z", axis_up="Y",  # rig faces Blender +Y -> FBX -Z (Roblox forward), Y up
            apply_scale_options="FBX_SCALE_ALL", global_scale=1.0,
            bake_anim=True, bake_anim_use_all_bones=True, bake_anim_use_nla_strips=False,
            bake_anim_use_all_actions=False, bake_anim_force_startend_keying=True,
            bake_anim_step=1.0, bake_anim_simplify_factor=0.0)
        print(f"wrote {path}: {end60 + 1} frames @ 60 fps = {end60 / 60:.2f}s (hit at 60fps frame {act['hit_time'] * 60:g})")
        bpy.data.actions.remove(dup)
    scene.render.fps, scene.frame_start, scene.frame_end = fps0, fs0, fe0
    bpy.data.objects.remove(exp)
    bpy.data.armatures.remove(data)


export_luau()
export_fbx()

"""Spin for Abilities - Pebble Toss, stage 5: Blender throw -> Roblox keyframes (Luau).

Run inside Blender after build_pebble_toss_throw.py:
    exec(open(r"<this file>").read())
Writes Game/src/client/Abilities/PebbleTossKeyframes.luau (Rojo syncs it into Studio), in the format
client/Abilities/Pose.luau builds into a KeyframeSequence: one keyframe per frame (0-30 @ 30 fps),
Linear between them, a "Release" marker on frame 12.

Conversion (see build_pebble_toss_throw.py): each joint's delta D (parent frame, rest-aligned axes)
    D_blender = R_rest * basis * R_rest^-1          translation t = R_rest * location (Root only)
    Roblox (x, y, z) -> Blender (x, -z, y) is the matrix M below, so
    Transform_roblox = M^T * D_blender * M,         t_roblox = M^T * t
which is the joint's Motor6D.Transform / Pose.CFrame (all R15 rest rotations are identity, and C0
sits on the joint). Rot is written as degrees for CFrame.Angles (R = Rx * Ry * Rz).
"""
import bpy, math
from mathutils import Matrix, Vector

OUT = r"C:\Roblox\Spin for ability\Game\src\client\Abilities\PebbleTossKeyframes.luau"
FPS, FIRST, LAST, RELEASE = 30, 0, 30, 12
JOINTS = ["Root", "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder",
          "LeftElbow", "LeftWrist", "RightHip", "RightKnee", "RightAnkle", "LeftHip", "LeftKnee", "LeftAnkle"]
M = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))


def euler_xyz(R):
    """Angles (a, b, c) in degrees with R = Rx(a) * Ry(b) * Rz(c) (Roblox CFrame.Angles)."""
    b = math.asin(max(-1.0, min(1.0, R[0][2])))
    a = math.atan2(-R[1][2], R[2][2])
    c = math.atan2(-R[0][1], R[0][0])
    return tuple(math.degrees(v) for v in (a, b, c))


def rebuild(a, b, c):
    rx, ry, rz = (math.radians(v) for v in (a, b, c))
    return Matrix.Rotation(rx, 3, "X") @ Matrix.Rotation(ry, 3, "Y") @ Matrix.Rotation(rz, 3, "Z")


def fmt(v):
    return ", ".join(f"{x:.3f}".rstrip("0").rstrip(".").replace("-0", "-0") if abs(x) >= 5e-4 else "0" for x in v)


def export():
    scene = bpy.context.scene
    rig = bpy.data.objects["PebbleTossRig"]
    worst = 0.0
    lines = []
    for frame in range(FIRST, LAST + 1):
        scene.frame_set(frame)
        poses = []
        for name in JOINTS:
            pb = rig.pose.bones[name]
            rest = pb.bone.matrix_local.to_3x3()
            D = rest @ pb.rotation_quaternion.to_matrix() @ rest.inverted()
            R = M.transposed() @ D @ M
            rot = euler_xyz(R)
            err = max(abs(x) for row in (rebuild(*rot) - R) for x in row)
            worst = max(worst, err)
            entry = f"Rot = Vector3.new({fmt(rot)})"
            if name == "Root":
                t = M.transposed() @ (rest @ pb.location)
                entry += f", Pos = Vector3.new({fmt(t)})"
            poses.append(f"\t\t\t{name} = {{ {entry} }},")
        markers = ' Markers = { "Release" },' if frame == RELEASE else ""
        lines.append(f"\t{{ -- frame {frame}{'  RELEASE' if frame == RELEASE else ''}\n"
                     f"\t\tTime = {frame / FPS:.4f},{markers}\n"
                     f"\t\tStyle = Enum.EasingStyle.Linear,\n"
                     f"\t\tPose = {{\n" + "\n".join(poses) + "\n\t\t},\n\t},")
    src = (
        "--!strict\n"
        "-- GENERATED - do not edit by hand. Pebble Toss throw, one keyframe per frame (0-30 @ 30 fps).\n"
        "-- Source: Game/assets/pebble_toss.blend (action PebbleToss_Throw), made by\n"
        "-- Game/assets/vfx/_src/build_pebble_toss_throw.py and exported by export_pebble_toss_anim.py\n"
        "-- (change the poses there and rerun both). Release marker on frame 12 = 0.4 s.\n\n"
        "local Pose = require(script.Parent.Pose)\n\n"
        "local KEYFRAMES: { Pose.Keyframe } = {\n" + "\n".join(lines) + "\n}\n\nreturn KEYFRAMES\n"
    )
    with open(OUT, "w", newline="\n") as fh:
        fh.write(src)
    print(f"wrote {OUT}: {LAST - FIRST + 1} keyframes x {len(JOINTS)} joints, worst Euler round-trip error {worst:.2e}")


export()

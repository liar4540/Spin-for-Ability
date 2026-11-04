"""Spin for Abilities - Gale Step, stage 4: Blender dash -> Roblox keyframes (Luau + .rbxmx).

Run inside Blender with Game/assets/gale_step.blend open (after build_gale_step_anim.py):
    exec(open(r"<this file>").read())
Samples every frame 0-36 @ 30 fps and writes
    Game/src/client/Abilities/GaleStepKeyframes.luau   for Pose.luau (Rojo syncs it into Studio)
    Game/assets/gale_step_dash.rbxmx                    a KeyframeSequence for the Open Cloud upload
both with KeyframeMarkers "DashStart" (frame 6) and "DashEnd" (frame 17), Linear between keys.

Conversion (same as export_pebble_toss_anim.py): each joint's delta D (parent frame, rest axes)
    D_blender = R_rest * basis * R_rest^-1          translation t = R_rest * location (Root only)
    Roblox (x, y, z) -> Blender (x, -z, y) is the matrix M, so
    Transform_roblox = M^T * D_blender * M,         t_roblox = M^T * t
which is the joint's Motor6D.Transform / Pose.CFrame (R15 rest rotations are identity, C0 on the joint).
"""
import bpy, math
from mathutils import Matrix

OUT_LUAU = r"C:\Roblox\Spin for ability\Game\src\client\Abilities\GaleStepKeyframes.luau"
OUT_RBXMX = r"C:\Roblox\Spin for ability\Game\assets\gale_step_dash.rbxmx"
RIG = "GaleStepRig"
FPS, FIRST, LAST = 30, 0, 36
MARKERS = {6: "DashStart", 17: "DashEnd"}
JOINTS = ["Root", "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder",
          "LeftElbow", "LeftWrist", "RightHip", "RightKnee", "RightAnkle", "LeftHip", "LeftKnee", "LeftAnkle"]
# pose tree for the .rbxmx: joint -> (part it moves, parent part)
TREE = {"Root": ("LowerTorso", "HumanoidRootPart"), "Waist": ("UpperTorso", "LowerTorso"),
        "Neck": ("Head", "UpperTorso"), "RightShoulder": ("RightUpperArm", "UpperTorso"),
        "RightElbow": ("RightLowerArm", "RightUpperArm"), "RightWrist": ("RightHand", "RightLowerArm"),
        "LeftShoulder": ("LeftUpperArm", "UpperTorso"), "LeftElbow": ("LeftLowerArm", "LeftUpperArm"),
        "LeftWrist": ("LeftHand", "LeftLowerArm"), "RightHip": ("RightUpperLeg", "LowerTorso"),
        "RightKnee": ("RightLowerLeg", "RightUpperLeg"), "RightAnkle": ("RightFoot", "RightLowerLeg"),
        "LeftHip": ("LeftUpperLeg", "LowerTorso"), "LeftKnee": ("LeftLowerLeg", "LeftUpperLeg"),
        "LeftAnkle": ("LeftFoot", "LeftLowerLeg")}
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
    return ", ".join(f"{x:.3f}".rstrip("0").rstrip(".") if abs(x) >= 5e-4 else "0" for x in v)


def sample():
    """[(frame, {joint: (R_roblox 3x3, t_roblox or None)})]"""
    scene = bpy.context.scene
    rig = bpy.data.objects[RIG]
    out = []
    for frame in range(FIRST, LAST + 1):
        scene.frame_set(frame)
        poses = {}
        for name in JOINTS:
            pb = rig.pose.bones[name]
            rest = pb.bone.matrix_local.to_3x3()
            D = rest @ pb.rotation_quaternion.to_matrix() @ rest.inverted()
            R = M.transposed() @ D @ M
            t = M.transposed() @ (rest @ pb.location) if name == "Root" else None
            poses[name] = (R, t)
        out.append((frame, poses))
    scene.frame_set(FIRST)
    return out


def write_luau(frames):
    worst = 0.0
    lines = []
    for frame, poses in frames:
        rows = []
        for name in JOINTS:
            R, t = poses[name]
            rot = euler_xyz(R)
            worst = max(worst, max(abs(x) for row in (rebuild(*rot) - R) for x in row))
            entry = f"Rot = Vector3.new({fmt(rot)})"
            if t is not None:
                entry += f", Pos = Vector3.new({fmt(t)})"
            rows.append(f"\t\t\t{name} = {{ {entry} }},")
        marker = MARKERS.get(frame)
        lines.append(f"\t{{ -- frame {frame}{'  ' + marker.upper() if marker else ''}\n"
                     f"\t\tTime = {frame / FPS:.4f},{f' Markers = {{ \"{marker}\" }},' if marker else ''}\n"
                     f"\t\tStyle = Enum.EasingStyle.Linear,\n"
                     f"\t\tPose = {{\n" + "\n".join(rows) + "\n\t\t},\n\t},")
    src = (
        "--!strict\n"
        "-- GENERATED - do not edit by hand. Gale Step dash, one keyframe per frame (0-36 @ 30 fps).\n"
        "-- Source: Game/assets/gale_step.blend (action GaleStep_Dash), made by\n"
        "-- Game/assets/vfx/_src/build_gale_step_anim.py and exported by export_gale_step_anim.py\n"
        "-- (change the poses there and rerun both). Markers: DashStart frame 6 = 0.2 s,\n"
        "-- DashEnd frame 17 = 0.5667 s. No root motion: the dash itself is moved in code.\n\n"
        "local Pose = require(script.Parent.Pose)\n\n"
        "local KEYFRAMES: { Pose.Keyframe } = {\n" + "\n".join(lines) + "\n}\n\nreturn KEYFRAMES\n"
    )
    with open(OUT_LUAU, "w", newline="\n") as fh:
        fh.write(src)
    return worst


def write_rbxmx(frames):
    """KeyframeSequence XML: Keyframe > Pose tree (HumanoidRootPart weight 0 > LowerTorso > ...),
    KeyframeMarker children, PoseEasingStyle Linear (0) / direction In (0)."""
    ref = [0]

    def item(cls, props, children=""):
        ref[0] += 1
        return (f'<Item class="{cls}" referent="RBX{ref[0]:08X}"><Properties>{props}</Properties>'
                f"{children}</Item>")

    def cf(R, t):
        t = t if t is not None else (0, 0, 0)
        tags = ["X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"]
        vals = [t[0], t[1], t[2]] + [R[i][j] for i in range(3) for j in range(3)]
        return '<CoordinateFrame name="CFrame">' + "".join(
            f"<{k}>{v:.6f}</{k}>" for k, v in zip(tags, vals)) + "</CoordinateFrame>"

    def pose(name, R, t, weight, children):
        props = (f'<string name="Name">{name}</string>{cf(R, t)}'
                 f'<token name="EasingDirection">0</token><token name="EasingStyle">0</token>'
                 f'<float name="Weight">{weight}</float>')
        return item("Pose", props, children)

    keyframes = []
    ident = Matrix.Identity(3)
    for frame, poses in frames:
        by_parent = {}
        for joint, (part, parent) in TREE.items():
            by_parent.setdefault(parent, []).append((joint, part))

        def build(part):
            return "".join(pose(p, poses[j][0], poses[j][1], 1, build(p)) for j, p in by_parent.get(part, []))

        root = pose("HumanoidRootPart", ident, None, 0, build("HumanoidRootPart"))
        marker = MARKERS.get(frame)
        mk = item("KeyframeMarker", f'<string name="Name">{marker}</string><string name="Value"></string>') if marker else ""
        keyframes.append(item("Keyframe", f'<string name="Name">Keyframe</string><float name="Time">{frame / FPS:.6f}</float>',
                              root + mk))
    seq = item("KeyframeSequence", '<string name="Name">GaleStep_Dash</string><bool name="Loop">false</bool>'
                                   '<token name="Priority">2</token>', "".join(keyframes))
    xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
           'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
           'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">' + seq + "</roblox>")
    with open(OUT_RBXMX, "w", newline="\n") as fh:
        fh.write(xml)


frames = sample()
worst = write_luau(frames)
write_rbxmx(frames)
print(f"wrote {OUT_LUAU} and {OUT_RBXMX}: {len(frames)} keyframes x {len(JOINTS)} joints, "
      f"markers {MARKERS}, worst Euler round-trip error {worst:.2e}")

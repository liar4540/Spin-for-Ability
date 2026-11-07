"""Spin for Abilities - Frost Jab, stage 1: R15 rig for the punch, checked against Studio (Blender 5.2).

Run inside Blender (MCP or Text Editor):
    exec(open(r"<this file>").read())
Appends the R15 rig from Game/assets/pebble_toss.blend (built by build_pebble_toss_rig.py; that file
is only read, never saved) into an empty scene as "FrostJabRig", checks every joint position, part
size and parent against the numbers read from Studio, prints the comparison table and saves
Game/assets/frost_jab.blend (30 fps, frames 0-13).

Studio source (read 2026-11-06 with the Studio MCP): Workspace.Dummies."Training Dummy", the game's
R15 dummy (15 AnimationConstraint joints, no Motor6D; HumanoidDescription scales H/W/D/Head 1,
BodyType 0.3). ServerStorage.Dev.PebbleTossRig gave identical numbers. Positions are rig-local
(HumanoidRootPart at the origin); the Blender rig stands on Z = 0, so HRP sits HRP_HEIGHT up.
All joint rest rotations are identity.

Axes: Roblox (x, y, z) -> Blender (x, -z, y). Roblox faces -Z, so the rig faces +Y here.
"""
import bpy, os
from mathutils import Vector

SRC_BLEND = r"C:\Roblox\Spin for ability\Game\assets\pebble_toss.blend"
OUT_BLEND = r"C:\Roblox\Spin for ability\Game\assets\frost_jab.blend"
RIG_SRC, RIG_NAME = "PebbleTossRig", "FrostJabRig"
FPS, FIRST, LAST = 30, 0, 13
HRP_HEIGHT = 3.1924  # HRP centre above the floor: HipHeight 2.1924 + half its 2-stud height

# part: (centre, size), rig-local Roblox studs (Studio: hrp.CFrame:PointToObjectSpace(part.Position))
STUDIO_PARTS = {
    "HumanoidRootPart": ((0, 0, 0), (2, 2, 1)),
    "LowerTorso": ((0, -0.7998, 0), (1.9914, 0.4007, 1.0040)),
    "UpperTorso": ((0, 0.2496, 0), (1.9432, 1.6980, 1.0040)),
    "Head": ((0, 1.6744, 0), (1.1590, 1.1820, 1.1606)),
    "LeftUpperArm": ((-1.4721, 0.4281, 0), (1.0011, 1.2416, 1.0019)),
    "LeftLowerArm": ((-1.4721, -0.2016, 0), (1.0011, 1.1175, 1.0019)),
    "LeftHand": ((-1.4721, -0.8653, 0), (0.9843, 0.3158, 1.0283)),
    "RightUpperArm": ((1.4721, 0.4281, 0), (1.0011, 1.2416, 1.0019)),
    "RightLowerArm": ((1.4721, -0.2016, 0), (1.0011, 1.1175, 1.0019)),
    "RightHand": ((1.4721, -0.8653, 0), (0.9843, 0.3158, 1.0283)),
    "LeftUpperLeg": ((-0.4979, -1.4714, 0), (0.9928, 1.3629, 0.9727)),
    "LeftLowerLeg": ((-0.4979, -2.3339, 0), (0.9928, 1.3007, 0.9728)),
    "LeftFoot": ((-0.4979, -3.0364, 0), (1.0089, 0.3120, 1.0011)),
    "RightUpperLeg": ((0.4979, -1.4714, 0), (0.9928, 1.3629, 0.9727)),
    "RightLowerLeg": ((0.4979, -2.3339, 0), (0.9928, 1.3007, 0.9728)),
    "RightFoot": ((0.4979, -3.0364, 0), (1.0089, 0.3120, 1.0011)),
}

# joint: (part0, part1, world position = Attachment0.WorldPosition, rig-local)
STUDIO_JOINTS = {
    "Root": ("HumanoidRootPart", "LowerTorso", (0, -1.0, 0)),
    "Waist": ("LowerTorso", "UpperTorso", (0, -0.5995, 0)),
    "Neck": ("UpperTorso", "Head", (0, 1.0986, 0)),
    "LeftShoulder": ("UpperTorso", "LeftUpperArm", (-0.9716, 0.8471, 0)),
    "LeftElbow": ("LeftUpperArm", "LeftLowerArm", (-1.4717, 0.0732, 0)),
    "LeftWrist": ("LeftLowerArm", "LeftHand", (-1.4717, -0.7338, 0)),
    "RightShoulder": ("UpperTorso", "RightUpperArm", (0.9716, 0.8471, 0)),
    "RightElbow": ("RightUpperArm", "RightLowerArm", (1.4721, 0.0731, 0)),
    "RightWrist": ("RightLowerArm", "RightHand", (1.4721, -0.7338, 0)),
    "LeftHip": ("LowerTorso", "LeftUpperLeg", (-0.4979, -1.0, 0)),
    "LeftKnee": ("LeftUpperLeg", "LeftLowerLeg", (-0.4979, -1.9207, 0)),
    "LeftAnkle": ("LeftLowerLeg", "LeftFoot", (-0.4979, -2.9304, 0)),
    "RightHip": ("LowerTorso", "RightUpperLeg", (0.4979, -1.0, 0)),
    "RightKnee": ("RightUpperLeg", "RightLowerLeg", (0.4979, -1.9206, 0)),
    "RightAnkle": ("RightLowerLeg", "RightFoot", (0.4979, -2.9304, 0)),
}
BODY_PARTS = set(STUDIO_PARTS) - {"HumanoidRootPart"}
POS_TOL, SIZE_TOL = 0.002, 0.002  # studs


def to_blender(v):
    x, y, z = v
    return Vector((x, -z, y + HRP_HEIGHT))


def load_rig():
    scene = bpy.context.scene
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.armatures, bpy.data.actions, bpy.data.cameras, bpy.data.lights):
        for block in list(coll):
            if block.users == 0:
                coll.remove(block)
    with bpy.data.libraries.load(SRC_BLEND, link=False) as (src, dst):
        dst.objects = [n for n in src.objects if n == RIG_SRC or n in BODY_PARTS]
    for ob in dst.objects:
        scene.collection.objects.link(ob)
    rig = bpy.data.objects[RIG_SRC]
    rig.name = RIG_NAME
    if rig.animation_data:
        rig.animation_data.action = None
    for act in list(bpy.data.actions):
        if act.users == 0:
            bpy.data.actions.remove(act)
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
    scene.render.fps, scene.render.fps_base = FPS, 1
    scene.frame_start, scene.frame_end = FIRST, LAST
    for m in list(scene.timeline_markers):
        scene.timeline_markers.remove(m)
    scene.frame_set(FIRST)
    return rig


def compare(rig):
    """Prints one row per joint and part; returns (worst joint error, worst size error, problems)."""
    problems = []
    bones = rig.data.bones
    if {b.name for b in bones} != set(STUDIO_JOINTS) | {"HumanoidRootPart"}:
        problems.append(f"bone names differ: {sorted(b.name for b in bones)}")
    print(f"{'joint':14s} {'part0 -> part1':30s} {'Studio (Blender axes)':>26s} {'Blender bone head':>26s} {'error':>7s}")
    worst_joint = 0.0
    for name, (p0, p1, pos) in STUDIO_JOINTS.items():
        b = bones.get(name)
        if not b:
            problems.append(f"missing bone {name}")
            continue
        want = to_blender(pos)
        got = rig.matrix_world @ b.head_local
        err = (want - got).length
        worst_joint = max(worst_joint, err)
        parent_ok = b.get("part0") == p0 and b.get("part1") == p1
        if not parent_ok:
            problems.append(f"{name}: part0/part1 {b.get('part0')}/{b.get('part1')} != {p0}/{p1}")
        expect_parent = "HumanoidRootPart" if p0 == "HumanoidRootPart" else next(
            j for j, d in STUDIO_JOINTS.items() if d[1] == p0)
        if not b.parent or b.parent.name != expect_parent:
            problems.append(f"{name}: parent bone {b.parent.name if b.parent else None} != {expect_parent}")
        print(f"{name:14s} {p0 + ' -> ' + p1:30s} ({want.x:+.4f},{want.y:+.4f},{want.z:+.4f}) "
              f"({got.x:+.4f},{got.y:+.4f},{got.z:+.4f}) {err:7.4f}")
    worst_size = 0.0
    for part, (pos, size) in STUDIO_PARTS.items():
        if part == "HumanoidRootPart":
            continue
        ob = bpy.data.objects.get(part)
        if not ob:
            problems.append(f"missing part mesh {part}")
            continue
        corners = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
        lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
        hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
        got_size = hi - lo
        want_size = Vector((size[0], size[2], size[1]))
        size_err = max(abs(a - b) for a, b in zip(got_size, want_size))
        pos_err = ((lo + hi) / 2 - to_blender(pos)).length
        worst_size = max(worst_size, size_err)
        if size_err > SIZE_TOL or pos_err > POS_TOL:
            problems.append(f"{part}: size error {size_err:.4f}, centre error {pos_err:.4f}")
    if worst_joint > POS_TOL:
        problems.append(f"worst joint error {worst_joint:.4f} > {POS_TOL}")
    return worst_joint, worst_size, problems


rig = load_rig()
worst_joint, worst_size, problems = compare(rig)
print(f"worst joint position error {worst_joint:.4f} studs | worst part size error {worst_size:.4f} studs")
print("PROBLEMS:" if problems else "all joints, parents, names and part sizes match Studio")
for p in problems:
    print("  " + p)
os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
print("saved", OUT_BLEND)

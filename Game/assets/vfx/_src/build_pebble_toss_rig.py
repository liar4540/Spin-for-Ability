"""Spin for Abilities - Pebble Toss, stage 1: R15 block rig matching Studio (Blender 5.2).

Run inside Blender (MCP or Text Editor):
    exec(open(r"<this file>").read())

Visual source of truth: images/abilities/pebble toss.png.
Rig data source: workspace.PebbleTossRig in Studio (default R15 block rig from an empty
HumanoidDescription). The game uses AnimationConstraint joints; their Attachment0/Attachment1
CFrames are the Motor6D C0/C1 equivalents and are copied here verbatim (all rest rotations are
identity, so only positions are listed).

Axes (1 Blender unit = 1 stud, +Y = forward, +Z = up; vault: 11 Abilities -> Rules):
    Roblox (x, y, z) -> Blender (x, -z, y). Roblox faces -Z, so the rig faces +Y here.
    Rotations convert as R_blender = M * R_roblox * M^T with M = that axis swap (a proper rotation,
    +90 deg about X), so no mirroring.
Bones are named after the R15 JOINTS (Root, Waist, Neck, LeftShoulder, ...) and carry the part they
move as the custom property "part1"; the extra root bone "HumanoidRootPart" never moves (no root
motion). Each bone's head sits exactly on its joint. One block mesh per part, bone-parented.
Floor is Z = 0 (Studio baseplate top is Y = 0).
"""
import bpy, os
from mathutils import Vector, Matrix

OUT_BLEND = r"C:\Roblox\Spin for ability\Game\assets\pebble_toss.blend"
FPS, FRAME_START, FRAME_END = 30, 0, 30

# Part centres (Roblox, rig-local: Studio z 30 subtracted) and sizes, read from Studio.
PARTS = {
    "HumanoidRootPart": ((0, 3.19242, 0), (2, 2, 1)),
    "LowerTorso": ((0, 2.39267, 0), (1.99141, 0.40065, 1.004)),
    "UpperTorso": ((0, 3.44197, 0), (1.94321, 1.69803, 1.004)),
    "Head": ((0, 4.86681, 0), (1.15898, 1.18201, 1.16064)),
    "LeftUpperArm": ((-1.47214, 3.62056, 0), (1.00107, 1.2416, 1.00187)),
    "LeftLowerArm": ((-1.47214, 2.99085, 0), (1.00107, 1.11751, 1.00187)),
    "LeftHand": ((-1.47213, 2.3271, 0), (0.98427, 0.31577, 1.02827)),
    "RightUpperArm": ((1.47214, 3.62056, 0), (1.00107, 1.2416, 1.00187)),
    "RightLowerArm": ((1.47214, 2.99084, 0), (1.00107, 1.11751, 1.00187)),
    "RightHand": ((1.47214, 2.3271, 0), (0.98427, 0.31577, 1.02827)),
    "LeftUpperLeg": ((-0.49785, 1.72103, 0), (0.99284, 1.36293, 0.9727)),
    "LeftLowerLeg": ((-0.49785, 0.85849, 0), (0.99284, 1.30066, 0.9728)),
    "LeftFoot": ((-0.49785, 0.15599, 0), (1.00887, 0.31199, 1.00107)),
    "RightUpperLeg": ((0.49785, 1.72103, 0), (0.99284, 1.36293, 0.9727)),
    "RightLowerLeg": ((0.49785, 0.8585, 0), (0.99284, 1.30066, 0.9728)),
    "RightFoot": ((0.49785, 0.156, 0), (1.00887, 0.31199, 1.00107)),
}

# joint: (part0, part1, C0 position, C1 position) - Roblox, read from Studio.
JOINTS = {
    "Root": ("HumanoidRootPart", "LowerTorso", (0, -1, 0), (0, -0.20025, 0)),
    "Waist": ("LowerTorso", "UpperTorso", (0, 0.2003, 0), (0, -0.849, 0)),
    "Neck": ("UpperTorso", "Head", (0, 0.84903, 0), (0, -0.5758, 0)),
    "LeftShoulder": ("UpperTorso", "LeftUpperArm", (-0.9716, 0.59751, 0), (0.50053, 0.41892, 0)),
    "LeftElbow": ("LeftUpperArm", "LeftLowerArm", (0.00048, -0.35489, 0), (0.00048, 0.27482, 0)),
    "LeftWrist": ("LeftLowerArm", "LeftHand", (0.00048, -0.53217, 0), (0.00047, 0.13157, 0)),
    "RightShoulder": ("UpperTorso", "RightUpperArm", (0.9716, 0.59751, 0), (-0.50053, 0.41892, 0)),
    "RightElbow": ("RightUpperArm", "RightLowerArm", (0, -0.35501, 0), (0, 0.27471, 0)),
    "RightWrist": ("RightLowerArm", "RightHand", (0, -0.53217, 0), (0, 0.13157, 0)),
    "LeftHip": ("LowerTorso", "LeftUpperLeg", (-0.49785, -0.20025, 0), (0, 0.47139, 0)),
    "LeftKnee": ("LeftUpperLeg", "LeftLowerLeg", (0, -0.44935, 0), (0, 0.41319, 0)),
    "LeftAnkle": ("LeftLowerLeg", "LeftFoot", (0, -0.59649, 0), (0, 0.10602, 0)),
    "RightHip": ("LowerTorso", "RightUpperLeg", (0.49785, -0.20025, 0), (0, 0.47139, 0)),
    "RightKnee": ("RightUpperLeg", "RightLowerLeg", (0, -0.44917, 0), (0, 0.41336, 0)),
    "RightAnkle": ("RightLowerLeg", "RightFoot", (0, -0.59649, 0), (0, 0.10602, 0)),
}

# Reference colours: light lavender head/arms/hands #D8D4EA, near-black torso/legs/feet #1C1C20
# (same hexes are set on the Studio rig's BodyColors). Linear values for the shader.
LIGHT, DARK = (0.686, 0.658, 0.822), (0.0116, 0.0116, 0.0144)
DARK_PARTS = {"LowerTorso", "UpperTorso", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
              "RightUpperLeg", "RightLowerLeg", "RightFoot"}


def rbx_to_bl(v):
    x, y, z = v
    return Vector((x, -z, y))


def part_pos(name):
    return Vector(PARTS[name][0])


def joint_world(name):
    """World (Roblox) position of a joint: Part0.Position + C0 (rest rotations are identity)."""
    p0, _, c0, _ = JOINTS[name]
    return part_pos(p0) + Vector(c0)


def check_joints():
    """Part0 * C0 must equal Part1 * C1 in the rest pose; report the worst mismatch."""
    worst = 0.0
    for name, (p0, p1, c0, c1) in JOINTS.items():
        err = ((part_pos(p0) + Vector(c0)) - (part_pos(p1) + Vector(c1))).length
        worst = max(worst, err)
    return worst


def bone_tail(joint):
    """Where each bone points: to its child joint, or to the far end of a leaf part."""
    part1 = JOINTS[joint][1]
    children = [j for j, d in JOINTS.items() if d[0] == part1]
    head = joint_world(joint)
    pos, size = part_pos(part1), Vector(PARTS[part1][1])
    if part1 == "UpperTorso":
        return joint_world("Neck")
    if part1 == "LowerTorso":
        return joint_world("Waist")
    if len(children) == 1:
        return joint_world(children[0])
    if part1 == "Head":
        return pos + Vector((0, size.y / 2, 0))
    if part1.endswith("Hand"):
        return pos + Vector((0, -size.y / 2, 0))
    if part1.endswith("Foot"):  # ankle -> toe (forward is -Z in Roblox)
        return pos + Vector((0, -size.y / 2, -size.z / 2))
    raise ValueError(joint)


def material(name, rgb):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Roughness"].default_value = 0.7
    mat.diffuse_color = (*rgb, 1)
    return mat


def clear_scene():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.armatures, bpy.data.actions):
        for block in list(coll):
            if block.users == 0:
                coll.remove(block)


def build():
    clear_scene()
    scene = bpy.context.scene
    scene.render.fps, scene.render.fps_base = FPS, 1
    scene.frame_start, scene.frame_end = FRAME_START, FRAME_END
    scene.frame_set(FRAME_START)
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    arm_data = bpy.data.armatures.new("R15")
    rig = bpy.data.objects.new("PebbleTossRig", arm_data)
    scene.collection.objects.link(rig)
    rig.show_in_front = True
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")

    eb = arm_data.edit_bones
    root = eb.new("HumanoidRootPart")
    hrp = part_pos("HumanoidRootPart")
    root.head = rbx_to_bl(hrp + Vector((0, -1, 0)))
    root.tail = rbx_to_bl(hrp + Vector((0, -1, -1)))  # points forward, stays still
    root.roll = 0

    order = ["Root", "Waist", "Neck", "LeftShoulder", "LeftElbow", "LeftWrist",
             "RightShoulder", "RightElbow", "RightWrist", "LeftHip", "LeftKnee", "LeftAnkle",
             "RightHip", "RightKnee", "RightAnkle"]
    part_to_bone = {"HumanoidRootPart": "HumanoidRootPart"}
    for j in order:
        b = eb.new(j)
        b.head = rbx_to_bl(joint_world(j))
        b.tail = rbx_to_bl(bone_tail(j))
        # roll: bone local Z points to Blender -Y (back) for vertical bones, +Z (up) for the foot,
        # so every bone has a fixed, known rest frame for the stage 5 conversion.
        b.align_roll(Vector((0, 0, 1)) if JOINTS[j][1].endswith("Foot") else Vector((0, -1, 0)))
        b.parent = eb[part_to_bone[JOINTS[j][0]]]
        b.use_connect = False
        part_to_bone[JOINTS[j][1]] = j
    bpy.ops.object.mode_set(mode="OBJECT")

    for j in order:
        rig.data.bones[j]["part1"] = JOINTS[j][1]
        rig.data.bones[j]["part0"] = JOINTS[j][0]

    light, dark = material("R15_Light", LIGHT), material("R15_Dark", DARK)
    for part, (pos, size) in PARTS.items():
        if part == "HumanoidRootPart":
            continue
        bpy.ops.mesh.primitive_cube_add(size=1, location=rbx_to_bl(pos))
        ob = bpy.context.active_object
        ob.name = part
        ob.data.name = part
        ob.scale = (size[0], size[2], size[1])  # Roblox (x, y, z) size -> Blender (x, z-depth, y-height)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        ob.data.materials.append(dark if part in DARK_PARTS else light)
        bone = part_to_bone[part]
        world = ob.matrix_world.copy()
        ob.parent = rig
        ob.parent_type = "BONE"
        ob.parent_bone = bone
        ob.matrix_world = world

    # Saves straight to the stage file.
    os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
    return rig


worst = check_joints()
rig = build()
print(f"joint check: worst Part0*C0 vs Part1*C1 mismatch = {worst:.5f} studs")
for b in rig.data.bones:
    h = rig.matrix_world @ b.head_local
    print(f"{b.name:16s} parent={b.parent.name if b.parent else '-':16s} head=({h.x:+.4f}, {h.y:+.4f}, {h.z:+.4f}) part1={b.get('part1', '-')}")
print("saved", OUT_BLEND)

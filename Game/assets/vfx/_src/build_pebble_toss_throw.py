"""Spin for Abilities - Pebble Toss, stage 2: right-handed overhand throw, frames 0-30 @ 30 fps.

Run inside Blender (MCP or Text Editor):
    exec(open(r"<this file>").read())
Rebuilds the rig first (build_pebble_toss_rig.py), then keys the throw and bakes it to one key per
frame on every joint bone (action "PebbleToss_Throw"), then saves Game/assets/pebble_toss.blend.

Axes: +Y = forward (the target), +X = the rig's right, +Z = up.
Every joint rotation below is a "delta" D in the PARENT's frame, written with rest-aligned axes:
    child_world = parent_world_delta * D * child_rest
which is exactly what a Roblox joint Transform is (all R15 rest rotations are identity), after the
axis swap Roblox (x, y, z) -> Blender (x, -z, y). Stage 5 converts back with the same matrices.
Angle helpers: Rx(+) swings a hanging arm/leg forward (and pitches a torso BACK), Rz(+) turns
toward the rig's left, Ry(-) lifts the right arm out sideways (Ry(+) the left).

No root motion: HumanoidRootPart never moves. The Root joint (LowerTorso) shifts and drops to move
the weight; the legs are solved per frame with exact 2-bone IK (key_legs) so both feet stay planted
(the back foot rolls onto its toes from the hold to the follow-through), then everything is baked
to one plain key per frame.

Timing (overlap: hips lead, torso 1 frame later, arms 1 frame after that):
    pose        hips  torso  arms/head
    ready         0     0      0
    wind-up       5     6      7
    hold          8     8      9      (hips already uncoil from 8)
    release      10    11     12      <- RELEASE FRAME = 12
    follow       16    17     18
    ready        28    29     30
"""
import bpy, math, os
from mathutils import Matrix, Vector, Quaternion

HERE = r"C:\Roblox\Spin for ability\Game\assets\vfx\_src"
exec(open(os.path.join(HERE, "build_pebble_toss_rig.py")).read())  # defines rig, PARTS, JOINTS, rbx_to_bl

ACTION = "PebbleToss_Throw"
RELEASE_FRAME = 12

# Feet (ankle joint positions, Blender axes): 1.4 studs apart sideways (shoulder width) and
# 1.4 front-to-back, left foot forward - the lunge stance of the reference.
FEET = {"Left": Vector((-0.70, 0.70, 0.262)), "Right": Vector((0.70, -0.70, 0.262))}
# Back (right) foot rolls up onto its toes as the weight goes forward: heel lift in degrees,
# pivoting on the toe edge. Smoothstep between these keys.
HEEL_LIFT = {"Right": [(0, 0), (9, 0), (12, 32), (18, 38), (24, 20), (30, 0)]}
FOOT_HALF_DEPTH, ANKLE_HEIGHT = 0.5, 0.262


def heel_lift(side, frame):
    keys = HEEL_LIFT.get(side)
    if not keys:
        return 0.0
    for (f0, a0), (f1, a1) in zip(keys, keys[1:]):
        if f0 <= frame <= f1:
            t = (frame - f0) / (f1 - f0)
            t = t * t * (3 - 2 * t)
            return a0 + (a1 - a0) * t
    return keys[-1][1]


def Rx(d): return Matrix.Rotation(math.radians(d), 3, "X")
def Ry(d): return Matrix.Rotation(math.radians(d), 3, "Y")
def Rz(d): return Matrix.Rotation(math.radians(d), 3, "Z")
I = Matrix.Identity(3)

# --- key poses -----------------------------------------------------------------------------------
# hips: (Root offset in studs, Root rotation)   torso: Waist   head: Neck
POSES = {
    "ready": {
        "hips": (Vector((0, 0, -0.18)), I),
        "Waist": Rx(-4),
        "Neck": Rx(3),
        "RightShoulder": Ry(-8) @ Rx(6), "RightElbow": Rx(18), "RightWrist": I,
        "LeftShoulder": Ry(8) @ Rx(6), "LeftElbow": Rx(18), "LeftWrist": I,
    },
    "windup": {
        # weight back onto the right leg, hips turned 18 deg away, slight lean back
        "hips": (Vector((0.16, -0.26, -0.26)), Rz(-18) @ Rx(4)),
        "Waist": Rz(-22) @ Rx(6),                    # total twist 40 deg away from the target
        "Neck": Rz(32) @ Rx(-4),                     # eyes stay on the target
        # right arm: rotated so its front faces up, lifted 104 deg sideways, swung 12 deg back;
        # elbow bent 95 deg so the forearm points up: hand by/behind the head
        "RightShoulder": Rz(-12) @ Ry(-104) @ Rz(-90), "RightElbow": Rx(95), "RightWrist": Rx(-20),
        # left arm points at the target: forward 90 deg, turned back 40 deg against the twist
        "LeftShoulder": Rz(40) @ Rx(92), "LeftElbow": Rx(10), "LeftWrist": I,
    },
    "release": {
        # weight onto the front (left) leg, hips 10 deg past centre, leaning forward
        "hips": (Vector((-0.12, 0.30, -0.30)), Rz(10) @ Rx(-6)),
        "Waist": Rz(10) @ Rx(-12),                   # total +20 deg past centre, 18 deg forward
        "Neck": Rz(-16) @ Rx(12),
        # right arm straight forward at shoulder height (cancel the 20 deg twist and 18 deg lean)
        "RightShoulder": Rz(-20) @ Rx(108), "RightElbow": Rx(5), "RightWrist": Rx(15),
        # left arm pulled back to the hip
        "LeftShoulder": Ry(10) @ Rx(-32), "LeftElbow": Rx(70), "LeftWrist": I,
    },
    "follow": {
        "hips": (Vector((-0.14, 0.34, -0.32)), Rz(16) @ Rx(-8)),
        "Waist": Rz(12) @ Rx(-18),
        "Neck": Rz(-20) @ Rx(18),
        # right arm carries on down and across the body (in front of the left thigh)
        "RightShoulder": Rz(11) @ Rx(52), "RightElbow": Rx(22), "RightWrist": Rx(10),
        "LeftShoulder": Ry(12) @ Rx(-36), "LeftElbow": Rx(62), "LeftWrist": I,
    },
}

# on the way back from the follow-through the right arm swings round the OUTSIDE (forward and out),
# instead of cutting through the torso to get to its side
POSES["recover"] = dict(POSES["ready"], **{
    "RightShoulder": Ry(-22) @ Rx(30), "RightElbow": Rx(28),
    "LeftShoulder": Ry(12) @ Rx(-10), "LeftElbow": Rx(30),
    "Neck": Rx(6),
})

HIPS = ["hips"]
TORSO = ["Waist"]
ARMS = ["Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist"]
TIMELINE = {  # group -> [(frame, pose)]
    "hips": [(0, "ready"), (5, "windup"), (8, "windup"), (10, "release"), (16, "follow"), (28, "ready"), (30, "ready")],
    "torso": [(0, "ready"), (6, "windup"), (8, "windup"), (11, "release"), (17, "follow"), (29, "ready"), (30, "ready")],
    "arms": [(0, "ready"), (7, "windup"), (9, "windup"), (12, "release"), (18, "follow"), (24, "recover"), (30, "ready")],
}


def rest_rot(pb):
    return pb.bone.matrix_local.to_3x3()


def key_rotation(pb, D, frame, prev):
    R = rest_rot(pb)
    q = (R.inverted() @ D @ R).to_quaternion()
    if prev is not None:
        q.make_compatible(prev)
    pb.rotation_quaternion = q
    pb.keyframe_insert("rotation_quaternion", frame=frame, group=pb.name)
    return q


def key_location(pb, offset, frame):
    pb.location = rest_rot(pb).inverted() @ offset
    pb.keyframe_insert("location", frame=frame, group=pb.name)


def bone_len(rig, name):
    return (rig.data.bones[name].tail_local - rig.data.bones[name].head_local).length


def leg_frame(down, n):
    """World delta for a leg segment pointing along `down`, bending in the plane with normal n.
    Rest segment: points -Z, its front is +Y."""
    z = -down.normalized()
    y = down.normalized().cross(n).normalized()       # front: the side the knee sticks out to
    x = y.cross(z).normalized()
    return Matrix((x, y, z)).transposed()


def key_legs(rig, frame, prev):
    """Exact 2-bone IK: ankle on its planted spot, knee bent forward (slightly out), foot flat."""
    bpy.context.scene.frame_set(frame)
    root = rig.pose.bones["Root"]
    pelvis = root.matrix.to_3x3() @ rest_rot(root).inverted()   # world delta of LowerTorso
    for side, planted in FEET.items():
        out = 1 if side == "Right" else -1
        foot = Rx(-heel_lift(side, frame))           # heel up, toes stay down
        toe = planted + Vector((0, FOOT_HALF_DEPTH, -ANKLE_HEIGHT))
        target = toe + foot @ (planted - toe)
        hip, knee, ankle = (rig.pose.bones[f"{side}{j}"] for j in ("Hip", "Knee", "Ankle"))
        L1, L2 = bone_len(rig, f"{side}Hip"), bone_len(rig, f"{side}Knee")
        H = rig.matrix_world @ hip.head
        d_vec = target - H
        d = min(d_vec.length, 0.999 * (L1 + L2))
        u = d_vec.normalized()
        cos_a = (L1 * L1 + d * d - L2 * L2) / (2 * L1 * d)
        a = math.acos(max(-1.0, min(1.0, cos_a)))
        fwd = Vector((0.15 * out, 1, 0))
        w = (fwd - fwd.dot(u) * u).normalized()
        K = H + L1 * (math.cos(a) * u + math.sin(a) * w)
        A = H + d * u
        t1, t2 = (K - H).normalized(), (A - K).normalized()
        n = t1.cross(t2).normalized()
        W1, W2 = leg_frame(t1, n), leg_frame(t2, n)
        D_hip = pelvis.inverted() @ W1
        D_knee = W1.inverted() @ W2
        D_ankle = W2.inverted() @ foot                # foot flat (or rolled onto its toes), facing forward
        for pb, D in ((hip, D_hip), (knee, D_knee), (ankle, D_ankle)):
            prev[pb.name] = key_rotation(pb, D, frame, prev.get(pb.name))


def animate(rig):
    scene = bpy.context.scene
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    rig.animation_data_create()
    act = bpy.data.actions.new(ACTION)
    rig.animation_data.action = act

    prev = {}
    for group, keys in TIMELINE.items():
        names = HIPS if group == "hips" else TORSO if group == "torso" else ARMS
        for frame, pose in keys:
            for name in names:
                if name == "hips":
                    offset, D = POSES[pose]["hips"]
                    pb = rig.pose.bones["Root"]
                    key_location(pb, offset, frame)
                    prev["Root"] = key_rotation(pb, D, frame, prev.get("Root"))
                else:
                    pb = rig.pose.bones[name]
                    prev[name] = key_rotation(pb, POSES[pose][name], frame, prev.get(name))

    # Keys are Bezier / auto-clamped (Blender default): 9->12 is 3 frames so it snaps,
    # 12->30 eases through 18 into the end pose so it settles slowly.
    # legs: solved and keyed on every frame from the (already keyed) hips
    for frame in range(0, 31):
        key_legs(rig, frame, prev)

    # bake to one key per frame on every joint bone (stage 5 samples these)
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.nla.bake(frame_start=0, frame_end=30, only_selected=True, visual_keying=False,
                     clear_constraints=False, use_current_action=True, bake_types={"POSE"})
    bpy.ops.pose.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    rig.animation_data.action.name = ACTION
    m = scene.timeline_markers.get("Release") or scene.timeline_markers.new("Release", frame=RELEASE_FRAME)
    m.frame = RELEASE_FRAME
    scene.frame_set(0)
    bpy.ops.wm.save_mainfile()


animate(rig)
print("action", rig.animation_data.action.name, "| release frame", RELEASE_FRAME)

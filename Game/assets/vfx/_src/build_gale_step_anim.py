"""Spin for Abilities - Gale Step, stage 1: dash animation, frames 0-36 @ 30 fps.

Run inside Blender (MCP or Text Editor):
    exec(open(r"<this file>").read())
Appends the R15 rig from Game/assets/pebble_toss.blend (built by build_pebble_toss_rig.py) into an
empty scene as "GaleStepRig", keys the dash, bakes it to one key per frame on every joint bone
(action "GaleStep_Dash"), adds the DashStart (6) / DashEnd (17) markers and saves
Game/assets/gale_step.blend.

Axes and joint convention: same as build_pebble_toss_throw.py. +Y = forward, +X = the rig's right,
+Z = up. Each joint rotation is a delta D in the parent's frame with rest-aligned axes, i.e. the
Roblox Motor6D.Transform after the axis swap Roblox (x, y, z) -> Blender (x, -z, y).
    Rx(+) swings a hanging arm/leg forward (and pitches a torso BACK), so a forward lean is Rx(-).
    Rz(+) turns toward the rig's left. Ry(-) lifts the right arm out sideways, Ry(+) the left.

No root motion: HumanoidRootPart never moves (the 30-stud dash is done in code). The Root joint
shifts / drops / leans the body; the legs are solved per frame with exact 2-bone IK toward keyed
ankle targets (grounded keys step with a small arc instead of sliding).

Timing (overlap: hips and torso lead, arms/head and feet 1-2 frames later):
    pose      hips+torso   arms/head
    idle          0           0
    charge        4           5
    launch        6           7       <- DashStart marker = 6
    dash        9-15 (bob)  10-15
    brake        17          18       <- DashEnd marker = 17
    settle       22          24
    idle         36          36
"""
import bpy, math, os
from mathutils import Matrix, Vector

SRC_BLEND = r"C:\Roblox\Spin for ability\Game\assets\pebble_toss.blend"
OUT_BLEND = r"C:\Roblox\Spin for ability\Game\assets\gale_step.blend"
RIG_SRC, RIG_NAME = "PebbleTossRig", "GaleStepRig"
ACTION = "GaleStep_Dash"
FPS, FIRST, LAST = 30, 0, 36
MARKERS = {"DashStart": 6, "DashEnd": 17}
ANKLE_HEIGHT, FOOT_HALF_DEPTH = 0.262, 0.5
BODY_PARTS = {"Head", "UpperTorso", "LowerTorso", *(f"{s}{p}" for s in ("Left", "Right") for p in (
    "UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot"))}


def Rx(d): return Matrix.Rotation(math.radians(d), 3, "X")
def Ry(d): return Matrix.Rotation(math.radians(d), 3, "Y")
def Rz(d): return Matrix.Rotation(math.radians(d), 3, "Z")
I = Matrix.Identity(3)
V = Vector


def arms(r_sh, l_sh, elbow, wrist=I):
    return {"RightShoulder": r_sh, "LeftShoulder": l_sh, "RightElbow": elbow, "LeftElbow": elbow,
            "RightWrist": wrist, "LeftWrist": wrist}


# --- key poses -----------------------------------------------------------------------------------
# hips: (Root offset in studs, Root rotation)   torso: Waist   head: Neck
# torso lean = hips pitch + Waist pitch (upper torso)
POSES = {
    "idle": dict(hips=(V((0, 0, -0.04)), I), Waist=Rx(-3), Neck=Rx(2),
                 **arms(Ry(-10) @ Rx(3), Ry(10) @ Rx(3), Rx(14))),
    # deep crouch, sitting back a little, 25 deg forward, arms pulled slightly back
    "charge": dict(hips=(V((0, -0.10, -0.33)), Rx(-10)), Waist=Rx(-15), Neck=Rx(20),
                   **arms(Ry(-18) @ Rx(-20), Ry(18) @ Rx(-20), Rx(40))),
    # 45 deg forward lean, weight thrown forward, arms swept back behind the body
    "launch": dict(hips=(V((0, 0.35, -0.38)), Rx(-20)), Waist=Rx(-25), Neck=Rx(32),
                   **arms(Ry(-12) @ Rx(-75), Ry(12) @ Rx(-75), Rx(12), Rx(-10))),
    # ninja run: 50 deg forward, arms trailing straight back (bob between A and B)
    "dashA": dict(hips=(V((0, 0.30, -0.50)), Rx(-22)), Waist=Rx(-28)),
    "dashB": dict(hips=(V((0, 0.30, -0.43)), Rx(-20)), Waist=Rx(-29)),
    "dash": dict(Neck=Rx(40), **arms(Ry(-6) @ Rx(-55), Ry(6) @ Rx(-55), Rx(4), Rx(-8))),
    # brake: torso snaps upright and twists 30 deg to the right with the swirl (opens toward the viewer, panel 7), arms out to the sides
    "brake": dict(hips=(V((0, 0.05, -0.45)), Rz(-15) @ Rx(6)), Waist=Rz(-15) @ Rx(-4), Neck=Rz(12),
                  **arms(Ry(-65) @ Rx(12), Ry(65) @ Rx(12), Rx(20))),
    # settle: slight crouch recovering, arms coming down
    "settle": dict(hips=(V((0, 0.02, -0.30)), Rz(-6) @ Rx(-2)), Waist=Rz(-4) @ Rx(-6), Neck=Rz(5) @ Rx(5),
                   **arms(Ry(-30) @ Rx(8), Ry(30) @ Rx(8), Rx(25))),
}

ARM_JOINTS = ["Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist"]
BOB = [(f, "dashA" if f % 2 else "dashB") for f in range(9, 16)]
TIMELINE = {  # group -> [(frame, pose)]
    "hips": [(0, "idle"), (4, "charge"), (6, "launch"), *BOB, (17, "brake"), (22, "settle"), (36, "idle")],
    "torso": [(0, "idle"), (4, "charge"), (6, "launch"), *BOB, (17, "brake"), (22, "settle"), (36, "idle")],
    "arms": [(0, "idle"), (5, "charge"), (7, "launch"), (10, "dash"), (15, "dash"), (18, "brake"),
             (24, "settle"), (36, "idle")],
}

# Feet: (frame, ankle position, foot pitch in degrees (+ = toes down / heel up), grounded).
# Grounded + pitch pivots on the toe edge (heel lift); grounded -> grounded moves step with an arc.
G = ANKLE_HEIGHT
FEET = {
    "Left": [  # front foot
        (0, V((-0.62, 0.20, G)), 0, True),
        (5, V((-0.75, 0.45, G)), 0, True),
        (7, V((-0.65, 1.10, 0.42)), 25, False),   # front knee driven up
        (10, V((-0.55, 1.30, 0.32)), 15, False),  # mid-stride
        (15, V((-0.55, 1.30, 0.32)), 15, False),
        (18, V((-0.70, 0.95, G)), 0, True),       # planted brake foot
        (23, V((-0.70, 0.95, G)), 0, True),
        (30, V((-0.62, 0.20, G)), 0, True),       # steps back to idle
        (36, V((-0.62, 0.20, G)), 0, True),
    ],
    "Right": [  # back foot
        (0, V((0.62, -0.20, G)), 0, True),
        (5, V((0.75, -0.55, G)), 0, True),
        (7, V((0.60, -1.45, G)), 45, True),       # pushing off on the toes, leg extended
        (10, V((0.50, -1.05, 0.70)), 40, False),  # trailing leg
        (15, V((0.50, -1.05, 0.70)), 40, False),
        (18, V((0.65, -0.75, G)), 30, True),
        (23, V((0.65, -0.75, G)), 10, True),
        (33, V((0.62, -0.20, G)), 0, True),
        (36, V((0.62, -0.20, G)), 0, True),
    ],
}


def smooth(t):
    return t * t * (3 - 2 * t)


def foot_at(side, frame):
    keys = FEET[side]
    for (f0, p0, a0, g0), (f1, p1, a1, g1) in zip(keys, keys[1:]):
        if f0 <= frame <= f1:
            t = smooth((frame - f0) / (f1 - f0))
            pos = p0.lerp(p1, t)
            if g0 and g1:
                step = (p1 - p0).length
                pos.z += 4 * min(0.35, 0.5 * step) * t * (1 - t)
            return pos, a0 + (a1 - a0) * t
    _, p, a, _ = keys[-1]
    return p.copy(), a


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
    y = down.normalized().cross(n).normalized()
    x = y.cross(z).normalized()
    return Matrix((x, y, z)).transposed()


KNEE_BEND = {}


def key_legs(rig, frame, prev):
    """Exact 2-bone IK toward the keyed ankle target, knee bent forward (slightly out)."""
    bpy.context.scene.frame_set(frame)
    root = rig.pose.bones["Root"]
    pelvis = root.matrix.to_3x3() @ rest_rot(root).inverted()
    for side in FEET:
        out = 1 if side == "Right" else -1
        ankle, pitch = foot_at(side, frame)
        foot = Rx(-pitch)
        if ankle.z <= ANKLE_HEIGHT + 1e-4 and pitch > 0:   # grounded heel lift: pivot on the toe edge
            toe = ankle + V((0, FOOT_HALF_DEPTH, -ANKLE_HEIGHT))
            ankle = toe + foot @ (ankle - toe)
        hip, knee, ank = (rig.pose.bones[f"{side}{j}"] for j in ("Hip", "Knee", "Ankle"))
        L1, L2 = bone_len(rig, f"{side}Hip"), bone_len(rig, f"{side}Knee")
        H = rig.matrix_world @ hip.head
        d_vec = ankle - H
        d = min(d_vec.length, 0.999 * (L1 + L2))
        u = d_vec.normalized()
        a = math.acos(max(-1.0, min(1.0, (L1 * L1 + d * d - L2 * L2) / (2 * L1 * d))))
        fwd = V((0.15 * out, 1, 0))
        w = (fwd - fwd.dot(u) * u).normalized()
        K = H + L1 * (math.cos(a) * u + math.sin(a) * w)
        A = H + d * u
        t1, t2 = (K - H).normalized(), (A - K).normalized()
        n = t1.cross(t2).normalized()
        W1, W2 = leg_frame(t1, n), leg_frame(t2, n)
        KNEE_BEND[(side, frame)] = math.degrees(t1.angle(t2))
        for pb, D in ((hip, pelvis.inverted() @ W1), (knee, W1.inverted() @ W2), (ank, W2.inverted() @ foot)):
            prev[pb.name] = key_rotation(pb, D, frame, prev.get(pb.name))


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
        old = rig.animation_data.action
        rig.animation_data.action = None
        if old and old.users == 0:
            bpy.data.actions.remove(old)
    for act in list(bpy.data.actions):
        if act.name.startswith("PebbleToss") and act.users == 0:
            bpy.data.actions.remove(act)
    scene.render.fps, scene.render.fps_base = FPS, 1
    scene.frame_start, scene.frame_end = FIRST, LAST
    for m in list(scene.timeline_markers):
        scene.timeline_markers.remove(m)
    return rig


def animate(rig):
    scene = bpy.context.scene
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
    rig.animation_data_create()
    act = bpy.data.actions.new(ACTION)
    rig.animation_data.action = act

    prev = {}
    for group, keys in TIMELINE.items():
        for frame, pose in keys:
            P = POSES[pose]
            if group == "hips":
                offset, D = P["hips"]
                pb = rig.pose.bones["Root"]
                key_location(pb, offset, frame)
                prev["Root"] = key_rotation(pb, D, frame, prev.get("Root"))
            elif group == "torso":
                pb = rig.pose.bones["Waist"]
                prev["Waist"] = key_rotation(pb, P["Waist"], frame, prev.get("Waist"))
            else:
                for name in ARM_JOINTS:
                    pb = rig.pose.bones[name]
                    prev[name] = key_rotation(pb, P[name], frame, prev.get(name))

    for frame in range(FIRST, LAST + 1):
        key_legs(rig, frame, prev)

    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.nla.bake(frame_start=FIRST, frame_end=LAST, only_selected=True, visual_keying=False,
                     clear_constraints=False, use_current_action=True, bake_types={"POSE"})
    bpy.ops.pose.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    rig.animation_data.action.name = ACTION
    for name, frame in MARKERS.items():
        scene.timeline_markers.new(name, frame=frame)
    scene.frame_set(FIRST)


def torso_pitch(rig, frame):
    """Upper torso lean from vertical in degrees (+ = forward)."""
    bpy.context.scene.frame_set(frame)
    up = (rig.matrix_world.to_3x3() @ rig.pose.bones["Waist"].matrix.to_3x3() @ V((0, 1, 0)))
    return math.degrees(math.atan2(up.y, up.z))


rig = load_rig()
animate(rig)
os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
for f in (0, 4, 6, 12, 17, 22, 36):
    print(f"frame {f:2d}: torso lean {torso_pitch(rig, f):+5.1f} deg | knee bend L {KNEE_BEND[('Left', f)]:5.1f}"
          f"  R {KNEE_BEND[('Right', f)]:5.1f}")
bpy.context.scene.frame_set(0)
print("saved", OUT_BLEND, "| markers", MARKERS)

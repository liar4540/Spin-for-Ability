"""Spin for Abilities - Frost Jab: the punch animation, frames 0-13 @ 30 fps.

Run inside Blender with Game/assets/frost_jab.blend open (after build_frost_jab_rig.py):
    STAGE = "spline"; exec(open(r"<this file>").read())
STAGE "blocking" (stage 2): key poses only, CONSTANT interpolation, every joint keyed together.
STAGE "spline" (stage 3, the default): Bezier curves + overlap. Hips lead, the torso follows a frame
later, the arms + head a frame after that; the legs are solved on every frame from the hips.
Keys the action "FrostJab_Punch" on FrostJabRig, adds the "Hit" marker and saves the .blend.
Check it with check_frost_jab_anim.py.

Look: images/abilities/frost jab.png. The attacker faces the dummy and throws a right straight
(the near arm in the reference, which is shot from the attacker's right side):
    frame  pose        reference panel
      0    ready       1  F0  Idle         orthodox guard: left foot forward, fists at the chin
      2    windup      2  F2  Wind-Up      sinks and twists away, right fist cocked back by the ribs
      4    hit         3  F4  Impact       hips + shoulders whip round, right arm straight at the
                                           target, lunge onto the front leg, back heel up  <- "Hit"
      5    overshoot   4  F5  Shard Burst  body carries on a few degrees past the hit
      6    hold        5  F6  Frost Ring   settles back onto the hit line (2-frame hold after F4)
     10    recovery    7  F10 Recovery     arm comes back, weight shifting back
     13    ready       8  F13 Ready        same as frame 0
"Hit" is frame 4 (0.133 s; CONFIG says 0.15 s = frame 4.5): the hand is furthest forward there.
Frames in the table are the ARM keys; with overlap (spline) the groups key at:
    pose        hips  torso  arms+head
    ready         0     0      0
    pullback      -     -      1      breakdown: the fist swings out and back on a curve
    windup        2     2      2      full stop on every channel; anticipation -> hit: 2 frames (arm)
    hit         2.67  3.33     4      <- "Hit": the hand peaks
    overshoot   3.67  4.33     5
    hold          6     6      6      2-frame hold after the hit, then a slow ease out
    recovery      8     9     10
    ready      12-13   13     13

Axes and joint convention: same as build_gale_step_anim.py. +Y = forward, +X = the rig's right,
+Z = up. Each joint rotation is a delta D in the parent's frame with rest-aligned axes (the Roblox
joint Transform after the axis swap Roblox (x, y, z) -> Blender (x, -z, y)).
    Rx(+) swings a hanging arm/leg forward (and pitches a torso BACK), so a forward lean is Rx(-);
    Rx(+) on an elbow bends the forearm forward (the natural way).
    Rz(+) turns toward the rig's left. Ry(-) lifts the right arm out sideways, Ry(+) the left.
D = A @ B applies B first.

No root motion: the HumanoidRootPart bone never moves. The Root joint shifts / drops / twists the
body; both feet stay planted the whole time (exact 2-bone IK toward fixed ankle targets; the back
heel lifts by pivoting on its toe edge, so the toe never moves).
"""
import bpy, math, os
from mathutils import Matrix, Vector

OUT_BLEND = r"C:\Roblox\Spin for ability\Game\assets\frost_jab.blend"
RIG_NAME = "FrostJabRig"
ACTION = "FrostJab_Punch"
FPS, FIRST, LAST = 30, 0, 13
MARKERS = {"Hit": 4}
STOP_FRAMES = {2}  # spline: every body channel comes to a full stop here (the wind-up apex)
ANKLE_HEIGHT, FOOT_HALF_DEPTH = 0.262, 0.5
STAGE = globals().get("STAGE", "spline")


def Rx(d): return Matrix.Rotation(math.radians(d), 3, "X")
def Ry(d): return Matrix.Rotation(math.radians(d), 3, "Y")
def Rz(d): return Matrix.Rotation(math.radians(d), 3, "Z")
I = Matrix.Identity(3)
V = Vector


# --- key poses -----------------------------------------------------------------------------------
# hips: (Root offset in studs, Root rotation)   Waist: upper torso on the hips   Neck: head
POSES = {
    # orthodox guard: body turned 25 deg to the right, slight crouch, both fists up by the chin
    "ready": dict(hips=(V((0, 0, -0.30)), Rz(-25)), Waist=Rz(-5) @ Rx(-6), Neck=Rz(28) @ Rx(4),
                  RightShoulder=Rz(50) @ Ry(-20) @ Rx(40), RightElbow=Rx(105), RightWrist=I,
                  LeftShoulder=Rz(-25) @ Rx(30), LeftElbow=Rx(140), LeftWrist=I),
    # sink + twist away, right fist pulled back by the ribs, left guard reaching forward
    "windup": dict(hips=(V((0, -0.10, -0.44)), Rz(-40) @ Rx(-12)), Waist=Rz(-18) @ Rx(-12), Neck=Rz(55) @ Rx(18),
                   RightShoulder=Ry(-12) @ Rx(-10), RightElbow=Rx(125), RightWrist=I,
                   LeftShoulder=Rz(-20) @ Rx(70), LeftElbow=Rx(80), LeftWrist=I),
    # whip round: hips + chest square up past the target, right arm straight out at shoulder
    # height, lunge forward onto the front leg; left fist back to the chin
    "hit": dict(hips=(V((0, 0.30, -0.42)), Rz(18) @ Rx(-10)), Waist=Rz(14) @ Rx(-6), Neck=Rz(-30) @ Rx(14),
                RightShoulder=Rz(-18) @ Rx(95), RightElbow=Rx(8), RightWrist=I,
                LeftShoulder=Rz(-25) @ Rx(55), LeftElbow=Rx(120), LeftWrist=I),
    # overshoot: the body carries on a few degrees, the arm stays on its line (hand not further out)
    "overshoot": dict(hips=(V((0, 0.30, -0.45)), Rz(20) @ Rx(-12)), Waist=Rz(16) @ Rx(-7), Neck=Rz(-33) @ Rx(15),
                      RightShoulder=Rz(-12) @ Rx(89), RightElbow=Rx(22), RightWrist=I,
                      LeftShoulder=Rz(-25) @ Rx(52), LeftElbow=Rx(122), LeftWrist=I),
    # hold: settles back onto the hit line
    "hold": dict(hips=(V((0, 0.28, -0.42)), Rz(17) @ Rx(-10)), Waist=Rz(13) @ Rx(-6), Neck=Rz(-29) @ Rx(14),
                 RightShoulder=Rz(-18) @ Rx(94), RightElbow=Rx(12), RightWrist=I,
                 LeftShoulder=Rz(-25) @ Rx(55), LeftElbow=Rx(120), LeftWrist=I),
    # recovery: arm drawn halfway back, weight moving back over the middle
    "recovery": dict(hips=(V((0, 0.12, -0.36)), Rz(-8) @ Rx(-5)), Waist=Rz(-2) @ Rx(-6), Neck=Rz(10) @ Rx(8),
                     RightShoulder=Rz(30) @ Rx(58), RightElbow=Rx(70), RightWrist=I,
                     LeftShoulder=Rz(-15) @ Rx(60), LeftElbow=Rx(108), LeftWrist=I),
    # breakdown (arms only, spline stage): halfway into the wind-up the fist swings out and back
    "pullback": dict(Neck=Rz(42) @ Rx(10),
                     RightShoulder=Rz(20) @ Ry(-35) @ Rx(18), RightElbow=Rx(120), RightWrist=I,
                     LeftShoulder=Rz(-22) @ Rx(50), LeftElbow=Rx(110), LeftWrist=I),
}
POSES["ready_end"] = POSES["ready"]

ARM_JOINTS = ["Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist"]
KEYS = [(0, "ready"), (2, "windup"), (4, "hit"), (5, "overshoot"), (6, "hold"), (10, "recovery"), (13, "ready_end")]
if STAGE == "blocking":
    TIMELINE = {"hips": KEYS, "torso": KEYS, "arms": KEYS}  # every group keys together
else:
    TIMELINE = {
        # everything comes to a full stop at the wind-up apex (frame 2, STOP_FRAMES); an arm still
        # pulling back while the hips already drive forward makes a cusp in the fist's path. From the
        # stop the hips lead the strike, the torso follows 2/3 frame later, the arm 2/3 frame after that.
        "hips": [(0, "ready"), (2, "windup"), (8 / 3, "hit"), (11 / 3, "overshoot"), (6, "hold"),
                 (8, "recovery"), (12, "ready_end"), (13, "ready_end")],
        "torso": [(0, "ready"), (2, "windup"), (10 / 3, "hit"), (13 / 3, "overshoot"), (6, "hold"),
                  (9, "recovery"), (13, "ready_end")],
        # frame 1 is a breakdown: the fist swings out and back on a curve instead of a straight line
        "arms": [(0, "ready"), (1, "pullback"), (2, "windup"), (4, "hit"), (5, "overshoot"), (6, "hold"),
                 (10, "recovery"), (13, "ready_end")],
    }

# Feet: planted all the way. (frame, ankle position, heel lift in degrees). Heel lift pivots on the
# toe edge, so the toe stays put.
G = ANKLE_HEIGHT
FEET = {
    "Left": [(f, V((-0.55, 0.85, G)), 0) for f, _ in KEYS],  # front foot, flat
    # back foot: heel up on the punch, on the hips' timing
    "Right": [(f, V((0.62, -0.95, G)), lift) for f, lift in (
        ((0, 0), (2, 0), (4, 20), (5, 22), (6, 20), (10, 8), (13, 0)) if STAGE == "blocking" else
        ((0, 0), (2, 0), (8 / 3, 20), (11 / 3, 22), (6, 20), (8, 8), (12, 0), (13, 0)))],
}


def foot_at(side, frame):
    keys = FEET[side]
    if STAGE == "blocking":  # stepped, like the rest of the blocking: the last key at or before frame
        _, p, a = [k for k in keys if k[0] <= frame][-1]
        return p.copy(), a
    for (f0, p0, a0), (f1, p1, a1) in zip(keys, keys[1:]):
        if f0 <= frame <= f1:
            t = (frame - f0) / (f1 - f0)
            t = t * t * (3 - 2 * t)
            return p0.lerp(p1, t), a0 + (a1 - a0) * t
    _, p, a = keys[-1]
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
        ankle, lift = foot_at(side, frame)
        foot = Rx(-lift)
        if lift > 0:  # heel lift: pivot on the toe edge
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
        if d_vec.length > L1 + L2:
            print(f"WARNING frame {frame} {side} leg overstretched by {d_vec.length - L1 - L2:.3f}")
        for pb, D in ((hip, pelvis.inverted() @ W1), (knee, W1.inverted() @ W2), (ank, W2.inverted() @ foot)):
            prev[pb.name] = key_rotation(pb, D, frame, prev.get(pb.name))


def animate(rig):
    scene = bpy.context.scene
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
    rig.animation_data_create()
    old = rig.animation_data.action
    if old:
        rig.animation_data.action = None
        bpy.data.actions.remove(old)
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

    if STAGE != "blocking":
        # Full stop at the wind-up apex: flat handles on EVERY channel there. Auto-clamped handles only
        # flatten a channel at its own peak, so channels still moving through the apex made the hand
        # cusp (hard turn at speed) on the way into the punch. Done before the legs are solved.
        for fc in _fcurves(act):
            for kp in fc.keyframe_points:
                if round(kp.co.x) in STOP_FRAMES:
                    kp.handle_left_type = kp.handle_right_type = "FREE"
                    kp.handle_left = (kp.co.x - 0.33, kp.co.y)
                    kp.handle_right = (kp.co.x + 0.33, kp.co.y)
            fc.update()

    leg_frames =sorted({f for f, _ in KEYS}) if STAGE == "blocking" else range(FIRST, LAST + 1)
    for frame in leg_frames:
        key_legs(rig, frame, prev)

    bpy.ops.object.mode_set(mode="OBJECT")
    if STAGE == "blocking":
        for fc in _fcurves(act):
            for kp in fc.keyframe_points:
                kp.interpolation = "CONSTANT"
    for m in list(scene.timeline_markers):
        scene.timeline_markers.remove(m)
    for name, frame in MARKERS.items():
        scene.timeline_markers.new(name, frame=frame)
    scene.frame_start, scene.frame_end = FIRST, LAST
    scene.frame_set(FIRST)


def _fcurves(act):
    """Action F-curves (Blender 5 keeps them in layers/strips/channelbags)."""
    if hasattr(act, "fcurves") and len(act.fcurves):
        return list(act.fcurves)
    out = []
    for layer in getattr(act, "layers", []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                out.extend(bag.fcurves)
    return out


rig = bpy.data.objects[RIG_NAME]
animate(rig)
os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
for f, pose in KEYS:
    bpy.context.scene.frame_set(f)
    hands = "  ".join(f"{s[0]} hand ({h.x:+.2f}, {h.y:+.2f}, {h.z:+.2f})" for s in ("Right", "Left")
                      for h in [bpy.data.objects[s + "Hand"].matrix_world.translation])
    print(f"frame {f:2d} {pose:10s} knee bend L {KNEE_BEND.get(('Left', f), 0):5.1f}  R {KNEE_BEND.get(('Right', f), 0):5.1f}  {hands}")
bpy.context.scene.frame_set(FIRST)
print("saved", OUT_BLEND, "| stage", STAGE, "| markers", MARKERS)

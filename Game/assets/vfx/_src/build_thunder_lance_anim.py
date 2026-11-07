"""Spin for Abilities - Thunder Lance: the overhand spear throw, frames 0-30 @ 30 fps.

Run inside Blender with Game/assets/thunder_lance.blend open (after build_thunder_lance_rig.py):
    STAGE = "blocking"; exec(open(r"<this file>").read())
STAGE "blocking" (stage 2): key poses only, CONSTANT interpolation, every joint keyed together.
STAGE "spline" (stage 3): Bezier curves + overlap (added in stage 3).
Keys the action "ThunderLance_Throw" on ThunderLanceRig, adds the "Summon" (F4) and "Release" (F15)
markers, keys the stand-in spear "TL_SpearStandIn" and saves the .blend.

Plan: Prompts/thunder_lance_prompt section 4 + images/abilities/thunder_lance_blueprint.png panel 1.
Right-handed javelin throw, target straight ahead (+Y), 40 studs out. No root motion.
    F0  ready      F4  summon (hand to chest, palm up)   F8  spear formed (hand at shoulder)
    F12 wind-up    F13 hold (hips start, front foot plants)   F14 whip (elbow high, torso tilts left)
    F15 release    F18 follow-through   F24 settle   F30 ready (= F0)

Axes and joint convention: same as build_frost_jab_anim.py. +Y = forward, +X = the rig's right,
+Z = up. Each joint rotation is a delta D in the parent's frame with rest-aligned axes.
    Rz(+) turns toward the rig's left (so "away from the target" for a right-hander is Rz(-)).
    Rx(-) leans forward. Ry(-) tilts the top toward the rig's left.
Arms are posed in CHARACTER space (world directions or wrist targets), then converted to joint deltas
through the torso's rotation, so "pointing at the target" means exactly that whatever the hips do.

Spear stand-in: a 6-stud lance (0.35 thick), grip point 2 studs from the tail. Its position follows
the RightHand part (welded); its direction is the aim (the VFX code does the same: grip welded to the
hand, axis along the aim), so the spear points at the target from F8 to F15 whatever the wrist does.
"""
import bpy, bmesh, math, os
from mathutils import Matrix, Vector, Quaternion

OUT_BLEND = r"C:\Roblox\Spin for ability\Game\assets\thunder_lance.blend"
RIG_NAME = "ThunderLanceRig"
ACTION = "ThunderLance_Throw"
SPEAR = "TL_SpearStandIn"
FPS, FIRST, LAST = 30, 0, 30
MARKERS = {"Summon": 4, "Release": 15}
ANKLE_HEIGHT, FOOT_HALF_DEPTH = 0.262, 0.5
SPEAR_LEN, SPEAR_THICK, SPEAR_GRIP_FROM_TAIL = 6.0, 0.35, 2.0
TARGET = Vector((0, 40, 3.4))  # the dummy's chest, 40 studs ahead (blueprint panel 3)
EYE_Z = 4.87
STAGE = globals().get("STAGE", "blocking")

# rest joint positions (Blender axes, from build_thunder_lance_rig.py)
ROOT_P = Vector((0, 0, 2.1924))
WAIST_P = Vector((0, 0, 2.5930))
SHOULDER_P = {"Right": Vector((0.9716, 0, 4.0395)), "Left": Vector((-0.9716, 0, 4.0395))}
UPPER_LEN, FORE_LEN = 0.774, 0.8069  # shoulder->elbow, elbow->wrist


def Rx(d): return Matrix.Rotation(math.radians(d), 3, "X")
def Ry(d): return Matrix.Rotation(math.radians(d), 3, "Y")
def Rz(d): return Matrix.Rotation(math.radians(d), 3, "Z")
I = Matrix.Identity(3)
V = Vector


def unit(*v): return V(v).normalized()


# --- key poses -----------------------------------------------------------------------------------
# hips: (Root offset, Root rotation). waist: upper torso on the hips. head: head pitch in WORLD
# (the neck cancels the torso turn so the eyes stay on the target).
# Arms, one of:
#   ("dir", upper-arm direction, elbow bend deg, twist deg)   natural swing from hanging + twist
#   ("ik", wrist target, elbow pole)                          2-bone IK in character space
#   ("ikrel", wrist offset from the shoulder joint, elbow pole) the same, relative to the shoulder
# wrist: (twist about the forearm deg (+ = palm up), flex deg).
# feet: side -> (ankle position, heel lift deg, yaw deg). Knee bend = 2 x acos(hip-to-ankle / 1.93).
G = ANKLE_HEIGHT
FEET_READY = {"Left": (V((-0.5, 0, G)), 0, 0), "Right": (V((0.5, 0, G)), 0, 0)}
POSES = {
    # feet shoulder-width, knees 10, arms relaxed with the elbows 20
    "ready": dict(
        hips=(V((0, 0, -0.008)), I), waist=I, head=0,
        Right=("dir", unit(0.1, 0.03, -1), 20, 0), RightWrist=(0, 0),
        Left=("dir", unit(-0.1, 0.03, -1), 20, 0), LeftWrist=(0, 0),
        feet=FEET_READY),
    # "Summon": right hand up to chest height in front, palm up, elbow 90
    "summon": dict(
        hips=(V((0, 0, -0.008)), I), waist=I, head=-4,
        Right=("dir", unit(0.02, 0.12, -1), 90, -18), RightWrist=(90, 0),
        Left=("dir", unit(-0.1, 0.03, -1), 20, 0), LeftWrist=(0, 0),
        feet=FEET_READY),
    # spear formed: hips 20 away, chest 30 away, hand at shoulder height beside the head, the spear
    # level; left arm starts rising forward; weight starting back
    "formed": dict(
        hips=(V((0, -0.12, -0.05)), Rz(-20)), waist=Rz(-10), head=0,
        Right=("ik", V((1.75, -0.75, 4.05)), V((0.3, -0.3, -1))), RightWrist=(90, 0),
        Left=("dir", unit(-0.05, 0.6, -0.8), 25, 0), LeftWrist=(0, 0),
        feet={"Left": (V((-0.5, 0, G)), 0, 0), "Right": (V((0.5, 0, G)), 0, 0)}),
    # wind-up peak: hips 40 away, chest 60 away (20 deg separation), right arm long and straight
    # behind at shoulder height (elbow 12), left arm points at the target, weight 70% back on the
    # bent right leg (knee 30), left foot in the air stepping forward
    "windup": dict(
        hips=(V((0.1, -0.35, -0.2)), Rz(-40)), waist=Rz(-20), head=0,
        Right=("dir", unit(0.32, -1, 0.2), 12, 0), RightWrist=(90, 0),
        Left=("dir", V((0, 1, 0.02)), 0, 0), LeftWrist=(0, 0),
        feet={"Left": (V((-0.45, 0.6, G + 0.3)), 0, 0), "Right": (V((0.5, 0, G)), 0, 0)}),
    # hold: hips start back toward the target (+15), chest stays back (stretch), front foot plants
    # with the knee nearly straight
    "hold": dict(
        hips=(V((0.05, 0.08, -0.235)), Rz(-25)), waist=Rz(-35), head=0,
        Right=("dir", unit(0.32, -1, 0.2), 12, 0), RightWrist=(90, 0),
        Left=("dir", V((0, 1, 0.02)), 0, 0), LeftWrist=(0, 0),
        feet={"Left": (V((-0.45, 1.15, G)), 0, 0), "Right": (V((0.5, 0, G)), 0, 0)}),
    # whip: hips square, shoulders start round, torso tilts 15 to the left (away from the throwing
    # arm); elbow forward and HIGH above the shoulder, hand still back behind it; left arm pulls
    # down toward the hip; weight onto the front leg
    "whip": dict(
        hips=(V((0, 0.3, -0.235)), I), waist=Rz(-25) @ Ry(-15), head=0,
        Right=("ikrel", V((0.35, -0.85, 0.66)), V((0.3, 1, 0.5))), RightWrist=(90, 0),
        Left=("ik", V((-1.25, 0.3, 2.9)), V((-0.6, -1, 0))), LeftWrist=(0, 0),
        feet={"Left": (V((-0.45, 1.15, G)), 0, 0), "Right": (V((0.5, 0, G)), 12, 0)}),
    # release: hips 20 past square, shoulders square and chest pushed forward, arm fully extended
    # forward and 30 up over the top of the shoulder, hand open; front leg braced, back heel up
    "release": dict(
        hips=(V((0, 0.5, -0.195)), Rz(20) @ Rx(-6)), waist=Rz(-20) @ Ry(-8) @ Rx(-20), head=0,
        Right=("dir", unit(-0.12, math.cos(math.radians(30)), math.sin(math.radians(30))), 0, 0),
        RightWrist=(0, 0),
        Left=("ik", V((-1.05, -0.05, 2.6)), V((-0.5, -1, 0))), LeftWrist=(0, 0),
        feet={"Left": (V((-0.45, 1.15, G)), 0, 0), "Right": (V((0.5, 0, G)), 35, 0)}),
    # overshoot (spline only): a beat after the release everything carries a little past it, then
    # settles into the follow-through
    "overshoot": dict(
        hips=(V((0, 0.55, -0.19)), Rz(26) @ Rx(-8)), waist=Rz(-20) @ Ry(-8) @ Rx(-25), head=4,
        Right=("dir", unit(-0.16, math.cos(math.radians(22)), math.sin(math.radians(22))), 4, 0),
        RightWrist=(0, 0),
        Left=("ik", V((-1.05, -0.2, 2.55)), V((-0.5, -1, 0))), LeftWrist=(0, 0),
        feet={"Left": (V((-0.45, 1.15, G)), 0, 0), "Right": (V((0.5, 0, G)), 42, 0)}),
    # follow-through: hips 30 past square, leaning 30 forward, arm swept down and across toward the
    # left knee, left arm behind the hip, back leg swings forward with the toes dragging
    "follow": dict(
        hips=(V((-0.05, 0.62, -0.24)), Rz(30) @ Rx(-10)), waist=Rz(-5) @ Rx(-22), head=12,
        Right=("ik", V((-0.4, 1.6, 2.15)), V((0.6, 0.2, 1))), RightWrist=(0, 0),
        Left=("ik", V((-1.05, -0.5, 2.5)), V((-0.3, -1, 0.3))), LeftWrist=(0, 0),
        feet={"Left": (V((-0.45, 1.15, G)), 0, 0), "Right": (V((0.4, 0.05, G)), 60, 0)}),
    # settle: back toward square, leaning 10 forward, arms up to guard, back foot down, knees 15
    "settle": dict(
        hips=(V((0, 0.55, -0.16)), Rz(8)), waist=Rz(-4) @ Rx(-8), head=4,
        Right=("ik", V((0.5, 1.35, 3.5)), V((1, 0, -0.6))), RightWrist=(0, 0),
        Left=("ik", V((-0.5, 1.45, 3.55)), V((-1, 0, -0.6))), LeftWrist=(0, 0),
        feet={"Left": (V((-0.45, 1.15, G)), 0, 0), "Right": (V((0.5, 0, G)), 0, 0)}),
}
POSES["ready_end"] = POSES["ready"]
# breakdown (arms only, spline): halfway through the draw-back the hand stays at shoulder height and
# swings out and back on a level arc (without it the hand dips 0.6 studs between F8 and F12)
POSES["drawback"] = dict(POSES["windup"],
                         Right=("ik", V((1.85, -1.45, 4.15)), V((0.4, 0.2, -1))), RightWrist=(90, 0),
                         Left=("dir", unit(-0.03, 0.85, -0.4), 15, 0))
KEYS = [(0, "ready"), (4, "summon"), (8, "formed"), (12, "windup"), (13, "hold"), (14, "whip"),
        (15, "release"), (18, "follow"), (24, "settle"), (30, "ready_end")]
# Spline timing (stage 3): the throw is a whip, so each link starts and arrives before the next one.
# The arm group (elbows, wrists) arrives at the release on the plan's frame (Release = F15 = the
# hand's fastest frame); the shoulders get there half a frame earlier, the torso a frame before the
# arm, the hips a frame before the torso. The elbow folds WITH the shoulder on the whip (F13.67, the
# hand stays back while the upper arm comes forward), holds folded to F14.25, then snaps straight
# into F15, so the hand is fastest on the Release frame. Each
# group comes to a full stop at its own wind-up peak (STOP), so the hand path has no cusp. After the
# release the shoulders move with the arm, so the arm eases down instead of dropping.
TIMELINE = {
    "hips": [(0, "ready"), (4, "summon"), (8, "formed"), (10.5, "windup"), (12, "hold"), (12.67, "whip"),
             (13.33, "release"), (14.33, "overshoot"), (16, "follow"), (22, "settle"), (24.5, "settle"), (29, "ready_end"), (30, "ready_end")],
    "torso": [(0, "ready"), (4, "summon"), (8, "formed"), (11, "windup"), (12, "windup"), (12.67, "hold"), (13.33, "whip"),
              (14, "release"), (15, "overshoot"), (17, "follow"), (23, "settle"), (30, "ready_end")],
    "shoulders": [(0, "ready"), (4, "summon"), (8, "formed"), (10, "drawback"), (12, "windup"), (13, "hold"), (14, "whip"),
                  (14.85, "release"), (16, "overshoot"), (18, "follow"), (24, "settle"), (30, "ready_end")],
    "arms": [(0, "ready"), (4, "summon"), (8, "formed"), (10, "drawback"), (12, "windup"), (13, "hold"), (13.67, "whip"),
             (14.25, "whip"), (15, "release"), (16, "overshoot"), (18, "follow"), (24, "settle"), (30, "ready_end")],
}
STOP = {"hips": 10.5, "torso": 12, "shoulders": 12, "arms": 12}
# The throwing hand F8-F24 (spline stage): a designed WORLD path for the right wrist, solved with arm
# IK every 0.1 frame. Interpolating separate shoulder and elbow keys while the chest
# turns underneath made the hand dip and cusp around the wind-up; a path can't. Cubic Hermite through
# the points; velocity None = Catmull-Rom, (0,0,0) = full stop (the wind-up peak). The release (F15)
# keeps forward speed so the hand is still fast there, overshoots a little and settles back by F16.
# (frame, wrist position, elbow pole, wrist velocity per frame or None)
RIGHT_PATH = [
    (8, V((1.75, -0.75, 4.05)), V((0.3, -0.3, -1)), None),          # spear formed, hand beside the head
    (10, V((1.78, -1.5, 4.1)), V((0.4, 0.0, -1)), None),            # drawn back level
    (12, V((1.53, -2.11, 4.09)), V((0.2, 0.2, -1)), V((0, 0, 0))),  # wind-up peak: full stop, elbow 10-15
    (13, V((1.45, -1.38, 4.22)), V((0.2, 0.3, -1)), None),          # hold: carried by the chest
    (14, V((1.05, 0.38, 4.55)), V((0.3, 1, 0.5)), V((-0.3, 0.6, 0.3))),  # whip: elbow high, hand back above it
    # RELEASE: the arm is nearly straight and the hand still at full speed (a javelin leaves the hand
    # just before the arm locks out); full extension comes a frame later, with a small overshoot
    (15, V((0.88, 2.85, 4.48)), V((1, 0, -0.3)), V((-0.15, 2.3, -0.5))),  # elbow out and a little down
    (16, V((0.68, 3.3, 3.9)), V((1, 0, -0.3)), V((-0.25, 0.0, -1.0))),  # full extension, curving down
    (18, V((0.14, 1.67, 2.07)), V((0.6, 0.2, 1)), None),            # follow-through toward the left knee
    (24, V((0.5, 1.35, 3.5)), V((1, 0, -0.6)), V((0, 0, 0))),       # guard
]
RIGHT_PATH_RANGE = (RIGHT_PATH[0][0], RIGHT_PATH[-1][0])
NOTE_FRAME = None  # for the out-of-reach notes


def right_path(frame):
    """(wrist position, pole) on RIGHT_PATH at a frame."""
    pts = RIGHT_PATH
    vel = []
    for i, (f, p, _, v) in enumerate(pts):
        if v is not None:
            vel.append(v)
        elif 0 < i < len(pts) - 1:
            vel.append((pts[i + 1][1] - pts[i - 1][1]) / (pts[i + 1][0] - pts[i - 1][0]))
        else:
            j = 1 if i == 0 else i - 1
            k = 0 if i == 0 else i
            vel.append((pts[max(j, k)][1] - pts[min(j, k)][1]) / (pts[max(j, k)][0] - pts[min(j, k)][0]))
    for i in range(len(pts) - 1):
        f0, p0, q0, _ = pts[i]
        f1, p1, q1, _ = pts[i + 1]
        if f0 <= frame <= f1:
            h = f1 - f0
            t = (frame - f0) / h
            h00, h10 = 2 * t ** 3 - 3 * t ** 2 + 1, t ** 3 - 2 * t ** 2 + t
            h01, h11 = -2 * t ** 3 + 3 * t ** 2, t ** 3 - t ** 2
            pos = h00 * p0 + h10 * h * vel[i] + h01 * p1 + h11 * h * vel[i + 1]
            return pos, q0.normalized().lerp(q1.normalized(), t * t * (3 - 2 * t))
    return pts[-1][1], pts[-1][2]


def right_wrist_twist(frame):
    """Palm up while carrying the spear, turning to neutral over the release (F14.25 -> F15)."""
    if frame <= 14.25:
        return 90.0
    if frame >= 15:
        return 0.0
    t = (frame - 14.25) / 0.75
    return 90.0 * (1 - t * t * (3 - 2 * t))
if STAGE == "blocking":
    TIMELINE = {g: KEYS for g in TIMELINE}
# Feet keep the plan's frames: the front foot plants on F13, the back heel peels up F13-F15, the
# back toes drag forward to F18, then the front foot steps back to the ready stance (lifted, F24-F29).
FEET_KEYS = [(f, POSES[p]["feet"]) for f, p in KEYS]
if STAGE != "blocking":
    FEET_KEYS += [(16, POSES["overshoot"]["feet"]),
                  (27, {"Left": (V((-0.47, 0.6, G + 0.22)), 0, 0), "Right": (V((0.5, 0, G)), 0, 0)}),
                  (29, FEET_READY)]
    FEET_KEYS.sort(key=lambda k: k[0])
# spear visible from F8 (the VFX grows it over F8-F12) until the release; the stand-in shows it whole
SPEAR_FRAMES = {8, 12, 13, 14, 15} if STAGE == "blocking" else set(range(8, 16))


# --- character-space helpers ---------------------------------------------------------------------
def hips_xf(P):
    off, Rr = P["hips"]
    return off, Rr


def torso_rot(P):
    return P["hips"][1] @ P["waist"]


def shoulder_world(P, side):
    off, Rr = P["hips"]
    waist = ROOT_P + off + Rr @ (WAIST_P - ROOT_P)
    return waist + torso_rot(P) @ (SHOULDER_P[side] - WAIST_P)


def seg_frame(d, front):
    """World rotation of a limb segment pointing along d with its front (+Y) toward `front`.
    Rest: points -Z, front +Y (identity)."""
    z = -d.normalized()
    f = front - front.dot(d.normalized()) * d.normalized()
    if f.length < 1e-4:
        f = V((0, 0, 1)) if abs(d.normalized().z) < 0.9 else V((0, 1, 0))
    y = f.normalized()
    x = y.cross(z).normalized()
    return Matrix((x, y, z)).transposed()


def swing(d, twist=0.0):
    """Rotation taking the hanging arm (-Z) to d by the shortest swing (no hidden twist: the arm's
    outer side stays outward), then `twist` degrees about d."""
    q = V((0, 0, -1)).rotation_difference(d.normalized())
    return Matrix.Rotation(math.radians(twist), 3, d.normalized()) @ q.to_matrix()


# The R15 elbow sits 0.5 studs OUTSIDE the shoulder joint (rest upper-arm offset (+-0.5, 0, -0.774));
# the forearm hangs straight down from the elbow. The arm's visual axis is the part's -Z.
def elbow_offset(side):
    return V((0.5 if side == "Right" else -0.5, 0, -UPPER_LEN))


def arm_frames(P, side, S=None, soft=0.95):
    """World rotations of the upper arm and forearm. The elbow is a pure hinge: the forearm is the
    upper arm rotated about its own X, so the bend is Rx(+) (toward the arm's front) in the joint.
    ("dir", u, bend, twist): upper arm's visual axis along u, natural swing + twist, elbow bend.
    ("ik", wrist target, pole): solved for the wrist, elbow toward the pole, offset elbow included."""
    spec = P[side]
    if spec[0] == "dir":
        _, u, bend, twist = spec
        return swing(u, twist), swing(u, twist) @ Rx(bend), bend
    kind, target, pole = spec
    S = S if S is not None else shoulder_world(P, side)
    if kind == "ikrel":  # target given relative to the shoulder joint (follows the chest)
        target = S + target
    Wu = swing(V((0, 0, -1)))
    bend = 0.0
    for _ in range(8):  # the elbow's sideways offset depends on the solution: iterate
        S2 = S + Wu @ V((elbow_offset(side).x, 0, 0))
        d_vec = target - S2
        # soft reach limit: past `soft` of full reach the distance eases into 99.9% (smooth), instead of
        # clamping hard, which put a corner in the hand path whenever a target left and re-entered reach
        reach, knee = 0.999 * (UPPER_LEN + FORE_LEN), soft * (UPPER_LEN + FORE_LEN)
        d = d_vec.length if d_vec.length <= knee else knee + (reach - knee) * math.tanh((d_vec.length - knee) / (reach - knee))
        uu = d_vec.normalized()
        a = math.acos(max(-1.0, min(1.0, (UPPER_LEN ** 2 + d * d - FORE_LEN ** 2) / (2 * UPPER_LEN * d))))
        w = (pole - pole.dot(uu) * uu).normalized()
        elbow = S2 + UPPER_LEN * (math.cos(a) * uu + math.sin(a) * w)
        u = (elbow - S2).normalized()
        v = (S2 + d * uu - elbow).normalized()
        bend = math.degrees(u.angle(v))
        # the side the forearm bends toward, from the triangle's angle (stable even when the arm is
        # nearly straight; taking it from v - u flips the upper arm's twist near full reach)
        Wu = seg_frame(u, math.sin(a) * uu - math.cos(a) * w)
    if d_vec.length > UPPER_LEN + FORE_LEN:
        print(f"  note: {side} wrist target {d_vec.length - UPPER_LEN - FORE_LEN:.2f} studs out of reach"
              f"{'' if NOTE_FRAME is None else f' (frame {NOTE_FRAME})'}")
    return Wu, Wu @ Rx(bend), bend


# --- keying --------------------------------------------------------------------------------------
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
    z = -down.normalized()
    y = down.normalized().cross(n).normalized()
    x = y.cross(z).normalized()
    return Matrix((x, y, z)).transposed()


BENDS = {}


def set_frame(frame):
    whole = math.floor(frame)
    bpy.context.scene.frame_set(whole, subframe=frame - whole)


def key_group(rig, group, frame, P, prev):
    """Keys one group of joints for pose P. Arms are posed in WORLD space: shoulder keys are made
    against the torso's actual (evaluated) rotation at that frame (and torso keys against the hips'), so when the hips and torso lead,
    the arm really stays back (the stretch) instead of being carried round with the chest.
    Groups must be keyed in TIMELINE order: hips, torso, then shoulders, then arms."""
    joints = []
    if group == "hips":
        off, Rr = P["hips"]
        key_location(rig.pose.bones["Root"], off, frame)
        joints.append(("Root", Rr))
    elif group == "torso":
        # the chest is posed in WORLD space too: its key is made against the hips' real rotation, so
        # while the hips lead, a held chest really holds (the hip-shoulder stretch)
        set_frame(frame)
        root = rig.pose.bones["Root"]
        hips_now = root.matrix.to_3x3() @ rest_rot(root).inverted()
        joints += [("Waist", hips_now.inverted() @ torso_rot(P)), ("Neck", torso_rot(P).inverted() @ Rx(-P["head"]))]
    else:
        set_frame(frame)
        waist = rig.pose.bones["Waist"]
        T = waist.matrix.to_3x3() @ rest_rot(waist).inverted()  # the chest's real rotation now
        for side in ("Right", "Left"):
            if side == "Right" and STAGE != "blocking" and RIGHT_PATH_RANGE[0] < frame < RIGHT_PATH_RANGE[1]:
                continue  # the throwing arm follows RIGHT_PATH here (key_right_arm)
            S = rig.matrix_world @ rig.pose.bones[side + "Shoulder"].head
            Wu, Wf, bend = arm_frames(P, side, S)
            twist, flex = P[side + "Wrist"]
            sign = 1 if side == "Right" else -1  # + twist turns the palm up on either hand
            Wh = Wf @ Rz(-sign * twist) @ Rx(flex)
            if group == "shoulders":
                joints.append((side + "Shoulder", T.inverted() @ Wu))
            else:
                BENDS[(side + "Elbow", frame)] = bend
                joints += [(side + "Elbow", Wu.inverted() @ Wf), (side + "Wrist", Wf.inverted() @ Wh)]
    for name, D in joints:
        prev[name] = key_rotation(rig.pose.bones[name], D, frame, prev.get(name))


def key_right_arm(rig, frame, prev):
    """Right arm on RIGHT_PATH: IK from the chest's real shoulder position to the path's wrist point."""
    global NOTE_FRAME
    NOTE_FRAME = frame
    set_frame(frame)
    waist = rig.pose.bones["Waist"]
    T = waist.matrix.to_3x3() @ rest_rot(waist).inverted()
    S = rig.matrix_world @ rig.pose.bones["RightShoulder"].head
    target, pole = right_path(frame)
    # the release swing (F14-F17) sweeps past full reach fast: a softer limit keeps its path smooth;
    # elsewhere the firmer one lets the wind-up arm straighten to 10-15 deg
    soft = 0.92 if 14 <= frame <= 17 else 0.95
    Wu, Wf, bend = arm_frames({"Right": ("ik", target, pole)}, "Right", S, soft)
    Wh = Wf @ Rz(-right_wrist_twist(frame))
    BENDS[("RightElbow", frame)] = bend
    for name, D in (("RightShoulder", T.inverted() @ Wu), ("RightElbow", Wu.inverted() @ Wf),
                    ("RightWrist", Wf.inverted() @ Wh)):
        prev[name] = key_rotation(rig.pose.bones[name], D, frame, prev.get(name))


def foot_at(side, frame):
    """Ankle target, heel lift and yaw at a frame: stepped in blocking, smoothstep between keys."""
    keys = [(f, feet[side]) for f, feet in FEET_KEYS]
    if STAGE == "blocking":
        return [k for f, k in keys if f <= frame][-1]
    for (f0, (p0, l0, y0)), (f1, (p1, l1, y1)) in zip(keys, keys[1:]):
        if f0 <= frame <= f1:
            t = (frame - f0) / (f1 - f0)
            t = t * t * (3 - 2 * t)
            return p0.lerp(p1, t), l0 + (l1 - l0) * t, y0 + (y1 - y0) * t
    return keys[-1][1]


def key_legs(rig, frame, prev):
    """Exact 2-bone IK toward the ankle target; knees bend toward the pelvis' front."""
    set_frame(frame)
    root = rig.pose.bones["Root"]
    pelvis = root.matrix.to_3x3() @ rest_rot(root).inverted()
    for side in ("Left", "Right"):
        ankle, lift, yaw = foot_at(side, frame)
        out = 1 if side == "Right" else -1
        ankle = ankle.copy()
        foot = Rz(yaw) @ Rx(-lift)
        if lift > 0:  # heel lift: pivot on the toe edge, so the toe stays put
            toe = ankle + Rz(yaw) @ V((0, FOOT_HALF_DEPTH, -ANKLE_HEIGHT))
            ankle = toe + Rz(yaw) @ Rx(-lift) @ Rz(-yaw) @ (ankle - toe)
        hip, knee, ank = (rig.pose.bones[f"{side}{j}"] for j in ("Hip", "Knee", "Ankle"))
        L1, L2 = bone_len(rig, f"{side}Hip"), bone_len(rig, f"{side}Knee")
        H = rig.matrix_world @ hip.head
        d_vec = ankle - H
        d = min(d_vec.length, 0.999 * (L1 + L2))
        u = d_vec.normalized()
        a = math.acos(max(-1.0, min(1.0, (L1 * L1 + d * d - L2 * L2) / (2 * L1 * d))))
        fwd = pelvis @ V((0.15 * out, 1, 0)) + Rz(yaw) @ V((0.15 * out, 1, 0))
        w = (fwd - fwd.dot(u) * u).normalized()
        K = H + L1 * (math.cos(a) * u + math.sin(a) * w)
        A = H + d * u
        t1, t2 = (K - H).normalized(), (A - K).normalized()
        n = t1.cross(t2).normalized()
        if n.length < 0.5:  # straight leg: any plane that contains the foot's forward
            n = (pelvis @ V((1, 0, 0))).normalized()
        W1, W2 = leg_frame(t1, n), leg_frame(t2, n)
        BENDS[(side + "Knee", frame)] = math.degrees(t1.angle(t2))
        if d_vec.length > L1 + L2 + 0.002:
            print(f"WARNING frame {frame} {side} leg overstretched by {d_vec.length - L1 - L2:.3f}")
        for pb, D in ((hip, pelvis.inverted() @ W1), (knee, W1.inverted() @ W2), (ank, W2.inverted() @ foot)):
            prev[pb.name] = key_rotation(pb, D, frame, prev.get(pb.name))


# --- spear stand-in ------------------------------------------------------------------------------
def spear_mesh():
    """Diamond-tipped lance along +Y, grip point (origin) SPEAR_GRIP_FROM_TAIL from the tail."""
    me = bpy.data.meshes.get(SPEAR) or bpy.data.meshes.new(SPEAR)
    bm = bmesh.new()
    r = SPEAR_THICK / 2
    tail, tip = -SPEAR_GRIP_FROM_TAIL, SPEAR_LEN - SPEAR_GRIP_FROM_TAIL
    rings = [(tail, 0.02), (tail + 0.6, r * 0.7), (tip - 1.4, r), (tip - 1.1, r * 1.5), (tip, 0.0)]
    verts = []
    for y, rad in rings:
        verts.append([bm.verts.new((rad * math.cos(a), y, rad * math.sin(a))) for a in
                      (i * math.pi / 2 for i in range(4))])
    for a, b in zip(verts, verts[1:]):
        for i in range(4):
            bm.faces.new((a[i], a[(i + 1) % 4], b[(i + 1) % 4], b[i]))
    bm.to_mesh(me)
    bm.free()
    return me


def spear_object():
    ob = bpy.data.objects.get(SPEAR)
    if not ob:
        ob = bpy.data.objects.new(SPEAR, spear_mesh())
        bpy.context.scene.collection.objects.link(ob)
    else:
        spear_mesh()
    mat = bpy.data.materials.get("TL_Spear") or bpy.data.materials.new("TL_Spear")
    mat.diffuse_color = (1.0, 0.88, 0.3, 1)
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    ob.animation_data_clear()
    for c in list(ob.constraints):
        ob.constraints.remove(c)
    # welded to the hand: the grip follows the RightHand part's centre
    c = ob.constraints.new("COPY_LOCATION")
    c.target = bpy.data.objects["RightHand"]
    ob.rotation_mode = "QUATERNION"
    return ob


def spear_direction(frame, grip):
    """Level at F8, tip at eye level F12-F13 (the plan), straight at the target from F14; blended
    in between."""
    flat = TARGET - grip
    flat.z = 0
    flat = flat.normalized()
    rise = EYE_Z - grip.z
    run = math.sqrt(max(0.01, (SPEAR_LEN - SPEAR_GRIP_FROM_TAIL) ** 2 - rise ** 2))
    eye = (flat * run + V((0, 0, rise))).normalized()
    at = (TARGET - grip).normalized()
    if frame <= 8:
        return flat
    if frame < 12:
        return flat.lerp(eye, (frame - 8) / 4).normalized()
    if frame <= 13:
        return eye
    if frame < 14:
        return eye.lerp(at, frame - 13).normalized()
    return at


def key_spear(ob, frame):
    sc = bpy.context.scene
    sc.frame_set(frame)
    grip = bpy.data.objects["RightHand"].matrix_world.translation.copy()
    show = frame in SPEAR_FRAMES
    d = spear_direction(frame, grip)
    ob.rotation_quaternion = V((0, 1, 0)).rotation_difference(d)
    ob.keyframe_insert("rotation_quaternion", frame=frame)
    ob.scale = (1, 1, 1) if show else (0.001, 0.001, 0.001)
    ob.keyframe_insert("scale", frame=frame)
    ob.hide_render = not show
    ob.keyframe_insert("hide_render", frame=frame)


# --- main ----------------------------------------------------------------------------------------
def _fcurves(act):
    if hasattr(act, "fcurves") and len(act.fcurves):
        return list(act.fcurves)
    out = []
    for layer in getattr(act, "layers", []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                out.extend(bag.fcurves)
    return out


def quat_continuity(act):
    """Keys are made group by group, not in time order, so neighbouring quaternion keys can have
    opposite signs (same rotation, but interpolation then spins the long way round). Flip keys so each
    bone's quaternion stays on the same side as the key before it in time."""
    by_bone = {}
    for fc in _fcurves(act):
        if fc.data_path.endswith("rotation_quaternion"):
            by_bone.setdefault(fc.data_path, {})[fc.array_index] = fc
    for path, fcs in by_bone.items():
        if len(fcs) != 4:
            continue
        frames = sorted({round(kp.co.x, 4) for kp in fcs[0].keyframe_points})
        kps = {i: {round(kp.co.x, 4): kp for kp in fcs[i].keyframe_points} for i in range(4)}
        prev = None
        for f in frames:
            if not all(f in kps[i] for i in range(4)):
                continue
            q = [kps[i][f].co.y for i in range(4)]
            if prev is not None and sum(a * b for a, b in zip(q, prev)) < 0:
                for i in range(4):
                    kp = kps[i][f]
                    kp.co.y, kp.handle_left.y, kp.handle_right.y = -kp.co.y, -kp.handle_left.y, -kp.handle_right.y
                q = [-x for x in q]
            prev = q
        for fc in fcs.values():
            fc.update()


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
            key_group(rig, group, frame, POSES[pose], prev)
    if STAGE != "blocking":
        # full stop at each group's wind-up peak: flat handles on its channels there (auto-clamped
        # handles only flatten a channel at its own extreme; one still moving makes a cusp)
        stop_of = {}
        for group, names in (("hips", ["Root"]), ("torso", ["Waist", "Neck"]),
                             ("shoulders", ["RightShoulder", "LeftShoulder"]),
                             ("arms", ["RightElbow", "RightWrist", "LeftElbow", "LeftWrist"])):
            for n in names:
                stop_of[n] = STOP[group]
        for fc in _fcurves(act):
            bone = fc.data_path.split('"')[1] if '"' in fc.data_path else ""
            if bone not in stop_of:
                continue
            for kp in fc.keyframe_points:
                if abs(kp.co.x - stop_of[bone]) < 1e-3:
                    kp.handle_left_type = kp.handle_right_type = "FREE"
                    kp.handle_left = (kp.co.x - 0.33, kp.co.y)
                    kp.handle_right = (kp.co.x + 0.33, kp.co.y)
            fc.update()
    if STAGE != "blocking":
        lo, hi = RIGHT_PATH_RANGE
        for i in range(lo * 10 + 1, hi * 10):  # every 0.1 frame: the chest turns fast under the arm
            key_right_arm(rig, i / 10, prev)
        for fc in _fcurves(act):
            if any(f'"Right{j}"' in fc.data_path for j in ("Shoulder", "Elbow", "Wrist")):
                for kp in fc.keyframe_points:
                    if lo <= kp.co.x <= hi:
                        kp.interpolation = "LINEAR"
    if STAGE != "blocking":
        quat_continuity(act)
    # legs: solved every quarter frame, so the feet stay planted between whole frames too
    leg_frames = (sorted({f for f, _ in KEYS}) if STAGE == "blocking" else
                  [f / 4 for f in range(FIRST * 4, LAST * 4 + 1)])
    for frame in leg_frames:
        key_legs(rig, frame, prev)
    if STAGE != "blocking":
        # the leg keys are dense IK samples: straight lines between them (as Roblox plays per-frame
        # keyframes) keep the feet planted; Bezier would bulge between samples
        for fc in _fcurves(act):
            if any(f'"{s}{j}"' in fc.data_path for s in ("Left", "Right") for j in ("Hip", "Knee", "Ankle")):
                for kp in fc.keyframe_points:
                    kp.interpolation = "LINEAR"
    bpy.ops.object.mode_set(mode="OBJECT")
    if STAGE == "blocking":
        for fc in _fcurves(act):
            for kp in fc.keyframe_points:
                kp.interpolation = "CONSTANT"
    spear = spear_object()
    for frame in (sorted({f for f, _ in KEYS}) if STAGE == "blocking" else range(FIRST, LAST + 1)):
        key_spear(spear, frame)
    if spear.animation_data and spear.animation_data.action:
        for fc in _fcurves(spear.animation_data.action):
            for kp in fc.keyframe_points:
                kp.interpolation = "CONSTANT"
    for m in list(scene.timeline_markers):
        scene.timeline_markers.remove(m)
    for name, frame in MARKERS.items():
        scene.timeline_markers.new(name, frame=frame)
    scene.render.fps, scene.render.fps_base = FPS, 1
    scene.frame_start, scene.frame_end = FIRST, LAST
    scene.frame_set(FIRST)


BODY = ["Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm",
        "RightLowerArm", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]


def spear_clearance(frame):
    """Smallest gap (studs, negative = inside) between the spear's surface and each body part box.
    The spear is sampled along its axis as a capsule of radius SPEAR_THICK / 2."""
    sc = bpy.context.scene
    sc.frame_set(frame)
    ob = bpy.data.objects[SPEAR]
    M = ob.matrix_world
    pts = [M @ V((0, -SPEAR_GRIP_FROM_TAIL + SPEAR_LEN * i / 60, 0)) for i in range(61)]
    worst = {}
    for name in BODY:
        part = bpy.data.objects[name]
        inv = part.matrix_world.inverted()
        lo = V([min(c[i] for c in part.bound_box) for i in range(3)])
        hi = V([max(c[i] for c in part.bound_box) for i in range(3)])
        best = 1e9
        for p in pts:
            q = inv @ p
            out = V([max(lo[i] - q[i], 0, q[i] - hi[i]) for i in range(3)])
            gap = out.length if out.length > 0 else -min(min(q[i] - lo[i], hi[i] - q[i]) for i in range(3))
            best = min(best, gap - SPEAR_THICK / 2)
        worst[name] = best
    return worst


rig = bpy.data.objects[RIG_NAME]
animate(rig)
os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
for f, pose in KEYS:
    bpy.context.scene.frame_set(f)
    h = bpy.data.objects["RightHand"].matrix_world.translation
    print(f"F{f:2d} {pose:9s} elbow R {BENDS.get(('RightElbow', f), 0):5.1f} L {BENDS.get(('LeftElbow', f), 0):5.1f} | "
          f"knee R {BENDS.get(('RightKnee', f), 0):5.1f} L {BENDS.get(('LeftKnee', f), 0):5.1f} | "
          f"R hand ({h.x:+.2f}, {h.y:+.2f}, {h.z:+.2f})")
for f in sorted(SPEAR_FRAMES):
    gaps = spear_clearance(f)
    near = sorted(gaps.items(), key=lambda kv: kv[1])[:3]
    tip = bpy.data.objects[SPEAR].matrix_world @ V((0, SPEAR_LEN - SPEAR_GRIP_FROM_TAIL, 0))
    aim = (bpy.data.objects[SPEAR].matrix_world.to_quaternion() @ V((0, 1, 0)))
    off_target = math.degrees(aim.angle((TARGET - bpy.data.objects["RightHand"].matrix_world.translation)))
    print(f"spear F{f:2d}: tip ({tip.x:+.2f}, {tip.y:+.2f}, {tip.z:+.2f}), {off_target:4.1f} deg off the target line | "
          + "  ".join(f"{n} {g:+.2f}" for n, g in near))
bpy.context.scene.frame_set(FIRST)
print("saved", OUT_BLEND, "| stage", STAGE, "| markers", MARKERS)

"""Spin for Abilities - combat animations (TSB style), stage 1: build + key the actions (Blender 5.2).

Run headless:
    blender.exe -b -P build_combat_anims.py
Rebuilds the project's R15 block rig (Game/assets/vfx/_src/build_pebble_toss_rig.py, the Studio joint
data - bones are NOT renamed or restructured), keys one action per move and saves
Game/assets/animations/combat_anims.blend (a new file; pebble_toss.blend is never touched).

Timing: 30 fps, frame = seconds * 30. Hit poses are keyed at the EXACT hit time (fractional frame,
e.g. 0.12 s = frame 3.6). Each action has a "Hit" pose marker (Blender markers are whole frames, so it
sits on the nearest frame) and the exact value in the custom property "hit_time".

Axes: +Y = forward (the target), +X = rig's right, +Z = up. Joint rotations are deltas in the parent's
frame with rest-aligned axes (= Roblox Motor6D Transform after the axis swap), same as the throw:
  Rx(+) swings a hanging arm/leg forward and pitches torso/head BACK, Rz(+) turns toward the rig's left,
  Ry(-) lifts the right arm out sideways (Ry(+) the left). Elbow Rx(+) = bend.
No root motion: HumanoidRootPart never moves (the controller already steps the player forward); the
Root joint (LowerTorso) shifts/sinks to move the weight and legs are solved per sample with exact
2-bone IK so the feet stay planted (rear heel may roll up onto the toes).

Stance: right foot forward, body bladed 18 deg to the left, so the right hand is the lead (jab/hook)
and the left the rear (cross/finisher). Every move starts and ends on GUARD so the string chains.
Overlap: hips lead the arms by HIPS_LEAD frames, the torso by TORSO_LEAD.
"""
import bpy, math, os, sys
from mathutils import Matrix, Vector

ROOT = r"C:\NYP\Roblox\Spin For Abilities\Game"
RIG_SCRIPT = os.path.join(ROOT, r"assets\vfx\_src\build_pebble_toss_rig.py")
OUT_BLEND = os.path.join(ROOT, r"assets\animations\combat_anims.blend")
RIG_NAME = "R15_Combat"
FPS = 30

# --- rig: run the existing rig builder, but save to the new file instead of pebble_toss.blend -------
src = open(RIG_SCRIPT, encoding="utf-8").read()
old = 'OUT_BLEND = r"C:\\Roblox\\Spin for ability\\Game\\assets\\pebble_toss.blend"'
assert old in src, "rig script OUT_BLEND line changed - update build_combat_anims.py"
# the rig builder saves as soon as the rig exists; send that save to a temp file, the real
# save happens at the end of main()
src = src.replace(old, "OUT_BLEND = " + repr(os.path.join(bpy.app.tempdir or os.environ.get("TEMP", "."), "_rig_only.blend")))
_ns = {}
exec(compile(src, RIG_SCRIPT, "exec"), _ns)
rig = _ns["rig"]
rig.name = RIG_NAME
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)


def Rx(d): return Matrix.Rotation(math.radians(d), 3, "X")
def Ry(d): return Matrix.Rotation(math.radians(d), 3, "Y")
def Rz(d): return Matrix.Rotation(math.radians(d), 3, "Z")
I = Matrix.Identity(3)
V = Vector

# Feet (ankle joints): right foot forward, 1.15 studs wide, 0.9 front-to-back.
FEET = {"Right": V((0.55, 0.42, 0.262)), "Left": V((-0.60, -0.48, 0.262))}
FOOT_HALF_DEPTH, ANKLE_HEIGHT = 0.5, 0.262

UPPER = ["Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist",
         "LeftShoulder", "LeftElbow", "LeftWrist"]

# --- poses ------------------------------------------------------------------------------------------
# Arms are posed by FIST TARGET (world point, studs; HumanoidRootPart at the origin, floor z = 0) plus
# an elbow POLE direction, solved per key with exact 2-bone IK (shoulder + elbow; wrist kept straight).
# A target out of reach gives a straight arm aimed at it, elbow bent `min_bend` deg (just off lock).
# That keeps the guard fist on the face whatever the hips/chest are doing, and stops arms swinging
# through the body. Hips/Waist/Neck stay plain rotations.
def ARM(target, pole, min_bend=8):
    return ("ik", V(target), V(pole), min_bend)


DOWN_OUT_R, DOWN_OUT_L = (0.5, 0, -1), (-0.5, 0, -1)
GUARD = {
    "hips": (V((0, 0, -0.22)), Rz(18)),
    "Waist": Rz(-6) @ Rx(-6),
    "Neck": Rz(-12) @ Rx(2),
    # lead (right) fist forward at chin height, rear (left) fist tight in front of the chin
    "RightArm": ARM((0.70, 1.40, 4.00), DOWN_OUT_R), "RightWrist": Rx(-8),
    "LeftArm": ARM((-0.55, 0.95, 4.15), DOWN_OUT_L), "LeftWrist": Rx(-8),
}


def P(**kw):
    d = dict(GUARD)
    d.update(kw)
    return d


# M1_1 - quick right jab (lead hand). Small hip/chest turn, left fist stays on the face.
JAB = {
    "antic": P(hips=(V((0, -0.05, -0.25)), Rz(14)), Waist=Rz(-9) @ Rx(-4), Neck=Rz(-6),
               RightArm=ARM((0.80, 1.15, 3.95), DOWN_OUT_R)),
    "hit": P(hips=(V((0.02, 0.14, -0.26)), Rz(26)), Waist=Rz(8) @ Rx(-8), Neck=Rz(-30) @ Rx(6),
             RightArm=ARM((0.15, 4.0, 3.85), (0.3, 0, -1)), RightWrist=Rx(-4),
             LeftArm=ARM((-0.60, 0.90, 4.15), DOWN_OUT_L)),
    "over": P(hips=(V((0.02, 0.17, -0.27)), Rz(28)), Waist=Rz(10) @ Rx(-9), Neck=Rz(-33) @ Rx(7),
              RightArm=ARM((0.12, 4.0, 3.82), (0.3, 0, -1), 3), RightWrist=Rx(-4),
              LeftArm=ARM((-0.60, 0.90, 4.15), DOWN_OUT_L)),
    "recover": P(hips=(V((0, 0.03, -0.23)), Rz(19)), Waist=Rz(-4) @ Rx(-6),
                 RightArm=ARM((0.78, 1.25, 3.95), DOWN_OUT_R)),
}

# M1_2 - left cross (rear hand). Hips + chest drive hard to the right, rear heel rolls up,
# right fist pulls back to guard the face.
CROSS = {
    "antic": P(hips=(V((0, -0.08, -0.26)), Rz(26)), Waist=Rz(-2) @ Rx(-4), Neck=Rz(-22) @ Rx(2),
               LeftArm=ARM((-0.62, 0.70, 4.05), DOWN_OUT_L),
               RightArm=ARM((0.72, 1.25, 4.05), DOWN_OUT_R)),
    "hit": P(hips=(V((-0.04, 0.26, -0.30)), Rz(-14) @ Rx(-3)), Waist=Rz(-16) @ Rx(-9), Neck=Rz(30) @ Rx(8),
             LeftArm=ARM((-0.05, 4.0, 3.80), (-0.3, 0, -1)), LeftWrist=Rx(-4),
             RightArm=ARM((0.88, 1.25, 4.05), DOWN_OUT_R)),
    "over": P(hips=(V((-0.05, 0.30, -0.31)), Rz(-18) @ Rx(-4)), Waist=Rz(-19) @ Rx(-10), Neck=Rz(35) @ Rx(9),
              LeftArm=ARM((-0.02, 4.0, 3.76), (-0.3, 0, -1), 3), LeftWrist=Rx(-4),
              RightArm=ARM((0.88, 1.25, 4.05), DOWN_OUT_R)),
    "recover": P(hips=(V((0, 0.06, -0.24)), Rz(12)), Waist=Rz(-7) @ Rx(-6), Neck=Rz(-6) @ Rx(2),
                 LeftArm=ARM((-0.50, 1.15, 4.10), DOWN_OUT_L)),
}

# M1_3 - right hook (lead hand). Elbow lifts out to shoulder height (pole points out to the side),
# forearm horizontal, the fist sweeps across in front of the centre line, driven by hips + chest
# turning right. Left fist stays tucked on the left cheek, clear of the hooking arm.
POLE_HOOK = (1, -0.2, 0.05)  # elbow out to the side at shoulder height
HOOK = {
    "antic": P(hips=(V((0.04, -0.06, -0.28)), Rz(26)), Waist=Rz(2) @ Rx(-5), Neck=Rz(-26) @ Rx(2),
               RightArm=ARM((1.15, 1.05, 3.95), (1, -0.3, -0.35)),
               LeftArm=ARM((-0.80, 1.00, 4.20), DOWN_OUT_L)),
    "hit": P(hips=(V((0.0, 0.16, -0.29)), Rz(0) @ Rx(-2)), Waist=Rz(-10) @ Rx(-8), Neck=Rz(10) @ Rx(6),
             RightArm=ARM((0.15, 1.30, 3.95), POLE_HOOK), RightWrist=I,
             LeftArm=ARM((-0.95, 0.95, 4.20), DOWN_OUT_L)),
    "over": P(hips=(V((-0.01, 0.18, -0.30)), Rz(-6) @ Rx(-3)), Waist=Rz(-14) @ Rx(-9), Neck=Rz(20) @ Rx(7),
              RightArm=ARM((0.0, 1.25, 3.92), POLE_HOOK), RightWrist=I,
              LeftArm=ARM((-0.98, 0.90, 4.20), DOWN_OUT_L)),
    "recover": P(hips=(V((0, 0.04, -0.24)), Rz(12)), Waist=Rz(-8) @ Rx(-6), Neck=Rz(-8) @ Rx(2),
                 RightArm=ARM((0.90, 1.35, 3.98), (1, 0, -0.8))),
}

# M1_4 - heavy finisher: big coil back (weight on the rear leg, left fist chambered at the ribs, right
# arm reaching out to measure), short hold, then a full-body left straight with the weight thrown onto
# the front leg, deep follow-through, a small recoil, and back into guard.
POLE_CHAMBER = (-0.4, -1, -0.6)
HEAVY = {
    "antic": P(hips=(V((0.04, -0.16, -0.34)), Rz(40) @ Rx(3)), Waist=Rz(14) @ Rx(3), Neck=Rz(-48) @ Rx(-2),
               LeftArm=ARM((-0.95, -0.45, 3.35), POLE_CHAMBER), LeftWrist=Rx(-10),
               RightArm=ARM((0.30, 2.30, 3.85), (0.4, 0, -1)), RightWrist=I),
    "hold": P(hips=(V((0.05, -0.19, -0.36)), Rz(44) @ Rx(4)), Waist=Rz(17) @ Rx(4), Neck=Rz(-53) @ Rx(-3),
              LeftArm=ARM((-1.00, -0.55, 3.30), POLE_CHAMBER), LeftWrist=Rx(-10),
              RightArm=ARM((0.25, 2.40, 3.85), (0.4, 0, -1)), RightWrist=I),
    "hit": P(hips=(V((-0.04, 0.34, -0.36)), Rz(-22) @ Rx(-6)), Waist=Rz(-22) @ Rx(-12), Neck=Rz(42) @ Rx(14),
             LeftArm=ARM((0.05, 4.5, 3.55), (-0.3, 0, -1)), LeftWrist=Rx(-4),
             RightArm=ARM((1.25, -0.75, 3.20), (0.5, -1, -0.3)), RightWrist=I),
    "over": P(hips=(V((-0.05, 0.40, -0.38)), Rz(-28) @ Rx(-8)), Waist=Rz(-27) @ Rx(-15), Neck=Rz(50) @ Rx(17),
              LeftArm=ARM((0.10, 4.5, 3.45), (-0.3, 0, -1), 3), LeftWrist=Rx(-4),
              RightArm=ARM((1.25, -0.85, 3.15), (0.5, -1, -0.3)), RightWrist=I),
    "recoil": P(hips=(V((-0.02, 0.16, -0.29)), Rz(-8) @ Rx(-3)), Waist=Rz(-12) @ Rx(-8), Neck=Rz(16) @ Rx(6),
                LeftArm=ARM((-0.20, 1.90, 3.85), (-0.6, 0, -1)), LeftWrist=Rx(-6),
                RightArm=ARM((0.85, 0.95, 3.90), DOWN_OUT_R)),
}

# ---- reference style (gameplay recording 2026-11-04): square stance facing the target, fists low and
# loose, each punch thrown straight at shoulder height with a big shoulder/torso drive and forward
# lean, the off arm swinging back for counterbalance, and a step-in with the opposite foot.
FEET_SQUARE = {"Right": V((0.62, -0.12, 0.262)), "Left": V((-0.62, 0.18, 0.262))}
READY = {
    "hips": (V((0, 0, -0.18)), Rz(6)),
    "Waist": Rz(-2) @ Rx(-8),
    "Neck": Rz(-4) @ Rx(5),
    "RightArm": ARM((0.85, 0.80, 3.35), (0.3, -0.5, -1)), "RightWrist": Rx(-6),
    "LeftArm": ARM((-0.85, 0.80, 3.35), (-0.3, -0.5, -1)), "LeftWrist": Rx(-6),
}


def R(**kw):
    d = dict(READY)
    d.update(kw)
    return d


JAB2 = {
    # coil: right shoulder pulled back, fist chambered at the ribs, left hand reaches out to measure
    "antic": R(hips=(V((0, -0.06, -0.22)), Rz(-10)), Waist=Rz(-12) @ Rx(-6), Neck=Rz(20) @ Rx(4),
               RightArm=ARM((1.30, 0.05, 3.45), (0.5, -1, -0.5)),
               LeftArm=ARM((-0.55, 1.35, 3.65), (-0.4, 0, -1))),
    # full shoulder drive: hips + chest turned ~46 deg, leaning in, fist straight through the target,
    # left arm thrown back and down behind the hip
    "hit": R(hips=(V((0, 0.22, -0.26)), Rz(24) @ Rx(-4)), Waist=Rz(22) @ Rx(-12), Neck=Rz(-42) @ Rx(10),
             RightArm=ARM((0.10, 4.5, 3.75), (0.3, 0, -1), 6), RightWrist=Rx(-4),
             LeftArm=ARM((-1.25, -0.75, 2.90), (-0.4, -1, -0.4))),
    "over": R(hips=(V((0, 0.26, -0.27)), Rz(28) @ Rx(-5)), Waist=Rz(25) @ Rx(-14), Neck=Rz(-48) @ Rx(12),
              RightArm=ARM((0.08, 4.5, 3.70), (0.3, 0, -1), 2), RightWrist=Rx(-4),
              LeftArm=ARM((-1.30, -0.85, 2.85), (-0.4, -1, -0.4))),
    "recover": R(hips=(V((0, 0.08, -0.20)), Rz(9)), Waist=Rz(0) @ Rx(-8), Neck=Rz(-8) @ Rx(5),
                 RightArm=ARM((1.10, 1.00, 3.45), (0.6, -0.3, -1)),
                 LeftArm=ARM((-0.92, 0.70, 3.30), (-0.3, -0.5, -1))),
}

S_MIRROR = Matrix(((-1, 0, 0), (0, 1, 0), (0, 0, 1)))


def mirror_pose(p):
    """Left/right mirror of a pose (x -> -x): rotations S R S, arm targets/poles flipped and swapped."""
    def m_arm(arm):
        _, t, pole, mb = arm
        return ("ik", V((-t.x, t.y, t.z)), V((-pole.x, pole.y, pole.z)), mb)
    off, D = p["hips"]
    return {
        "hips": (V((-off.x, off.y, off.z)), S_MIRROR @ D @ S_MIRROR),
        "Waist": S_MIRROR @ p["Waist"] @ S_MIRROR,
        "Neck": S_MIRROR @ p["Neck"] @ S_MIRROR,
        "RightArm": m_arm(p["LeftArm"]), "LeftArm": m_arm(p["RightArm"]),
        "RightWrist": S_MIRROR @ p["LeftWrist"] @ S_MIRROR, "LeftWrist": S_MIRROR @ p["RightWrist"] @ S_MIRROR,
    }


# M1_2 - left cross: the jab mirrored, with more hip/chest drive and lean (stronger than M1_1).
CROSS2 = {k: mirror_pose(v) for k, v in JAB2.items()}
CROSS2["hit"].update(hips=(V((0, 0.28, -0.28)), Rz(-30) @ Rx(-5)), Waist=Rz(-26) @ Rx(-14), Neck=Rz(52) @ Rx(12))
CROSS2["over"].update(hips=(V((0, 0.32, -0.29)), Rz(-34) @ Rx(-6)), Waist=Rz(-29) @ Rx(-16), Neck=Rz(58) @ Rx(14))

# M1_3 - right hook: chest turns right to load (elbow out), then whips left so the bent arm sweeps
# the fist across in front of the centre line. Off hand swings back less than on the straights.
POLE_HOOK2 = (0.85, 0.3, 0.1)
HOOK2 = {
    "antic": R(hips=(V((0, -0.05, -0.24)), Rz(-16)), Waist=Rz(-10) @ Rx(-6), Neck=Rz(24) @ Rx(4),
               RightArm=ARM((1.45, 0.45, 3.75), (1, -0.4, -0.2)),
               LeftArm=ARM((-0.75, 1.10, 3.55), (-0.4, -0.3, -1))),
    "hit": R(hips=(V((0, 0.18, -0.26)), Rz(20) @ Rx(-3)), Waist=Rz(16) @ Rx(-10), Neck=Rz(-34) @ Rx(8),
             RightArm=ARM((-0.10, 1.75, 3.90), POLE_HOOK2), RightWrist=I,
             LeftArm=ARM((-1.15, -0.30, 3.10), (-0.4, -1, -0.5))),
    "over": R(hips=(V((0, 0.21, -0.27)), Rz(26) @ Rx(-4)), Waist=Rz(20) @ Rx(-11), Neck=Rz(-42) @ Rx(9),
              RightArm=ARM((-0.45, 1.55, 3.90), POLE_HOOK2), RightWrist=I,
              LeftArm=ARM((-1.20, -0.40, 3.05), (-0.4, -1, -0.5))),
    "recover": R(hips=(V((0, 0.07, -0.20)), Rz(10)), Waist=Rz(2) @ Rx(-8), Neck=Rz(-10) @ Rx(5),
                 RightArm=ARM((1.10, 1.05, 3.50), (0.7, -0.2, -0.8)),
                 LeftArm=ARM((-0.95, 0.65, 3.30), (-0.3, -0.5, -1))),
}

# M1_4 - heavy left straight: big coil (left fist chambered far back, weight back), a beat of hold,
# then a lunging step with the right foot and the whole body thrown through the punch; deep
# follow-through, recoil, back to ready.
HEAVY2 = {
    "antic": R(hips=(V((0, -0.16, -0.32)), Rz(30) @ Rx(4)), Waist=Rz(16) @ Rx(4), Neck=Rz(-44),
               LeftArm=ARM((-1.35, -0.45, 3.35), (-0.5, -1, -0.4)), LeftWrist=Rx(-10),
               RightArm=ARM((0.45, 1.65, 3.75), (0.4, 0, -1))),
    "hold": R(hips=(V((0, -0.19, -0.35)), Rz(34) @ Rx(5)), Waist=Rz(19) @ Rx(5), Neck=Rz(-50) @ Rx(-2),
              LeftArm=ARM((-1.40, -0.60, 3.30), (-0.5, -1, -0.4)), LeftWrist=Rx(-10),
              RightArm=ARM((0.40, 1.75, 3.75), (0.4, 0, -1))),
    "hit": R(hips=(V((0, 0.42, -0.36)), Rz(-30) @ Rx(-8)), Waist=Rz(-28) @ Rx(-16), Neck=Rz(54) @ Rx(14),
             LeftArm=ARM((-0.10, 4.8, 3.55), (-0.3, 0, -1), 6), LeftWrist=Rx(-4),
             RightArm=ARM((1.30, -0.80, 2.85), (0.4, -1, -0.4))),
    "over": R(hips=(V((0, 0.48, -0.38)), Rz(-35) @ Rx(-10)), Waist=Rz(-32) @ Rx(-19), Neck=Rz(60) @ Rx(17),
              LeftArm=ARM((-0.08, 4.8, 3.45), (-0.3, 0, -1), 2), LeftWrist=Rx(-4),
              RightArm=ARM((1.35, -0.90, 2.80), (0.4, -1, -0.4))),
    "recoil": R(hips=(V((0, 0.22, -0.27)), Rz(-12) @ Rx(-4)), Waist=Rz(-12) @ Rx(-10), Neck=Rz(18) @ Rx(7),
                LeftArm=ARM((-0.45, 2.10, 3.75), (-0.6, 0, -1)), LeftWrist=Rx(-6),
                RightArm=ARM((1.40, 0.55, 3.30), (0.6, -0.6, -1))),
}

# Uppercut - drop into the legs with the right fist low by the hip, then extend the legs (rising onto
# the toes) and drive the fist up past the face, torso rising and leaning back with it.
UPPER = {
    "crouch": R(hips=(V((0, -0.02, -0.48)), Rz(-14) @ Rx(-6)), Waist=Rz(-8) @ Rx(-14), Neck=Rz(20) @ Rx(10),
                RightArm=ARM((1.15, 0.30, 2.70), (0.5, -1, -0.3)), RightWrist=Rx(10),
                LeftArm=ARM((-0.65, 1.20, 3.40), (-0.4, -0.3, -1))),
    "hit": R(hips=(V((0, 0.16, -0.10)), Rz(22) @ Rx(3)), Waist=Rz(16) @ Rx(6), Neck=Rz(-30) @ Rx(-6),
             RightArm=ARM((0.25, 1.30, 5.15), (0.7, -0.4, -0.6)), RightWrist=Rx(-10),
             LeftArm=ARM((-1.20, -0.55, 2.95), (-0.4, -1, -0.4))),
    "over": R(hips=(V((0, 0.18, -0.06)), Rz(26) @ Rx(5)), Waist=Rz(19) @ Rx(10), Neck=Rz(-34) @ Rx(-12),
              RightArm=ARM((0.18, 1.05, 5.55), (0.7, -0.4, -0.6)), RightWrist=Rx(-10),
              LeftArm=ARM((-1.25, -0.65, 2.90), (-0.4, -1, -0.4))),
    "recover": R(hips=(V((0, 0.08, -0.20)), Rz(10)), Waist=Rz(2) @ Rx(-4), Neck=Rz(-10) @ Rx(2),
                 RightArm=ARM((1.20, 1.20, 3.55), (0.7, -0.2, -0.8)),
                 LeftArm=ARM((-0.95, 0.65, 3.30), (-0.3, -0.5, -1))),
}

# Downslam - both fists rise together overhead with the back arched, a beat of hold, then the whole
# upper body drives down into a deep crouch and the double-fist hammer finishes low in front.
DOWN = {
    "raise": R(hips=(V((0, -0.10, -0.12)), Rx(6)), Waist=Rx(14), Neck=Rx(-10),
               RightArm=ARM((0.50, 0.15, 5.70), (0.7, -0.3, 0.2)), RightWrist=Rx(-10),
               LeftArm=ARM((-0.50, 0.15, 5.70), (-0.7, -0.3, 0.2)), LeftWrist=Rx(-10)),
    "hold": R(hips=(V((0, -0.13, -0.10)), Rx(8)), Waist=Rx(18), Neck=Rx(-12),
              RightArm=ARM((0.50, -0.10, 5.80), (0.7, -0.3, 0.2)), RightWrist=Rx(-12),
              LeftArm=ARM((-0.50, -0.10, 5.80), (-0.7, -0.3, 0.2)), LeftWrist=Rx(-12)),
    "hit": R(hips=(V((0, 0.26, -0.58)), Rx(-18)), Waist=Rx(-28), Neck=Rx(22),
             RightArm=ARM((0.50, 2.10, 1.60), (0.6, 0, 0.3), 10), RightWrist=Rx(-6),
             LeftArm=ARM((-0.50, 2.10, 1.60), (-0.6, 0, 0.3), 10), LeftWrist=Rx(-6)),
    "over": R(hips=(V((0, 0.30, -0.64)), Rx(-21)), Waist=Rx(-32), Neck=Rx(25),
              RightArm=ARM((0.50, 1.95, 1.20), (0.6, 0, 0.3), 6), RightWrist=Rx(-6),
              LeftArm=ARM((-0.50, 1.95, 1.20), (-0.6, 0, 0.3), 6), LeftWrist=Rx(-6)),
    "recover": R(hips=(V((0, 0.12, -0.32)), Rz(4) @ Rx(-6)), Waist=Rz(-2) @ Rx(-12), Neck=Rz(-4) @ Rx(10),
                 RightArm=ARM((1.00, 1.10, 3.10), (0.6, -0.3, -1)),
                 LeftArm=ARM((-1.00, 1.10, 3.10), (-0.6, -0.3, -1))),
}

# ---- hit reactions (played on whoever GETS hit; reference: gameplay recording 2026-11-04) -------------
# Arms (and for Launched / KnockedDown the legs too) are plain joint rotations here instead of IK targets:
# "RightShoulder"/"RightElbow"/"RightWrist" keys replace "RightArm"; legs="free" specs key
# "RightHip"/"RightKnee"/"RightAnkle" from the pose instead of solving planted feet.
def LIMP(side, fwd=8, out=12, bend=25):
    s = -1 if side == "Right" else 1  # Ry(-) lifts the right arm out, Ry(+) the left
    return {f"{side}Shoulder": Ry(s * out) @ Rx(fwd), f"{side}Elbow": Rx(bend), f"{side}Wrist": Rx(-8)}


def REACT(hips, Waist, Neck, **joints):
    d = {"hips": hips, "Waist": Waist, "Neck": Neck}
    d.update(LIMP("Right"))
    d.update(LIMP("Left"))
    d.update(joints)
    return d


# Stunned - dazed loop: bent forward, head drooping to one side, arms hanging limp, swaying.
DAZED = REACT((V((0, -0.06, -0.36)), Rz(6) @ Rx(-6)), Rz(4) @ Rx(-14), Rz(12) @ Rx(-20),
              **LIMP("Right", 6, 14, 28), **LIMP("Left", 12, 10, 22))
DAZED_SWAY = REACT((V((0, -0.04, -0.33)), Rz(-6) @ Rx(-4)), Rz(-5) @ Rx(-11), Rz(-12) @ Rx(-16),
                   **LIMP("Right", 14, 10, 22), **LIMP("Left", 4, 14, 30))
# Flinch - one hit lands: snapped back (head thrown back, chest arched, arms flung forward), then
# settles back into the dazed pose.
JOLT = REACT((V((0, -0.24, -0.30)), Rx(9)), Rx(16), Rz(6) @ Rx(30),
             **LIMP("Right", 38, 26, 45), **LIMP("Left", 30, 30, 38))

# Launched - in the air after an Uppercut: body tipped back, face to the sky, arms out and trailing,
# legs dangling, a slow flail.
AIR_LEGS = {"RightHip": Rx(30), "RightKnee": Rx(-62), "RightAnkle": Rx(-20),
            "LeftHip": Rx(6), "LeftKnee": Rx(-34), "LeftAnkle": Rx(-15)}
AIR_LEGS2 = {"RightHip": Rx(10), "RightKnee": Rx(-38), "RightAnkle": Rx(-15),
             "LeftHip": Rx(28), "LeftKnee": Rx(-64), "LeftAnkle": Rx(-20)}
AIR = REACT((V((0, 0, 0)), Rx(14)), Rx(16), Rx(38),
            RightShoulder=Ry(-55) @ Rx(-20), RightElbow=Rx(28),
            LeftShoulder=Ry(55) @ Rx(-25), LeftElbow=Rx(22), **AIR_LEGS)
AIR2 = REACT((V((0, 0, 0.05)), Rx(18)), Rx(20), Rx(32),
             RightShoulder=Ry(-72) @ Rx(-8), RightElbow=Rx(38),
             LeftShoulder=Ry(70) @ Rx(-14), LeftElbow=Rx(30), **AIR_LEGS2)

# KnockedDown - after a Downslam (or a Knockback ragdoll): flat on the back, face up, head rolled to
# the side, arms thrown out, one knee up; the chest rises and falls. HumanoidRootPart stays upright,
# so the Root joint tips the whole body back 90 deg and drops it to the floor.
LIE_Z = 0.5 - rig.data.bones["Root"].head_local.z  # lower-torso centre ~0.5 above the floor
LIE_LEGS = {"RightHip": Rx(24), "RightKnee": Rx(-48), "RightAnkle": Rx(10),
            "LeftHip": Ry(-6) @ Rx(4), "LeftKnee": Rx(-10), "LeftAnkle": Rx(20)}
LIE = REACT((V((0, 0, LIE_Z)), Rx(90)), Rx(-3), Rz(28) @ Rx(6),
            RightShoulder=Ry(-78) @ Rx(10), RightElbow=Rx(35),
            LeftShoulder=Ry(62) @ Rx(-6), LeftElbow=Rx(18), **LIE_LEGS)
LIE2 = REACT((V((0, 0, LIE_Z)), Rx(90)), Rx(-7), Rz(26) @ Rx(4),
             RightShoulder=Ry(-80) @ Rx(12), RightElbow=Rx(38),
             LeftShoulder=Ry(64) @ Rx(-4), LeftElbow=Rx(20), **LIE_LEGS)

# Downslam (air) - the finisher of the air combo, thrown while hanging next to the target after an
# Uppercut. Knees tuck, the body arches back with both fists high overhead, then everything whips
# forward and down: hips pitch forward, the double-fist hammer comes down in front and the legs kick
# back behind for the counter-swing; deep follow-through, then it opens back up (the attacker is
# dropping to the ground by then). Legs are free (no planted feet in the air).
def AIRP(hips, Waist, Neck, legs, **arms):
    d = dict(READY)
    d.update(hips=hips, Waist=Waist, Neck=Neck, **arms)
    d.update(legs)
    return d


TUCK_LEGS = {"RightHip": Rx(55), "RightKnee": Rx(-95), "RightAnkle": Rx(-15),
             "LeftHip": Rx(40), "LeftKnee": Rx(-85), "LeftAnkle": Rx(-15)}
RAISE_LEGS = {"RightHip": Rx(62), "RightKnee": Rx(-112), "RightAnkle": Rx(-20),
              "LeftHip": Rx(45), "LeftKnee": Rx(-100), "LeftAnkle": Rx(-20)}
KICK_LEGS = {"RightHip": Rx(-18), "RightKnee": Rx(-85), "RightAnkle": Rx(-25),
             "LeftHip": Rx(-4), "LeftKnee": Rx(-65), "LeftAnkle": Rx(-20)}
KICK_LEGS2 = {"RightHip": Rx(-24), "RightKnee": Rx(-92), "RightAnkle": Rx(-25),
              "LeftHip": Rx(-8), "LeftKnee": Rx(-72), "LeftAnkle": Rx(-20)}
OPEN_LEGS = {"RightHip": Rx(12), "RightKnee": Rx(-35), "RightAnkle": Rx(-10),
             "LeftHip": Rx(4), "LeftKnee": Rx(-25), "LeftAnkle": Rx(-10)}
AIR_DOWN = {
    "tuck": AIRP((V((0, -0.05, 0.10)), Rx(8)), Rx(6), Rx(-6), TUCK_LEGS,
                 RightArm=ARM((0.70, 0.40, 4.70), (0.7, -0.4, -0.3)), RightWrist=Rx(-8),
                 LeftArm=ARM((-0.70, 0.40, 4.70), (-0.7, -0.4, -0.3)), LeftWrist=Rx(-8)),
    "raise": AIRP((V((0, -0.15, 0.15)), Rx(20)), Rx(24), Rx(-16), RAISE_LEGS,
                  RightArm=ARM((0.45, -0.60, 6.10), (0.7, -0.3, 0.2)), RightWrist=Rx(-14),
                  LeftArm=ARM((-0.45, -0.60, 6.10), (-0.7, -0.3, 0.2)), LeftWrist=Rx(-14)),
    "hit": AIRP((V((0, 0.30, -0.05)), Rx(-32)), Rx(-28), Rx(24), KICK_LEGS,
                RightArm=ARM((0.40, 2.60, 1.10), (0.6, 0, 0.3), 8), RightWrist=Rx(-6),
                LeftArm=ARM((-0.40, 2.60, 1.10), (-0.6, 0, 0.3), 8), LeftWrist=Rx(-6)),
    "over": AIRP((V((0, 0.36, -0.10)), Rx(-40)), Rx(-32), Rx(28), KICK_LEGS2,
                 RightArm=ARM((0.42, 2.20, 0.60), (0.6, 0, 0.3), 4), RightWrist=Rx(-6),
                 LeftArm=ARM((-0.42, 2.20, 0.60), (-0.6, 0, 0.3), 4), LeftWrist=Rx(-6)),
    "recover": AIRP((V((0, 0.12, -0.05)), Rx(-12)), Rx(-12), Rx(10), OPEN_LEGS,
                    # same elbow pole family as the hammer, so the arms lift without flipping
                    RightArm=ARM((0.80, 1.70, 2.70), (0.6, 0, 0.3), 30),
                    LeftArm=ARM((-0.80, 1.70, 2.70), (-0.6, 0, 0.3), 30)),
}

REACTIONS = {
    # loops: start == end. hit = 0 (no impact frame; kept so the export picks them up).
    "Stunned": dict(length=0.80, hit=0.0, lead=(0, 0), stance=FEET_SQUARE, loop=True,
                    keys=[(0, DAZED), (12.0, DAZED_SWAY), (24.0, DAZED)], heel={}),
    "Flinch": dict(length=0.35, hit=0.06, lead=(0, 0), stance=FEET_SQUARE,
                   keys=[(0, DAZED), (1.8, JOLT), (5.0, DAZED_SWAY), (10.5, DAZED)], heel={}),
    "Launched": dict(length=0.80, hit=0.0, lead=(0, 0), legs="free", loop=True,
                     keys=[(0, AIR), (12.0, AIR2), (24.0, AIR)]),
    "KnockedDown": dict(length=1.20, hit=0.0, lead=(0, 0), legs="free", loop=True,
                        keys=[(0, LIE), (18.0, LIE2), (36.0, LIE)]),
}

# name: length (s), hit (s), [(frame, pose)], heel lifts {side: [(frame, deg)]}, foot steps
# {side: [(frame, (dx, dy, lift))]}, hips/torso lead (frames). All start and end on READY.
ANIMS = {
    "M1_1": dict(length=0.30, hit=0.12, lead=(0.5, 0.25), stance=FEET_SQUARE,
                 keys=[(0, READY), (1.4, JAB2["antic"]), (3.6, JAB2["hit"]), (4.8, JAB2["over"]),
                       (7.0, JAB2["recover"]), (9.0, READY)],
                 # left foot steps in (lifts 0.28, lands 0.32 forward on the hit), right heel rolls up
                 steps={"Left": [(0, (0, 0, 0)), (1.0, (0, 0, 0)), (2.3, (0, 0.18, 0.28)), (3.4, (0, 0.32, 0)),
                                 (6.5, (0, 0.30, 0)), (9.0, (0, 0, 0))]},
                 heel={"Right": [(0, 0), (2.0, 0), (3.6, 24), (4.8, 28), (7.0, 6), (9.0, 0)]}),
    "M1_2": dict(length=0.30, hit=0.12, lead=(0.6, 0.3), stance=FEET_SQUARE,
                 keys=[(0, READY), (1.4, CROSS2["antic"]), (3.6, CROSS2["hit"]), (4.8, CROSS2["over"]),
                       (7.0, CROSS2["recover"]), (9.0, READY)],
                 steps={"Right": [(0, (0, 0, 0)), (1.0, (0, 0, 0)), (2.3, (0, 0.22, 0.30)), (3.4, (0, 0.40, 0)),
                                  (6.5, (0, 0.38, 0)), (9.0, (0, 0, 0))]},
                 heel={"Left": [(0, 0), (2.0, 0), (3.6, 28), (4.8, 32), (7.0, 8), (9.0, 0)]}),
    "M1_3": dict(length=0.30, hit=0.12, lead=(0.6, 0.3), stance=FEET_SQUARE,
                 keys=[(0, READY), (1.6, HOOK2["antic"]), (3.6, HOOK2["hit"]), (4.9, HOOK2["over"]),
                       (7.0, HOOK2["recover"]), (9.0, READY)],
                 heel={"Right": [(0, 0), (1.6, 0), (3.6, 22), (4.9, 26), (7.0, 6), (9.0, 0)]}),
    "M1_4": dict(length=0.45, hit=0.20, lead=(0.9, 0.45), stance=FEET_SQUARE,
                 keys=[(0, READY), (3.0, HEAVY2["antic"]), (4.3, HEAVY2["hold"]), (6.0, HEAVY2["hit"]),
                       (7.6, HEAVY2["over"]), (10.0, HEAVY2["recoil"]), (13.5, READY)],
                 # lunge: right foot lifts out of the hold and lands 0.5 forward just before impact
                 steps={"Right": [(0, (0, 0, 0)), (4.3, (0, 0, 0)), (5.0, (0, 0.30, 0.32)), (5.8, (0, 0.52, 0)),
                                  (10.0, (0, 0.48, 0)), (13.5, (0, 0, 0))]},
                 heel={"Left": [(0, 0), (4.3, 0), (6.0, 34), (7.6, 40), (10.0, 14), (13.5, 0)]}),
    "Uppercut": dict(length=0.40, hit=0.15, lead=(0.6, 0.3), stance=FEET_SQUARE,
                     keys=[(0, READY), (2.0, UPPER["crouch"]), (4.5, UPPER["hit"]), (6.2, UPPER["over"]),
                           (9.0, UPPER["recover"]), (12.0, READY)],
                     # rises onto the toes as the legs extend
                     heel={"Right": [(0, 0), (2.0, 0), (4.5, 26), (6.2, 30), (9.0, 6), (12.0, 0)],
                           "Left": [(0, 0), (2.0, 0), (4.5, 14), (6.2, 18), (9.0, 4), (12.0, 0)]}),
    # air version (AIR_DOWN); the old standing hammer (DOWN) is kept above for reference
    "Downslam": dict(length=0.45, hit=0.25, lead=(0.7, 0.35), legs="free",
                     keys=[(0, AIR_DOWN["tuck"]), (3.5, AIR_DOWN["raise"]), (5.2, AIR_DOWN["raise"]),
                           (7.5, AIR_DOWN["hit"]), (9.0, AIR_DOWN["over"]), (11.5, AIR_DOWN["recover"]),
                           (13.5, READY)],
                     heel={}),
}
ANIMS.update(REACTIONS)


# --- keying -----------------------------------------------------------------------------------------
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


def smooth_keys(keys, frame):
    if not keys:
        return 0.0
    for (f0, a0), (f1, a1) in zip(keys, keys[1:]):
        if f0 <= frame <= f1:
            t = (frame - f0) / (f1 - f0)
            t = t * t * (3 - 2 * t)
            return a0 + (a1 - a0) * t
    return keys[-1][1]


def bone_len(name):
    b = rig.data.bones[name]
    return (b.tail_local - b.head_local).length


def leg_frame(down, n):
    z = -down.normalized()
    y = down.normalized().cross(n).normalized()
    x = y.cross(z).normalized()
    return Matrix((x, y, z)).transposed()


def set_time(t):
    f = math.floor(t)
    bpy.context.scene.frame_set(f, subframe=t - f)


def smooth_vec(keys, frame):
    if not keys:
        return V((0, 0, 0))
    return V(tuple(smooth_keys([(f, v[i]) for f, v in keys], frame) for i in range(3)))


def key_legs(t, heel, prev, report, stance=None, steps=None):
    """Exact 2-bone IK: ankle on its planted spot, knee forward (slightly out), foot flat/rolled."""
    set_time(t)
    root = rig.pose.bones["Root"]
    pelvis = root.matrix.to_3x3() @ rest_rot(root).inverted()
    for side, base in (stance or FEET).items():
        planted = base + smooth_vec((steps or {}).get(side), t)
        out = 1 if side == "Right" else -1
        foot = Rx(-smooth_keys(heel.get(side), t))
        toe = planted + V((0, FOOT_HALF_DEPTH, -ANKLE_HEIGHT))
        target = toe + foot @ (planted - toe)
        hip, knee, ankle = (rig.pose.bones[f"{side}{j}"] for j in ("Hip", "Knee", "Ankle"))
        L1, L2 = bone_len(f"{side}Hip"), bone_len(f"{side}Knee")
        H = rig.matrix_world @ hip.head
        d_vec = target - H
        if d_vec.length > 0.999 * (L1 + L2):
            report.append(f"  ! {side} leg overstretched at frame {t:.2f} ({d_vec.length:.3f} > {L1 + L2:.3f})")
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
        for pb, D in ((hip, pelvis.inverted() @ W1), (knee, W1.inverted() @ W2), (ankle, W2.inverted() @ foot)):
            prev[pb.name] = key_rotation(pb, D, t, prev.get(pb.name))


def head_rel(child, parent):
    b = rig.data.bones
    return b[child].head_local - b[parent].head_local


def solve_arm(side, pose):
    """Shoulder + elbow deltas that put the fist (hand centre) on the pose's target. The chest frame
    comes from this pose's own hips/Waist, so targets are exact at the key.
    R15 detail: the elbow joint sits 0.5 studs outboard of the shoulder joint, so the upper-arm rest
    vector r1 is tilted; the solve uses the real rest vectors r1 (shoulder->elbow) and r2 (elbow->hand
    centre) instead of assuming a straight hanging arm."""
    _, target, pole, min_bend = pose[f"{side}Arm"]
    offset, D_root = pose["hips"]
    chest = D_root @ pose["Waist"]
    root_head = rig.data.bones["Root"].head_local + offset
    S = root_head + D_root @ (head_rel("Waist", "Root") + pose["Waist"] @ head_rel(f"{side}Shoulder", "Waist"))
    r1 = head_rel(f"{side}Elbow", f"{side}Shoulder")
    r2 = head_rel(f"{side}Wrist", f"{side}Elbow") + V((0, 0, -0.13157))
    L2 = r2.length
    # |r1 + Rx(t) r2|^2 = |r1|^2 + L2^2 + 2 * (-r1.z) * L2 * cos t   (r2 ~ straight down, hinge = X)
    d = (target - S).length
    c = (d * d - r1.length_squared - L2 * L2) / (2 * -r1.z * L2)
    c = max(math.cos(math.radians(150)), min(math.cos(math.radians(min_bend)), c))
    theta = math.degrees(math.acos(c))
    v_local = r1 + Rx(theta) @ r2                     # shoulder -> fist in the arm's rest frame
    # align v_local with the aim direction, and put the elbow (r1) on the pole side
    def basis(a, b):
        e1 = a.normalized()
        e2 = (b - b.dot(e1) * e1).normalized()
        return Matrix((e1, e2, e1.cross(e2))).transposed()
    u = (target - S).normalized()
    W1 = basis(u, V(pole)) @ basis(v_local, r1).transposed()
    return chest.inverted() @ W1, Rx(theta)


def sample_times(spec):
    """Leg IK samples: every half frame (the FBX is baked at 60 fps), plus the exact hit and end."""
    end = spec["length"] * FPS
    return sorted(set(i * 0.5 for i in range(0, math.floor(end * 2) + 1)) | {spec["hit"] * FPS, end})


def build_action(name, spec):
    end = spec["length"] * FPS
    hit = spec["hit"] * FPS
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data.action = act
    for pb in rig.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
        pb.scale = (1, 1, 1)

    hips_lead, torso_lead = spec["lead"]
    prev, report = {}, []
    root = rig.pose.bones["Root"]
    for frame, pose in spec["keys"]:
        edge = frame <= 0 or frame >= end
        fh = frame if edge else max(0.0, frame - hips_lead)
        ft = frame if edge else max(0.0, frame - torso_lead)
        offset, D = pose["hips"]
        key_location(root, offset, fh)
        prev["Root"] = key_rotation(root, D, fh, prev.get("Root"))
        prev["Waist"] = key_rotation(rig.pose.bones["Waist"], pose["Waist"], ft, prev.get("Waist"))
        prev["Neck"] = key_rotation(rig.pose.bones["Neck"], pose["Neck"], frame, prev.get("Neck"))
        for side in ("Right", "Left"):
            if f"{side}Shoulder" in pose:  # hit reactions: plain rotations
                D_sh, D_el = pose[f"{side}Shoulder"], pose[f"{side}Elbow"]
            else:
                D_sh, D_el = solve_arm(side, pose)
            for j, D in ((f"{side}Shoulder", D_sh), (f"{side}Elbow", D_el), (f"{side}Wrist", pose[f"{side}Wrist"])):
                prev[j] = key_rotation(rig.pose.bones[j], D, frame, prev.get(j))
        if spec.get("legs") == "free":
            for side in ("Right", "Left"):
                for j in ("Hip", "Knee", "Ankle"):
                    name = f"{side}{j}"
                    prev[name] = key_rotation(rig.pose.bones[name], pose.get(name, I), frame, prev.get(name))
    if spec.get("legs") != "free":
        for t in sample_times(spec):
            key_legs(t, spec["heel"], prev, report, spec.get("stance"), spec.get("steps"))

    # all keys Bezier, auto-clamped handles (the impact key sits between the anticipation and the
    # over-extension extremes, so the fist is still accelerating through the hit).
    slot = rig.animation_data.action_slot
    from bpy_extras import anim_utils
    cb = anim_utils.action_get_channelbag_for_slot(act, slot)
    for fc in cb.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
            kp.handle_left_type = kp.handle_right_type = "AUTO_CLAMPED"
        fc.update()

    act.use_frame_range = True
    act.frame_start, act.frame_end = 0, end
    act["length_seconds"] = spec["length"]
    act["hit_time"] = spec["hit"]
    act["hit_frame_exact"] = hit
    m = act.pose_markers.new("Hit")
    m.frame = round(hit)
    return act, report


def main():
    scene = bpy.context.scene
    scene.render.fps, scene.render.fps_base = FPS, 1
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    bpy.ops.object.mode_set(mode="OBJECT")
    rig.animation_data_create()
    only = [a for a in sys.argv[sys.argv.index("--") + 1:]] if "--" in sys.argv else []
    for name, spec in ANIMS.items():
        if only and name not in only:
            continue
        act, report = build_action(name, spec)
        print(f"built {name}: {spec['length']:.2f}s = {spec['length'] * FPS:g} frames, "
              f"hit {spec['hit']:.2f}s = frame {spec['hit'] * FPS:g} (marker on {act.pose_markers['Hit'].frame})")
        for line in report:
            print(line)
    first = next(n for n in ANIMS if not only or n in only)
    rig.animation_data.action = bpy.data.actions[first]
    scene.frame_start, scene.frame_end = 0, math.ceil(ANIMS[first]['length'] * FPS)
    scene.frame_set(0)
    out = OUT_BLEND if not only else OUT_BLEND.replace('.blend', '_' + '_'.join(only) + '.blend')
    bpy.ops.wm.save_as_mainfile(filepath=out)
    print("saved", out)


main()

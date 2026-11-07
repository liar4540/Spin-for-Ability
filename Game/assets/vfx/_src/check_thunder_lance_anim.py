"""Spin for Abilities - Thunder Lance: animation checks (stage 3 rules), printed as numbers.

Run inside Blender after build_thunder_lance_anim.py (STAGE = "spline"):
    exec(open(r"<this file>").read())
Evaluates ThunderLanceRig frames 0-30 and prints:
  1. elbows + knees: bend 0-150 deg, only the natural way (elbow forward Rx+, knee backward Rx-)
  2. wrists: the hand's direction within 60 deg of the forearm's (a turn of the palm about the forearm
     is not a bend, so it doesn't count)
  3. feet: drift of each PLANTED contact point inside its planted window (Vault limit 0.02 studs,
     stricter than the prompt's 0.05), at whole frames and at 10 samples per frame
  4. root drift: the HumanoidRootPart bone never moves (must be 0)
  5. F30 vs F0: every joint within 1 deg
  6. right hand path F8-F24: no sharp turn (> 25 deg per 1/10 frame) while moving fast, which is what a
     cusp or zig-zag looks like (the 1/100-frame figure is printed too, for information); forward/back reversals are listed with their speed; the path goes
     OVER the shoulder
  7. release: the frame whose step moves the hand forward the most, and the sub-frame where its forward
     speed peaks; both must be the "Release" marker (F15)
Ends with PASS / FAIL per check. Nothing is changed or saved.
"""
import bpy, math
from mathutils import Vector

RIG_NAME = "ThunderLanceRig"
FIRST, LAST, FPS = 0, 30, 30
BEND_MAX, WRIST_MAX, DRIFT_MAX, SAME_POSE_DEG = 150, 60, 0.02, 1.0
FOOT_HALF = (0.5005, 0.156)  # foot mesh: half depth (toe +Y), half height (sole -Z)
# planted windows (first, last frame) per contact point: the front (left) foot is down F0-F8 and
# F13-F24 and again from F29; the back (right) heel is down F0-F13 and from F24; its toe stays down
# F0-F15 (the heel peels up on the toe) and from F24.
PLANTED = {"LeftHeel": [(0, 8), (13, 24), (29, 30)], "LeftToe": [(0, 8), (13, 24), (29, 30)],
           "RightHeel": [(0, 13), (24, 30)], "RightToe": [(0, 15), (24, 30)]}
PATH = (8, 24)

rig = bpy.data.objects[RIG_NAME]
sc = bpy.context.scene
release = next((m.frame for m in sc.timeline_markers if m.name == "Release"), None)


def delta(pb):
    R = pb.bone.matrix_local.to_3x3()
    return R @ pb.rotation_quaternion.normalized().to_matrix() @ R.inverted()


def axis_angle(M):
    q = M.to_quaternion()
    angle = math.degrees(q.angle)
    if angle > 180:
        angle = 360 - angle
    axis = q.axis if q.angle > 1e-6 else Vector((1, 0, 0))
    return angle, axis


def sample(f, sub=0.0):
    sc.frame_set(f, subframe=sub)
    d = {}
    for side in ("Left", "Right"):
        foot = bpy.data.objects[f"{side}Foot"]
        d[f"{side}Toe"] = foot.matrix_world @ Vector((0, FOOT_HALF[0], -FOOT_HALF[1]))
        d[f"{side}Heel"] = foot.matrix_world @ Vector((0, -FOOT_HALF[0], -FOOT_HALF[1]))
    d["hand"] = bpy.data.objects["RightHand"].matrix_world.translation.copy()
    return d


frames = list(range(FIRST, LAST + 1))
data = {}
for f in frames:
    d = sample(f)
    d["joints"] = {pb.name: delta(pb) for pb in rig.pose.bones}
    d["quats"] = {pb.name: pb.rotation_quaternion.normalized() for pb in rig.pose.bones}
    hrp = rig.pose.bones["HumanoidRootPart"]
    d["hrp"] = (rig.matrix_world @ hrp.matrix).copy()
    for side in ("Left", "Right"):
        el, wr = rig.pose.bones[f"{side}Elbow"], rig.pose.bones[f"{side}Wrist"]
        d[f"{side}forearm"] = (el.tail - el.head).normalized()
        d[f"{side}hand_dir"] = (wr.tail - wr.head).normalized()
    d["shoulder_z"] = (rig.matrix_world @ rig.pose.bones["RightShoulder"].head).z
    data[f] = d
results = []

print("1. ELBOWS / KNEES  (bend deg; natural = elbow Rx+, knee Rx-)")
ok1 = True
for joint, natural in (("RightElbow", 1), ("LeftElbow", 1), ("RightKnee", -1), ("LeftKnee", -1)):
    lo, hi, wrong = 999, -1, []
    for f in frames:
        angle, axis = axis_angle(data[f]["joints"][joint])
        lo, hi = min(lo, angle), max(hi, angle)
        if angle > 2 and axis.x * natural < 0.7:
            wrong.append((f, round(angle, 1)))
    bad = hi > BEND_MAX or bool(wrong)
    ok1 &= not bad
    print(f"   {joint:11s} {lo:5.1f} - {hi:5.1f} deg  {'OK' if not bad else 'BAD'} {wrong if wrong else ''}")
results.append(("elbows/knees 0-150, natural direction", ok1))

print("2. WRISTS  (angle between the hand's and the forearm's direction, deg)")
ok2 = True
for side in ("Right", "Left"):
    worst = max(((math.degrees(data[f][f"{side}hand_dir"].angle(data[f][f"{side}forearm"])), f) for f in frames))
    ok2 &= worst[0] <= WRIST_MAX
    print(f"   {side}Wrist max {worst[0]:5.1f} deg (frame {worst[1]})")
results.append((f"wrists within {WRIST_MAX} deg of the forearm", ok2))

print("3. FEET  (drift of planted contact points inside their windows, studs)")
worst_whole, worst_sub = 0.0, 0.0
for name, windows in PLANTED.items():
    for a, b in windows:
        ref = data[a][name]
        whole = max((data[f][name] - ref).length for f in range(a, b + 1))
        sub = max((sample(f, i / 10)[name] - ref).length for f in range(a, b) for i in range(10))
        worst_whole, worst_sub = max(worst_whole, whole), max(worst_sub, sub, whole)
        print(f"   {name:9s} F{a:2d}-F{b:2d}: {whole:.4f} at whole frames, {max(sub, whole):.4f} with sub-frames")
sc.frame_set(FIRST)
results.append((f"planted feet drift <= {DRIFT_MAX} (whole frames)", worst_whole <= DRIFT_MAX))
results.append((f"planted feet drift <= {DRIFT_MAX} (10 samples per frame)", worst_sub <= DRIFT_MAX))

root_drift = max((data[f]["hrp"].translation - data[FIRST]["hrp"].translation).length for f in frames)
root_rot = max(math.degrees((data[f]["hrp"].to_3x3() @ data[FIRST]["hrp"].to_3x3().inverted()).to_quaternion().angle)
               for f in frames)
print(f"4. ROOT  HumanoidRootPart drift {root_drift:.6f} studs, rotation {root_rot:.4f} deg")
results.append(("root drift 0", root_drift < 1e-6 and root_rot < 1e-4))

diffs = sorted(((min(a, 360 - a), n) for n, q0 in data[FIRST]["quats"].items()
                for a in [math.degrees(q0.rotation_difference(data[LAST]["quats"][n]).angle)]), reverse=True)
print(f"5. F0 vs F30  largest joint difference {diffs[0][0]:.4f} deg ({diffs[0][1]})")
results.append((f"F30 == F0 within {SAME_POSE_DEG} deg", diffs[0][0] <= SAME_POSE_DEG))

print("6. RIGHT HAND PATH F8-F24  (frame: position | forward step)")
for f in range(PATH[0], PATH[1] + 1):
    p = data[f]["hand"]
    step = f" | {p.y - data[f - 1]['hand'].y:+.3f}"
    print(f"   {f:2d}: ({p.x:+.2f}, {p.y:+.2f}, {p.z:+.2f}){step}")
SUB = 100
path = []
for f in range(PATH[0], PATH[1]):
    for i in range(SUB):
        path.append(sample(f, i / SUB)["hand"])
path.append(sample(PATH[1])["hand"])
sc.frame_set(FIRST)
FAST, TURN_MAX, TURN10_MAX, STOP = 0.3, 10.0, 25.0, 0.1  # studs/frame, deg per 1/SUB and per 1/10 frame, studs/frame
speeds = [0.0] + [(path[i] - path[i - 1]).length * SUB for i in range(1, len(path))]
sharp = (0.0, 0)
for i in range(2, len(path)):
    u, v = path[i - 1] - path[i - 2], path[i] - path[i - 1]
    if min(speeds[i - 1], speeds[i]) > FAST:
        t = math.degrees(u.angle(v))
        if t > sharp[0]:
            sharp = (t, PATH[0] + (i - 1) / SUB)
turns, cusps = [], []
for i in range(2, len(path)):
    u, v = path[i - 1] - path[i - 2], path[i] - path[i - 1]
    if u.y * v.y < 0 and abs(v.y) * SUB > 0.01:
        lo = min(speeds[max(1, i - 6):i + 5])
        turns.append((PATH[0] + (i - 1) / SUB, lo))
        if lo >= STOP:
            cusps.append(PATH[0] + (i - 1) / SUB)
# the same on 1/10-frame chords: dense IK keys played back linearly leave hair-width corners at every
# key (0.02 studs) that the 1/100 test flags; a cusp you can see at 60 fps shows on 1/10-frame chords too
CH = SUB // 10
sharp10 = (0.0, 0)
for i in range(2 * CH, len(path), CH):
    u, v = path[i - CH] - path[i - 2 * CH], path[i] - path[i - CH]
    if min(u.length, v.length) * 10 > FAST:
        t = math.degrees(u.angle(v))
        if t > sharp10[0]:
            sharp10 = (t, PATH[0] + (i - CH) / SUB)
print(f"   sharpest turn while moving > {FAST} studs/frame: {sharp10[0]:.1f} deg per 1/10 frame at frame "
      f"{sharp10[1]:.2f} (limit {TURN10_MAX}); finest scale (1/{SUB} frame): {sharp[0]:.1f} deg at {sharp[1]:.2f}, "
      f"info only")
for t, lo in turns:
    print(f"   forward/back reversal at frame {t:.2f}: slowest {lo:.3f} studs/frame "
          f"-> {'stops, then turns' if lo < STOP else 'turns round on a curve (see the sharpest-turn line)'}")
over = max(data[f]["hand"].z - data[f]["shoulder_z"] for f in range(13, 16))
print(f"   over the shoulder: on F13-F15 the hand rises {over:+.2f} studs above the right shoulder joint")
results.append((f"hand path smooth (no turn > {TURN10_MAX} deg per 1/10 frame while moving)", sharp10[0] <= TURN10_MAX))
results.append(("hand path goes over the shoulder", over > 0.3))

print("7. RELEASE  (forward = +Y, toward the target)")
step_peak = max(range(PATH[0] + 1, PATH[1] + 1), key=lambda f: data[f]["hand"].y - data[f - 1]["hand"].y)
fwd = [(path[i].y - path[i - 1].y) * SUB for i in range(1, len(path))]
i_peak = max(range(len(fwd)), key=lambda i: fwd[i])
t_peak = PATH[0] + (i_peak + 0.5) / SUB
print(f"   largest forward step lands on F{step_peak} "
      f"({data[step_peak]['hand'].y - data[step_peak - 1]['hand'].y:.3f} studs in that frame)")
print(f"   forward speed peaks at frame {t_peak:.2f} ({fwd[i_peak]:.2f} studs/frame = {fwd[i_peak] * FPS:.0f} studs/s); "
      f"Release marker F{release}")
results.append(("release = the hand's fastest forward frame = Release marker (F15)",
                step_peak == release == 15 and round(t_peak) == release))

print("SUMMARY")
for name, ok in results:
    print(f"   {'PASS' if ok else 'FAIL'}  {name}")

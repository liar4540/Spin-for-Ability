"""Spin for Abilities - Frost Jab: animation checks (stage 3 rules), printed as numbers.

Run inside Blender after build_frost_jab_anim.py:
    exec(open(r"<this file>").read())
Evaluates every frame 0-13 of FrostJabRig and prints:
  1. elbows + knees: bend 0-150 deg, only the natural way (elbow forward, knee backward)
  2. wrists: hand no more than 60 deg off the forearm; on the hit frame the fist (the hand's knuckle
     end, along the forearm) points at the target
  3. feet: drift of each planted contact point (front foot: heel + toe, flat all the time; back foot:
     toe, its heel lifts on purpose) - must stay <= 0.05 studs
  4. root drift: the HumanoidRootPart bone never moves (must be 0)
  5. first vs last frame: every joint within 1 deg
  6. punching hand path: direction change between frames (no zig-zags), and the frame where the hand
     is furthest forward (must be the "Hit" marker, 0.15 s = frame 4-5)
Ends with PASS / FAIL per check. Nothing is changed or saved.
"""
import bpy, math
from mathutils import Vector

RIG_NAME = "FrostJabRig"
FIRST, LAST, FPS = 0, 13, 30
TARGET = Vector((0, 4.4, 3.2))  # Training Dummy chest, 4.4 studs ahead (stand-in in the previews)
BEND_MAX, WRIST_MAX, DRIFT_MAX, SAME_POSE_DEG, FIST_AIM_MAX = 150, 60, 0.05, 1.0, 30
# local contact points on the foot meshes (Blender axes: +Y = toe, -Z = sole)
FOOT_HALF = (0.5005, 0.156)

rig = bpy.data.objects[RIG_NAME]
sc = bpy.context.scene
hit_frame = next((m.frame for m in sc.timeline_markers if m.name == "Hit"), None)


def delta(pb):
    """The joint rotation D in the parent's rest-aligned frame (what build_frost_jab_anim keyed)."""
    R = pb.bone.matrix_local.to_3x3()
    return R @ pb.rotation_quaternion.normalized().to_matrix() @ R.inverted()  # Blender poses normalized


def axis_angle(M):
    q = M.to_quaternion()
    angle = math.degrees(q.angle)
    if angle > 180:
        angle = 360 - angle
    axis = q.axis if q.angle > 1e-6 else Vector((1, 0, 0))
    return angle, axis


def world(ob, local):
    return ob.matrix_world @ Vector(local)


frames = list(range(FIRST, LAST + 1))
data = {}
for f in frames:
    sc.frame_set(f)
    d = {"joints": {pb.name: delta(pb) for pb in rig.pose.bones},
         "quats": {pb.name: pb.rotation_quaternion.copy() for pb in rig.pose.bones}}
    for side in ("Left", "Right"):
        foot = bpy.data.objects[f"{side}Foot"]
        d[f"{side}Toe"] = world(foot, (0, FOOT_HALF[0], -FOOT_HALF[1]))
        d[f"{side}Heel"] = world(foot, (0, -FOOT_HALF[0], -FOOT_HALF[1]))
    hrp = rig.pose.bones["HumanoidRootPart"]
    d["hrp"] = (rig.matrix_world @ hrp.matrix).copy()
    d["hand"] = bpy.data.objects["RightHand"].matrix_world.translation.copy()
    elbow = rig.pose.bones["RightElbow"]
    wrist = rig.pose.bones["RightWrist"]
    d["forearm"] = ((rig.matrix_world @ elbow.tail) - (rig.matrix_world @ elbow.head)).normalized()
    d["hand_dir"] = ((rig.matrix_world @ wrist.tail) - (rig.matrix_world @ wrist.head)).normalized()
    d["fist"] = rig.matrix_world @ wrist.tail
    data[f] = d
sc.frame_set(FIRST)
results = []

# 1. elbows + knees
print("1. ELBOWS / KNEES  (bend deg, natural = elbow forward Rx+, knee backward Rx-)")
worst = {}
ok1 = True
for joint, natural in (("RightElbow", 1), ("LeftElbow", 1), ("RightKnee", -1), ("LeftKnee", -1)):
    lo, hi, wrong = 999, -1, []
    for f in frames:
        angle, axis = axis_angle(data[f]["joints"][joint])
        lo, hi = min(lo, angle), max(hi, angle)
        if angle > 2 and axis.x * natural < 0.7:  # bends mostly the wrong way / sideways
            wrong.append((f, round(angle, 1), tuple(round(a, 2) for a in axis)))
    bad = hi > BEND_MAX or wrong
    ok1 &= not bad
    print(f"   {joint:11s} {lo:5.1f} - {hi:5.1f} deg  {'OK' if not bad else 'BAD'}  {wrong if wrong else ''}")
results.append(("elbows/knees 0-150, natural direction", ok1))

# 2. wrists + fist aim
print("2. WRISTS  (hand vs forearm, deg)")
ok2 = True
for joint in ("RightWrist", "LeftWrist"):
    hi = max(axis_angle(data[f]["joints"][joint])[0] for f in frames)
    ok2 &= hi <= WRIST_MAX
    print(f"   {joint:11s} max {hi:5.1f} deg")
hf = hit_frame if hit_frame is not None else 4
to_target = (TARGET - data[hf]["fist"]).normalized()
aim = math.degrees(data[hf]["hand_dir"].angle(to_target))
flat_aim = math.degrees(Vector((data[hf]["hand_dir"].x, data[hf]["hand_dir"].y, 0)).angle(
    Vector((to_target.x, to_target.y, 0))))
ok2 &= aim <= FIST_AIM_MAX
print(f"   hit frame {hf}: fist points {aim:.1f} deg off the line to the target ({flat_aim:.1f} deg seen from above)")
results.append((f"wrists <= {WRIST_MAX} deg, fist faces target on hit", ok2))

# 3. feet
print("3. FEET  (drift of planted contact points from frame 0, studs)")
ok3 = True
worst_drift = 0
for name in ("LeftToe", "LeftHeel", "RightToe"):
    drift = max((data[f][name] - data[FIRST][name]).length for f in frames)
    worst_drift = max(worst_drift, drift)
    print(f"   {name:9s} max drift {drift:.4f}")
lift = max(data[f]["RightHeel"].z - data[FIRST]["RightHeel"].z for f in frames)
ok3 = worst_drift <= DRIFT_MAX
print(f"   largest drift {worst_drift:.4f} (limit {DRIFT_MAX}); back heel lifts up to {lift:.3f} on purpose")
results.append((f"planted feet drift <= {DRIFT_MAX}", ok3))

# 4. root
root_drift = max((data[f]["hrp"].translation - data[FIRST]["hrp"].translation).length for f in frames)
root_rot = max(math.degrees((data[f]["hrp"].to_3x3() @ data[FIRST]["hrp"].to_3x3().inverted()).to_quaternion().angle)
               for f in frames)
print(f"4. ROOT  HumanoidRootPart drift {root_drift:.6f} studs, rotation {root_rot:.4f} deg")
results.append(("root drift 0", root_drift < 1e-6 and root_rot < 1e-4))

# 5. first vs last
diffs = []
for name, q0 in data[FIRST]["quats"].items():
    q1 = data[LAST]["quats"][name]
    diffs.append((math.degrees(q0.rotation_difference(q1).angle), name))
diffs.sort(reverse=True)
d5 = diffs[0][0]
d5 = min(d5, 360 - d5)
print(f"5. FIRST vs LAST  largest joint difference {d5:.3f} deg ({diffs[0][1]})")
results.append((f"first == last within {SAME_POSE_DEG} deg", d5 <= SAME_POSE_DEG))

# 6. hand path: whole frames for the table, then 10 samples per frame (what Motion Paths draws) for
# the smoothness test. A smooth arc turns gradually; a cusp/zig-zag turns hard while still moving fast.
print("6. PUNCHING HAND PATH  (frame: position | step studs)")
for f in frames:
    p = data[f]["hand"]
    step = f" | {(p - data[f - 1]['hand']).length:.3f}" if f > FIRST else ""
    print(f"   {f:2d}: ({p.x:+.2f}, {p.y:+.2f}, {p.z:+.2f}){step}")
SUB = 100
hand_ob = bpy.data.objects["RightHand"]
path = []
for f in range(FIRST, LAST):
    for i in range(SUB):
        sc.frame_set(f, subframe=i / SUB)
        path.append(hand_ob.matrix_world.translation.copy())
sc.frame_set(LAST)
path.append(hand_ob.matrix_world.translation.copy())
sc.frame_set(FIRST)
FAST, TURN_MAX, STOP = 0.3, 10.0, 0.1  # studs/frame, deg per 1/SUB frame, studs/frame
speeds = [0.0] + [(path[i] - path[i - 1]).length * SUB for i in range(1, len(path))]
sharp, y_turns = (0.0, 0), []
for i in range(2, len(path)):
    u, v = path[i - 1] - path[i - 2], path[i] - path[i - 1]
    if min(speeds[i - 1], speeds[i]) > FAST:
        t = math.degrees(u.angle(v))
        if t > sharp[0]:
            sharp = (t, (i - 1) / SUB)
    if u.y * v.y < 0 and abs(v.y) * SUB > 0.01:
        y_turns.append(i - 1)
peak = max(frames, key=lambda f: data[f]["hand"].y)
print(f"   hand furthest forward on frame {peak} ({peak / FPS:.3f} s); 'Hit' marker frame {hit_frame}")
print(f"   sub-frame path ({SUB}/frame): sharpest turn while moving > {FAST} studs/frame: {sharp[0]:.1f} deg "
      f"in 1/{SUB} frame at frame {sharp[1]:.2f} (limit {TURN_MAX})")
cusps = []
for i in y_turns:
    lo = min(speeds[max(1, i - 5):i + 6])  # slowest point within +-0.05 frame of the reversal
    kind = "full stop, then turns round" if lo < STOP else "CUSP: turns round while moving"
    if lo >= STOP:
        cusps.append(i / SUB)
    print(f"   forward/back reversal at frame {i / SUB:.2f}: slowest {lo:.3f} studs/frame -> {kind}")
print(f"   ({len(y_turns)} reversals; a jab has 2: the wind-up apex and after the hit)")
results.append((f"hand peak frame == Hit marker, in 4-5", peak == hit_frame and 4 <= peak <= 5))
results.append((f"hand path smooth: no turn > {TURN_MAX} deg per 1/{SUB} frame while moving, "
                f"reversals only at a stop, <= 2", sharp[0] <= TURN_MAX and not cusps and len(y_turns) <= 2))

print("SUMMARY")
for name, ok in results:
    print(f"   {'PASS' if ok else 'FAIL'}  {name}")

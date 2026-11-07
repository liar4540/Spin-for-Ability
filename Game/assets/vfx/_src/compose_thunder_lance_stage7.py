"""Spin for Abilities - Thunder Lance stage 7: 12 blueprint panels next to the same moments in Studio.

Run with the system Python (needs Pillow):
    python compose_thunder_lance_stage7.py <capture dir> <casts> <out name> [label] [speed]
<casts> is the client's TL_CastMs attribute: "<unix ms>:<pose|flight>,..." - the wall time each
/vfxtest lance cast started and which scripted camera it used (pose = side view of the thrower, target
to the right; flight = tracking the spear, then the impact seen from the thrower's side). The capture
dir holds Studio window captures named <unix ms>.png (capture_studio_window.ps1 burst, same machine
clock as the client's DateTime.now()). A capture at wall time T in a cast started at S shows game time
(T - S) / 1000 * speed (default 0.25). Every panel uses the nearest non-black capture over all casts
with its camera (PrintWindow sometimes returns a black viewport).
The reference sheet with 12 panels was never provided; the 12 panels are cut from
images/abilities/thunder_lance_blueprint.png (key poses F0-F30, spear construction, trail, impact).
Writes Game/assets/vfx/previews/<out name>.png: reference row over Studio row, 6 panels per band.
"""
import glob, os, sys
from PIL import Image, ImageDraw, ImageFont, ImageStat

REF = r"C:\Roblox\Spin for ability\images\abilities\thunder_lance_blueprint.png"
PREV = r"C:\Roblox\Spin for ability\Game\assets\vfx\previews"
VIEWPORT = (584, 350, 2064, 1320)  # Studio 3D viewport inside the window capture, above the hotbar
K = 2400 / 2253  # blueprint pixels per pixel of the 2253-wide view the boxes were measured on
POSE_X = [57, 235, 413, 591, 769, 947]
HIT = 0.5 + (40 - 4 - 2.5) / 160  # release + the tip's flight until the 2.5-stud hitbox touches the dummy


def box(x0, y0, x1, y1):
    return tuple(round(v * K) for v in (x0, y0, x1, y1))


ART = box(140, 1080, 500, 1450)
# panel number, title, camera, game time (s since the cast), reference boxes (stacked top to bottom)
PANELS = [(i + 1, title, "pose", t, [box(POSE_X[i], 180, POSE_X[i] + 168, 530)])
          for i, (title, t) in enumerate([("F0 Ready", 0.01), ("F4 Summon", 4 / 30 + 0.02), ("F12 Wind-up", 12 / 30),
                                          ("F15 Release", 15 / 30 + 0.01), ("F18 Follow-through", 18 / 30),
                                          ("F30 Ready", 1.0)])]
PANELS += [
    (7, "Spear in flight", "flight", 0.545, [box(1460, 175, 2215, 330)]),
    (8, "Crackling trail", "flight", 0.64, [box(1175, 170, 1500, 345)]),
    (9, "Impact flash (+1 frame)", "flight", HIT + 1 / 30, [ART, box(520, 1062, 705, 1108)]),
    (10, "Spark burst + shock ring", "flight", HIT + 0.09, [ART, box(520, 1135, 705, 1280)]),
    (11, "Arcs on target", "flight", HIT + 0.35, [ART, box(520, 1347, 705, 1420)]),
    (12, "Scorch decal", "flight", HIT + 1.3, [box(130, 1370, 490, 1480)]),
]
CW, CH = 300, 220


def font(size, bold=True):
    for name in (("segoeuib.ttf" if bold else "segoeui.ttf"), "arialbd.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def contain(img, w, h, bg):
    img = img.copy()
    img.thumbnail((w, h), Image.LANCZOS)
    out = Image.new("RGB", (w, h), bg)
    out.paste(img, ((w - img.width) // 2, (h - img.height) // 2))
    return out


def reference(boxes):
    sheet = Image.open(REF).convert("RGB")
    parts = [sheet.crop(b) for b in boxes]
    w = max(p.width for p in parts)
    stack = Image.new("RGB", (w, sum(p.height for p in parts)), (15, 27, 45))
    y = 0
    for p in parts:
        stack.paste(p, ((w - p.width) // 2, y))
        y += p.height
    return contain(stack, CW, CH, (15, 27, 45))


def fill(img):
    """Centre-crop to the cell aspect, then scale."""
    w, h = img.size
    target = CW / CH
    if w / h > target:
        nw = round(h * target)
        img = img.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
    else:
        nh = round(w / target)
        img = img.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
    return img.resize((CW, CH), Image.LANCZOS)


def main():
    cap_dir, casts_arg, out_name = sys.argv[1], sys.argv[2], sys.argv[3]
    label = sys.argv[4] if len(sys.argv) > 4 else ""
    speed = float(sys.argv[5]) if len(sys.argv) > 5 else 0.25
    casts = [(int(ms), mode) for ms, mode in (c.split(":") for c in casts_arg.split(","))]
    caps = sorted(int(os.path.basename(p)[:-4]) for p in glob.glob(os.path.join(cap_dir, "*.png"))
                  if os.path.basename(p)[:-4].isdigit())
    lo, hi = caps[0], caps[-1]
    black = {}

    def is_black(ms):
        if ms not in black:
            img = Image.open(os.path.join(cap_dir, f"{ms}.png")).convert("L").crop(VIEWPORT).resize((48, 32))
            black[ms] = ImageStat.Stat(img).mean[0] < 10
        return black[ms]

    pad, head, lab = 8, 58, 22
    W = pad + 6 * (CW + pad)
    band_h = 2 * (CH + lab) + pad * 3
    sheet = Image.new("RGB", (W, head + 2 * band_h), (24, 26, 33))
    d = ImageDraw.Draw(sheet)
    d.text((pad, 10), f"Thunder Lance - Stage 7: blueprint (top) vs Studio (bottom) {label}", fill=(242, 251, 255), font=font(22))
    d.text((pad, 36), f"Studio: /vfxtest lance (real ThunderLanceVFX + uploaded animation) at {speed}x, dummy 40 studs away; "
           "frame chosen by game time", fill=(255, 225, 77), font=font(13, False))
    for i, (n, title, mode, t, boxes) in enumerate(PANELS):
        band, col = divmod(i, 6)
        x = pad + col * (CW + pad)
        y = head + band * band_h
        best = None
        for start, m in casts:
            want = start + t / speed * 1000
            if m != mode or want < lo or want > hi:
                continue
            for ms in sorted(caps, key=lambda c: abs(c - want))[:12]:
                if not is_black(ms):
                    got = (ms - start) / 1000 * speed
                    if best is None or abs(got - t) < abs(best[0] - t):
                        best = (got, ms)
                    break
        d.text((x + 2, y), f"{n}. {title}", fill=(255, 225, 77), font=font(14))
        sheet.paste(reference(boxes), (x, y + lab - 2))
        y2 = y + CH + lab + pad
        if best:
            got, ms = best
            d.text((x + 2, y2), f"Studio t = {got:.3f} s (frame {got * 30:.1f})", fill=(220, 225, 235), font=font(13, False))
            sheet.paste(fill(Image.open(os.path.join(cap_dir, f"{ms}.png")).convert("RGB").crop(VIEWPORT)), (x, y2 + lab - 2))
            print(f"  panel {n:2d}: wanted {t:.3f} s, got {got:.3f} s ({ms})")
        else:
            d.text((x + 2, y2), "no capture", fill=(255, 120, 120), font=font(13, False))
            print(f"  panel {n:2d}: no capture")
    out = os.path.join(PREV, out_name + ".png")
    sheet.save(out)
    print("wrote", out, sheet.size)


main()

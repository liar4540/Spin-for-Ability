"""Spin for Abilities - Frost Jab stage 7: the 12 reference panels next to the same moments in Studio.

Run with the system Python (needs Pillow):
    python compose_frost_jab_stage7.py <capture dir> <cast start unix ms> <speed> <out name> [label]
The capture dir holds Studio viewport captures named <unix ms>.png (PowerShell PrintWindow burst,
same machine clock as the client's DateTime.now()). The cast ran at <speed> (e.g. 0.1), so a capture
at wall time T shows game time (T - start) / 1000 * speed. For every panel the capture nearest its
moment is used (the panel's frame number at 30 fps; "+N s" panels = N s after the hit).
Writes Game/assets/vfx/previews/<out name>.png: reference row over Studio row, 6 panels per band.
"""
import glob, os, sys
from PIL import Image, ImageDraw, ImageFont

REF = r"C:\Roblox\Spin for ability\images\abilities\frost jab.png"
PREV = r"C:\Roblox\Spin for ability\Game\assets\vfx\previews"
COLS = [(13, 259), (266, 512), (519, 765), (772, 1018), (1025, 1274), (1280, 1524)]
ROWS = [(115, 528), (551, 964)]
HIT = 4 / 30
# panel number, title, game time (s since the key press)
PANELS = [(1, "F0 Idle", 0.004), (2, "F2 Wind-Up", 2 / 30), (3, "F4 Impact", 4 / 30), (4, "F5 Shard Burst", 5 / 30),
          (5, "F6 Frost Ring", 6 / 30), (6, "F8 Ring Expands", 8 / 30), (7, "F10 Recovery", 10 / 30),
          (8, "F13 Ready", 13 / 30), (9, "+0.5s Slowed", HIT + 0.5), (10, "+1.0s Frost Thinning", HIT + 1.0),
          (11, "+1.5s Frost Breaks", HIT + 1.56), (12, "Finished", HIT + 2.3)]
CW, CH = 246, 330


def font(size, bold=True):
    for name in (("segoeuib.ttf" if bold else "segoeui.ttf"), "arialbd.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def panel(n):
    row, col = divmod(n - 1, 6)
    (x0, x1), (y0, y1) = COLS[col], ROWS[row]
    return Image.open(REF).convert("RGB").crop((x0, y0 + 40, x1, y1))  # below the panel's title bar


def fit(img):
    """Centre-crop to the panel aspect, then scale."""
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
    cap_dir, start, speed, out_name = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
    label = sys.argv[5] if len(sys.argv) > 5 else ""
    caps = sorted((int(os.path.basename(p)[:-4]), p) for p in glob.glob(os.path.join(cap_dir, "*.png")))
    pad, head, lab = 8, 58, 24
    W = pad + 6 * (CW + pad)
    H = head + 2 * (2 * (CH + lab) + pad * 3)
    sheet = Image.new("RGB", (W, H), (24, 26, 33))
    d = ImageDraw.Draw(sheet)
    d.text((pad, 10), f"Frost Jab - Stage 7: reference (top) vs Studio (bottom) {label}", fill=(242, 251, 255), font=font(22))
    d.text((pad, 36), f"Studio: real FrostJabVFX + uploaded animation at {speed}x, frame chosen by game time; "
           "the attacker is a blocky R15 dummy coloured like the reference", fill=(168, 230, 255), font=font(13, False))
    picked = []
    for i, (n, title, t) in enumerate(PANELS):
        band, col = divmod(i, 6)
        x = pad + col * (CW + pad)
        y = head + band * (2 * (CH + lab) + pad * 3)
        want = start + t / speed * 1000
        ms, path = min(caps, key=lambda c: abs(c[0] - want))
        got = (ms - start) / 1000 * speed
        picked.append((n, t, got))
        d.text((x + 2, y), f"{n}. {title}", fill=(255, 220, 60), font=font(14))
        sheet.paste(fit(panel(n)), (x, y + lab - 4))
        y2 = y + CH + lab + pad
        d.text((x + 2, y2), f"Studio t = {got:.3f} s (frame {got * 30:.1f})", fill=(220, 225, 235), font=font(13, False))
        sheet.paste(fit(Image.open(path).convert("RGB")), (x, y2 + lab - 4))
    out = os.path.join(PREV, out_name + ".png")
    sheet.save(out)
    print("wrote", out, sheet.size)
    for n, t, got in picked:
        print(f"  panel {n:2d}: wanted {t:.3f} s, got {got:.3f} s")


main()

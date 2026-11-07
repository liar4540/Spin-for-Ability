"""Spin for Abilities - Frost Jab stage 2 sheet: reference panel | side | 3/4 front, per key pose.

Run with the system Python (needs Pillow), after render_frost_jab_poses.py:
    python compose_frost_jab_stage2.py
Writes Game/assets/vfx/previews/frost_jab_stage2_poses.png.
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = r"C:\Roblox\Spin for ability"
REF = os.path.join(ROOT, "images", "abilities", "frost jab.png")
POSES = os.path.join(ROOT, "Game", "assets", "vfx", "previews", "frost_jab")
OUT = os.path.join(ROOT, "Game", "assets", "vfx", "previews", "frost_jab_stage2_poses.png")

# Reference panel boxes in the 1536x1024 sheet (panel numbers 1-12), measured on the panels' 1-px
# border lines (border included, so each crop shows its "N. Fx - name" title bar and no outside strip).
COLS = [(13, 259), (266, 512), (519, 765), (772, 1018), (1025, 1274), (1280, 1524)]
ROWS = [(115, 528), (551, 964)]

# frame, panel, label
SHOTS = [(0, 1, "ready"), (2, 2, "wind-up"), (4, 3, "HIT  (marker)"), (5, 4, "overshoot"),
         (6, 5, "hold"), (10, 7, "recovery"), (13, 8, "ready (= 0)")]
CW, CH, PAD, LABEL = 270, 360, 8, 26


def panel(n):
    row, col = divmod(n - 1, 6)
    (x0, x1), (y0, y1) = COLS[col], ROWS[row]
    return Image.open(REF).convert("RGB").crop((x0, y0, x1, y1))


def font(size):
    for name in ("segoeuib.ttf", "arialbd.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def fit(img):
    img = img.copy()
    img.thumbnail((CW, CH))
    cell = Image.new("RGB", (CW, CH), (20, 21, 26))
    cell.paste(img, ((CW - img.width) // 2, (CH - img.height) // 2))
    return cell


def main():
    rows = [("Reference", lambda f, p: panel(p)),
            ("Side (forward = right)", lambda f, p: Image.open(os.path.join(POSES, f"pose_side_{f:02d}.png"))),
            ("3/4 front", lambda f, p: Image.open(os.path.join(POSES, f"pose_34_{f:02d}.png")))]
    W = PAD + len(SHOTS) * (CW + PAD)
    H = PAD + len(rows) * (LABEL * 2 + CH + PAD)
    sheet = Image.new("RGB", (W, H), (32, 33, 38))
    d = ImageDraw.Draw(sheet)
    big, small = font(20), font(15)
    y = PAD
    for title, get in rows:
        d.text((PAD, y), title, fill=(235, 235, 240), font=big)
        y += LABEL
        for i, (f, p, label) in enumerate(SHOTS):
            x = PAD + i * (CW + PAD)
            marker = "HIT" in label
            d.text((x + 4, y), f"frame {f}  {label}" + ("" if title != "Reference" else f"  (panel {p})"),
                   fill=(168, 230, 255) if marker else (210, 210, 215), font=small)
            sheet.paste(fit(get(f, p)), (x, y + LABEL))
        y += LABEL + CH + PAD
    sheet.save(OUT)
    print("wrote", OUT, sheet.size)


main()

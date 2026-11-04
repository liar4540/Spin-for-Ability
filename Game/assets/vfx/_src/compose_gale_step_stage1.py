"""Spin for Abilities - Gale Step stage 1 sheet: reference panel | side | 3/4 front, per key frame.

Run with the system Python (needs Pillow), after render_gale_step_poses.py:
    python compose_gale_step_stage1.py
Writes Game/assets/vfx/previews/gale_step_stage1_poses.png.
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = r"C:\Roblox\Spin for ability"
REF = os.path.join(ROOT, "images", "abilities", "gale step.png")
POSES = os.path.join(ROOT, "Game", "assets", "vfx", "previews", "gale_step")
OUT = os.path.join(ROOT, "Game", "assets", "vfx", "previews", "gale_step_stage1_poses.png")

# Reference panel boxes in the 1536x1024 sheet (panel numbers 1-12, header strip excluded).
COLS = [(18, 260), (268, 509), (517, 762), (770, 1022), (1030, 1271), (1279, 1519)]
ROWS = [(152, 523), (586, 951)]


def panel(n):
    row, col = divmod(n - 1, 6)
    (x0, x1), (y0, y1) = COLS[col], ROWS[row]
    return Image.open(REF).convert("RGB").crop((x0, y0, x1, y1))


# frame, panel, label
SHOTS = [(0, 1, "idle"), (4, 2, "charge"), (6, 3, "launch  DashStart"), (12, 5, "dash hold"),
         (17, 7, "brake  DashEnd"), (22, 8, "settle"), (36, 12, "idle")]
CW, CH, PAD, LABEL = 300, 400, 8, 26


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
    big, small = font(20), font(16)
    y = PAD
    for title, get in rows:
        d.text((PAD, y), title, fill=(235, 235, 240), font=big)
        y += LABEL
        for i, (f, p, label) in enumerate(SHOTS):
            x = PAD + i * (CW + PAD)
            marker = "DashStart" in label or "DashEnd" in label
            d.text((x + 4, y), f"frame {f}  {label}" + ("" if title != "Reference" else f"  (panel {p})"),
                   fill=(255, 210, 90) if marker else (210, 210, 215), font=small)
            sheet.paste(fit(get(f, p)), (x, y + LABEL))
        y += LABEL + CH + PAD
    sheet.save(OUT)
    print("wrote", OUT, sheet.size)


main()

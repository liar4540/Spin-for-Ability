"""Spin for Abilities - Thunder Lance stage 2 sheet: blueprint pose panel | side | 3/4 front, per key.

Run with the system Python (needs Pillow), after render_thunder_lance_poses.py:
    python compose_thunder_lance_stage2.py
The reference is images/abilities/thunder_lance_blueprint.png, section 1 (6 key poses: F0, F4, F12,
F15, F18, F30). The 12-panel sheet named in the prompt was never provided, so the in-between keys
(F8, F13, F14, F24) have no reference panel.
Writes Game/assets/vfx/previews/thunder_lance_stage2_poses.png.
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = r"C:\Roblox\Spin for ability"
REF = os.path.join(ROOT, "images", "abilities", "thunder_lance_blueprint.png")
POSES = os.path.join(ROOT, "Game", "assets", "vfx", "previews", "thunder_lance")
OUT = os.path.join(ROOT, "Game", "assets", "vfx", "previews", "thunder_lance_stage2_poses.png")

# Blueprint section 1 panel boxes (2400x1760 sheet): 6 columns, measured on the panel borders.
PANEL_X = [(50, 240), (240, 430), (430, 620), (620, 810), (810, 1000), (1000, 1190)]
PANEL_Y = (190, 562)
# frame, blueprint panel (1-6 or None), label
SHOTS = [(0, 1, "ready"), (4, 2, "SUMMON (marker)"), (8, None, "spear formed"), (12, 3, "wind-up peak"),
         (13, None, "hold"), (14, None, "whip"), (15, 4, "RELEASE (marker)"), (18, 5, "follow-through"),
         (24, None, "settle"), (30, 6, "ready (= F0)")]
CW, CH, PAD, LABEL = 230, 320, 8, 24


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


def crop_pose(img):
    """Pose renders are 600x800 with the character in the middle; trim the empty floor and sky."""
    return img.crop((70, 160, 530, 720))


def main():
    ref = Image.open(REF).convert("RGB")

    def ref_cell(f, p):
        if p is None:
            cell = Image.new("RGB", (CW, CH), (20, 21, 26))
            d = ImageDraw.Draw(cell)
            d.text((14, CH // 2 - 10), "no reference panel", fill=(120, 124, 135), font=font(16))
            return cell
        x0, x1 = PANEL_X[p - 1]
        return fit(ref.crop((x0, PANEL_Y[0], x1, PANEL_Y[1])))

    rows = [("Blueprint (section 1)", ref_cell),
            ("Side (target to the right)", lambda f, p: fit(crop_pose(Image.open(os.path.join(POSES, f"pose_side_{f:02d}.png")).convert("RGB")))),
            ("3/4 front", lambda f, p: fit(crop_pose(Image.open(os.path.join(POSES, f"pose_34_{f:02d}.png")).convert("RGB"))))]
    W = PAD + len(SHOTS) * (CW + PAD)
    H = 44 + PAD + len(rows) * (LABEL * 2 + CH + PAD)
    sheet = Image.new("RGB", (W, H), (32, 33, 38))
    d = ImageDraw.Draw(sheet)
    d.text((PAD, 10), "Thunder Lance - Stage 2: blocking (stepped keys). Yellow = 6-stud stand-in spear, grip on RightHand, aimed at the target.",
           fill=(242, 251, 255), font=font(20))
    y = 44 + PAD
    for title, get in rows:
        d.text((PAD, y), title, fill=(235, 235, 240), font=font(19))
        y += LABEL
        for i, (f, p, label) in enumerate(SHOTS):
            x = PAD + i * (CW + PAD)
            marker = label.isupper() or "(marker)" in label
            d.text((x + 4, y), f"F{f}  {label}" + (f"  [panel {p}]" if title.startswith("Blueprint") and p else ""),
                   fill=(255, 220, 60) if marker else (210, 210, 215), font=font(14))
            sheet.paste(get(f, p), (x, y + LABEL))
        y += LABEL + CH + PAD
    sheet.save(OUT)
    print("wrote", OUT, sheet.size)


main()

"""Spin for Abilities - Frost Jab stage 1 sheet: Studio dummy | Blender rig (front views) + joint table.

Run with the system Python (needs Pillow), after build_frost_jab_rig.py:
    python compose_frost_jab_stage1.py
Inputs in Game/assets/vfx/previews/frost_jab/:
    studio_front.png   Studio window capture: Training Dummy from the front, a yellow marker on every
                       joint (Attachment0.WorldPosition), camera 25 studs out, 7 studs tall view
    blender_front.png  Blender viewport render: FrostJabRig, ortho front camera, 6.2 studs tall view
Writes Game/assets/vfx/previews/frost_jab_stage1_rig.png. Both views are scaled to the same
pixels per stud and lined up on the floor, so matching joints sit at the same height.
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = r"C:\Roblox\Spin for ability\Game\assets\vfx\previews"
SHOTS = os.path.join(ROOT, "frost_jab")
OUT = os.path.join(ROOT, "frost_jab_stage1_rig.png")

PX_PER_STUD = 110
VIEW_H = 5.7  # studs shown, floor to top (head top is 5.27)
# Studio: viewport box in the window capture, studs it spans vertically, floor row in the capture
STUDIO_BOX, STUDIO_STUDS, STUDIO_FLOOR = (294, 177, 1033, 850), 7.0, 767
# Blender: whole render, 6.2 studs tall (ortho scale on the long side), floor row
BLENDER_STUDS, BLENDER_FLOOR = 6.2, 729

# joint, Studio (rig-local Roblox), Blender bone head (Blender axes), error - printed by build_frost_jab_rig.py
TABLE = [
    ("Root", "(0, -1.0000, 0)", "(0, 0, 2.1924)", "0.0000"),
    ("Waist", "(0, -0.5995, 0)", "(0, 0, 2.5930)", "0.0001"),
    ("Neck", "(0, 1.0986, 0)", "(0, 0, 4.2910)", "0.0000"),
    ("L/R Shoulder", "(±0.9716, 0.8471, 0)", "(±0.9716, 0, 4.0395)", "0.0000"),
    ("L/R Elbow", "(±1.4717/1.4721, 0.0732, 0)", "(±1.4717/1.4721, 0, 3.2656)", "0.0001"),
    ("L/R Wrist", "(±1.4717/1.4721, -0.7338, 0)", "(±1.4717/1.4721, 0, 2.4587)", "0.0001"),
    ("L/R Hip", "(±0.4979, -1.0000, 0)", "(±0.4979, 0, 2.1924)", "0.0001"),
    ("L/R Knee", "(±0.4979, -1.9207, 0)", "(±0.4979, 0, 1.2718)", "0.0001"),
    ("L/R Ankle", "(±0.4979, -2.9304, 0)", "(±0.4979, 0, 0.2620)", "0.0001"),
]


def font(size, bold=False):
    for name in (("segoeuib.ttf" if bold else "segoeui.ttf"), "arial.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def fit(img, studs_tall, floor_row):
    """Scale to PX_PER_STUD and crop to VIEW_H studs above the floor (+0.3 below), 5 studs wide."""
    scale = PX_PER_STUD * studs_tall / img.height
    img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    floor = floor_row * scale
    w = 5 * PX_PER_STUD
    cx = img.width / 2
    box = (round(cx - w / 2), round(floor - VIEW_H * PX_PER_STUD), round(cx + w / 2), round(floor + 0.3 * PX_PER_STUD))
    return img.crop(box)


studio = Image.open(os.path.join(SHOTS, "studio_front.png")).convert("RGB").crop(STUDIO_BOX)
studio = fit(studio, STUDIO_STUDS, STUDIO_FLOOR - STUDIO_BOX[1])
blender = fit(Image.open(os.path.join(SHOTS, "blender_front.png")).convert("RGB"), BLENDER_STUDS, BLENDER_FLOOR)

pad, title_h, table_h = 24, 56, 40 + 30 * (len(TABLE) + 2)
W = pad * 3 + studio.width + blender.width
H = title_h + studio.height + pad * 2 + table_h
sheet = Image.new("RGB", (W, H), (24, 26, 33))
d = ImageDraw.Draw(sheet)
d.text((pad, 14), "Frost Jab - Stage 1: rig match (front view)", fill=(242, 251, 255), font=font(26, True))
for i, (img, label) in enumerate(((studio, "Studio: Training Dummy (joint markers)"), (blender, "Blender: FrostJabRig (bone heads)"))):
    x = pad + i * (studio.width + pad)
    sheet.paste(img, (x, title_h))
    d.text((x + 8, title_h + 6), label, fill=(255, 220, 60), font=font(18, True))
    # floor line and 1-stud ticks
    for s in range(0, 6):
        y = title_h + round(VIEW_H * PX_PER_STUD) - s * PX_PER_STUD
        d.line((x, y, x + 10, y), fill=(168, 230, 255), width=2)
        d.text((x + 13, y - 10), f"{s}", fill=(168, 230, 255), font=font(14))

y = title_h + studio.height + pad
cols = (pad, pad + 160, pad + 470, pad + 800)
for cx, head in zip(cols, ("Joint", "Studio (rig-local, Y up)", "Blender bone head (Z up)", "Error (studs)")):
    d.text((cx, y), head, fill=(168, 230, 255), font=font(17, True))
for r, row in enumerate(TABLE):
    for cx, cell in zip(cols, row):
        d.text((cx, y + 30 * (r + 1)), cell, fill=(230, 236, 245), font=font(16))
d.text((pad, y + 30 * (len(TABLE) + 1) + 4),
       "Worst joint error 0.0001 studs, worst part size error 0.0000. Same 15 joint names, same parents. "
       "Blender = Roblox (x, -z, y), floor at Z = 0.\n"
       "Studio is a perspective camera (markers sit 0.6 studs in front of the body), so its joints look "
       "about 2% higher; the numbers above are exact.", fill=(255, 220, 60), font=font(15))
sheet.save(OUT)
print("saved", OUT, sheet.size)

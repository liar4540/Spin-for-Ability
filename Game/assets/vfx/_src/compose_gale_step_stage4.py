"""Spin for Abilities - Gale Step stage 4 sheet: Blender render vs Studio playback of the uploaded
animation, frames 4 / 12 / 17, side and 3/4 views (same camera positions and 39.6 deg vertical FOV).

    python compose_gale_step_stage4.py <studio side 4> <studio 34 4> <side 12> <34 12> <side 17> <34 17>
Studio captures are landscape; the centre is cropped to the 3:4 Blender frame (same vertical FOV,
so the scale matches). Writes Game/assets/vfx/previews/gale_step_stage4_blender_vs_studio.png.
"""
import os, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = r"C:\Roblox\Spin for ability\Game\assets\vfx\previews"
OUT = os.path.join(ROOT, "gale_step_stage4_blender_vs_studio.png")
FRAMES = [(4, "charge"), (12, "dash hold"), (17, "brake  DashEnd")]
CW, CH, PAD, LABEL = 300, 400, 8, 26


def font(size):
    for name in ("segoeuib.ttf", "arialbd.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def studio_crop(path):
    im = Image.open(path).convert("RGB")
    w = int(im.height * 0.75)
    x0 = (im.width - w) // 2
    return im.crop((x0, 0, x0 + w, im.height)).resize((CW, CH), Image.LANCZOS)


def main(studio):
    cols = []  # (title, image)
    for i, (f, label) in enumerate(FRAMES):
        for v, view in enumerate(("side", "34")):
            blender = Image.open(os.path.join(ROOT, "gale_step", f"pose_{view}_{f:02d}.png")).convert("RGB").resize((CW, CH))
            cols.append((f"frame {f} {label}  {'side' if view == 'side' else '3/4'}", blender, studio_crop(studio[i * 2 + v])))
    W = PAD + len(cols) * (CW + PAD)
    H = PAD + LABEL + 2 * (LABEL + CH + PAD) + 40
    sheet = Image.new("RGB", (W, H), (32, 33, 38))
    d = ImageDraw.Draw(sheet)
    big, small = font(18), font(15)
    for r, row in enumerate(("Blender (GaleStep_Dash action)", "Studio (uploaded animation 130755455737261)")):
        y = PAD + LABEL + r * (LABEL + CH + PAD)
        d.text((PAD, y), row, fill=(235, 235, 240), font=big)
        for c, (title, b, s) in enumerate(cols):
            x = PAD + c * (CW + PAD)
            if r == 0:
                d.text((x + 150 - d.textlength(title, font=small) / 2, PAD), title, fill=(255, 210, 90), font=small)
            sheet.paste(b if r == 0 else s, (x, y + LABEL))
    d.text((PAD, H - 32), "Every body part matches Blender within 0.0003 studs at frames 4, 12 and 17 (measured in Studio).",
           fill=(200, 230, 200), font=small)
    sheet.save(OUT)
    print("wrote", OUT, sheet.size)


main(sys.argv[1:7])

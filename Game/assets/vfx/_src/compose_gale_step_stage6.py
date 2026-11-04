"""Spin for Abilities - Gale Step stage 6 sheet: reference panels 2, 3, 5, 7, 9, 11 above the matching
Studio playtest moments (0.12 / 0.22 / 0.35 / 0.58 / 0.85 / 1.1 s).

    python compose_gale_step_stage6.py <out.png> <title> <shot>:<cx>:<cy> x6
Each shot is a Studio capture; (cx, cy) is the pixel to centre the crop on (the character). The crop
has the reference panel's aspect, so both rows line up.
"""
import os, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = r"C:\Roblox\Spin for ability"
REF = os.path.join(ROOT, "images", "abilities", "gale step.png")
COLS = [(18, 260), (268, 509), (517, 762), (770, 1022), (1030, 1271), (1279, 1519)]
ROWS = [(152, 523), (586, 951)]
PANELS = [(2, "0.12 s charge"), (3, "0.22 s dash start"), (5, "0.35 s mid dash"),
          (7, "0.58 s finish"), (9, "0.85 s dissipating"), (11, "1.1 s residual")]
CW, CH, PAD, LABEL = 280, 430, 8, 26
CROP_H = 840  # Studio pixels; width follows the panel aspect


def font(size):
    for name in ("segoeuib.ttf", "arialbd.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def panel(n):
    row, col = divmod(n - 1, 6)
    (x0, x1), (y0, y1) = COLS[col], ROWS[row]
    return Image.open(REF).convert("RGB").crop((x0, y0, x1, y1)).resize((CW, CH), Image.LANCZOS)


def shot(spec):
    path, cx, cy = spec.rsplit(":", 2)
    im = Image.open(path).convert("RGB")
    h = min(CROP_H, im.height)
    w = int(h * CW / CH)
    x0 = max(0, min(im.width - w, int(cx) - w // 2))
    y0 = max(0, min(im.height - h, int(cy) - h // 2))
    return im.crop((x0, y0, x0 + w, y0 + h)).resize((CW, CH), Image.LANCZOS)


def main(out, title, specs):
    W = PAD + len(PANELS) * (CW + PAD)
    H = PAD + 30 + 2 * (LABEL + CH + PAD)
    sheet = Image.new("RGB", (W, H), (32, 33, 38))
    d = ImageDraw.Draw(sheet)
    d.text((PAD, PAD), title, fill=(240, 240, 245), font=font(20))
    for r in range(2):
        y = PAD + 30 + r * (LABEL + CH + PAD)
        for c, (n, label) in enumerate(PANELS):
            x = PAD + c * (CW + PAD)
            text = f"reference panel {n}" if r == 0 else f"Studio {label}"
            d.text((x + 4, y + 3), text, fill=(255, 210, 90) if r else (215, 215, 220), font=font(15))
            sheet.paste(panel(n) if r == 0 else shot(specs[c]), (x, y + LABEL))
    sheet.save(out)
    print("wrote", out, sheet.size)


main(sys.argv[1], sys.argv[2], sys.argv[3:9])

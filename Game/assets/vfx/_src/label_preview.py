"""Draw the labels a Blender preview script saved next to its render (<png>.labels.json).

    python label_preview.py <png> [title]
Each label is (text, x, y): drawn centred on x, just above y, kept inside the image.
"""
import json, sys
from PIL import Image, ImageDraw, ImageFont


def font(size):
    for name in ("segoeuib.ttf", "arialbd.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def main(png, title=None):
    img = Image.open(png).convert("RGB")
    d = ImageDraw.Draw(img)
    f = font(20)
    with open(png + ".labels.json") as fh:
        labels = json.load(fh)
    for text, x, y in labels:
        l, t, r, b = d.multiline_textbbox((0, 0), text, font=f, align="center")
        w, h = r - l, b - t
        x0 = max(8, min(img.width - w - 8, x - w / 2))
        y0 = max(8, y - h - 12)
        d.rectangle((x0 - 6, y0 - 3, x0 + w + 6, y0 + h + 8), fill=(20, 21, 26))
        d.multiline_text((x0, y0), text, fill=(235, 240, 245), font=f, align="center")
    if title:
        d.text((12, img.height - 34), title, fill=(200, 205, 215), font=font(18))
    img.save(png)
    print("labelled", png)


main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)

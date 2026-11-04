"""Spin for Abilities - Gale Step stage 3 sheet: every texture on dark grey, the flipbook grid, and
flipbook frames 1, 5, 9 and 13 enlarged. Also a tinted strip (palette #E9FBFF / #7FE6FF / #2FA8D8,
additive, like LightEmission = 1 in Studio) so the white textures can be judged in colour.

    python compose_gale_step_stage3.py
Writes Game/assets/vfx/previews/gale_step_stage3_textures.png.
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageChops

ROOT = r"C:\Roblox\Spin for ability\Game\assets\vfx"
TEX = os.path.join(ROOT, "textures")
FRAMES = os.path.join(ROOT, "previews", "gale_step")
OUT = os.path.join(ROOT, "previews", "gale_step_stage3_textures.png")
BG = (0x2E, 0x2E, 0x33)
PALETTE = {"core": (0xE9, 0xFB, 0xFF), "main": (0x7F, 0xE6, 0xFF), "edge": (0x2F, 0xA8, 0xD8)}


def font(size):
    for name in ("segoeuib.ttf", "arialbd.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def on_bg(img, size=None, bg=BG):
    img = img.convert("RGBA")
    if size:
        img = img.resize(size, Image.LANCZOS)
    base = Image.new("RGBA", img.size, bg + (255,))
    return Image.alpha_composite(base, img).convert("RGB")


def tinted(img, rgb, size=None, bg=(14, 16, 22)):
    """Additive tint, the way LightEmission = 1 adds a coloured texture over the scene."""
    img = img.convert("RGBA")
    if size:
        img = img.resize(size, Image.LANCZOS)
    r, g, b, a = img.split()
    col = Image.merge("RGB", [ch.point(lambda v, k=k: v * k // 255) for ch, k in zip((r, g, b), rgb)])
    add = ImageChops.multiply(col, Image.merge("RGB", (a, a, a)))
    return ImageChops.add(Image.new("RGB", img.size, bg), add)


def border(d, box):
    d.rectangle(box, outline=(82, 82, 92))


def main():
    f_big, f = font(22), font(16)
    W = 1680
    sheet = Image.new("RGB", (W, 1500), BG)
    d = ImageDraw.Draw(sheet)
    x, y = 24, 18
    d.text((x, y), "Gale Step - stage 3 textures (white/grey + alpha, on #2E2E33)", fill=(240, 240, 245), font=f_big)
    y += 44
    # row 1: wind_gradient (1024x256) at 1:1 width 768, then wind_streaks 256
    items = [("wind_gradient.png  1024x256", "wind_gradient.png", (768, 192)),
             ("wind_streaks.png  512x512", "wind_streaks.png", (256, 256)),
             ("wind_wisp.png  256x256", "wind_wisp.png", (256, 256))]
    cx = x
    for label, fn, size in items:
        im = Image.open(os.path.join(TEX, fn))
        d.text((cx, y), label, fill=(215, 215, 220), font=f)
        sheet.paste(on_bg(im, size), (cx, y + 24))
        border(d, (cx - 1, y + 23, cx + size[0], y + 24 + size[1]))
        cx += size[0] + 32
    y += 24 + 256 + 30
    cx = x
    for label, fn in (("sparkle.png  256x256", "sparkle.png"), ("soft_glow.png  256x256", "soft_glow.png")):
        im = Image.open(os.path.join(TEX, fn))
        d.text((cx, y), label, fill=(215, 215, 220), font=f)
        sheet.paste(on_bg(im), (cx, y + 24))
        border(d, (cx - 1, y + 23, cx + 256, y + 280))
        cx += 256 + 32
    # tinted strip next to them
    d.text((cx, y), "tinted, additive (how they read in game)", fill=(215, 215, 220), font=f)
    tx = cx
    for fn, key, size in (("wind_gradient.png", "main", (384, 96)), ("wind_streaks.png", "core", (128, 128)),
                          ("sparkle.png", "core", (96, 96)), ("wind_wisp.png", "main", (128, 128)),
                          ("soft_glow.png", "edge", (96, 96))):
        im = tinted(Image.open(os.path.join(TEX, fn)), PALETTE[key], size)
        sheet.paste(im, (tx, y + 24))
        tx += size[0] + 10
    swy = y + 24 + 140
    for i, (k, rgb) in enumerate(PALETTE.items()):
        sheet.paste(Image.new("RGB", (40, 24), rgb), (cx + i * 150, swy))
        d.text((cx + i * 150 + 48, swy + 2), f"{k} #{''.join(f'{c:02X}' for c in rgb)}", fill=(215, 215, 220), font=f)
    y += 24 + 256 + 30
    # flipbook grid + enlarged frames
    d.text((x, y), "wind_swirl_flipbook.png  1024x1024, 4x4 = 16 frames (shown at 50%)", fill=(215, 215, 220), font=f)
    grid = Image.open(os.path.join(TEX, "wind_swirl_flipbook.png"))
    sheet.paste(on_bg(grid, (512, 512)), (x, y + 24))
    for k in range(5):
        d.line((x + k * 128, y + 24, x + k * 128, y + 24 + 512), fill=(82, 82, 92))
        d.line((x, y + 24 + k * 128, x + 512, y + 24 + k * 128), fill=(82, 82, 92))
    ex = x + 512 + 40
    d.text((ex, y), "frames 1, 5, 9, 13 enlarged (top: white on grey, bottom: tinted #7FE6FF)", fill=(215, 215, 220), font=f)
    for i, n in enumerate((1, 5, 9, 13)):
        fr = Image.open(os.path.join(FRAMES, f"flipbook_{n:02d}.png"))
        px = ex + i * 268
        sheet.paste(on_bg(fr, (256, 256)), (px, y + 24))
        border(d, (px - 1, y + 23, px + 256, y + 280))
        d.text((px + 6, y + 28), f"frame {n}", fill=(255, 210, 90), font=f)
        sheet.paste(tinted(fr, PALETTE["main"], (256, 256)), (px, y + 24 + 262))
    sheet = sheet.crop((0, 0, W, y + 24 + 530))
    sheet.save(OUT)
    print("wrote", OUT, sheet.size)


main()

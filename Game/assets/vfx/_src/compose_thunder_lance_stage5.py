"""Spin for Abilities - Thunder Lance stage 5 sheet: meshes next to the rig + textures on dark and light.

Run with the system Python (needs Pillow), after build_thunder_lance_meshes.py,
build_thunder_lance_textures.py and render_thunder_lance_meshes.py:
    python compose_thunder_lance_stage5.py
Top: previews/thunder_lance/meshes_front.png with the labels from meshes_labels.json (1-stud floor
checker for scale). Below, every texture three times: the white art itself on a dark background, then
tinted with the colour the game gives it (Roblox multiplies the white art by Color) on dark and on a
light background, so dark fringes, halos or a texture that vanishes on a bright map would show.
A zoomed strip of each texture's edge (4x, nearest neighbour) on light shows any fringe pixel by pixel.
Writes Game/assets/vfx/previews/thunder_lance_stage5_assets.png.
"""
import json, os
from PIL import Image, ImageDraw, ImageFont

ROOT = r"C:\Roblox\Spin for ability\Game\assets\vfx"
PREV = os.path.join(ROOT, "previews", "thunder_lance")
TEX = os.path.join(ROOT, "textures")
OUT = os.path.join(ROOT, "previews", "thunder_lance_stage5_assets.png")
DARK, LIGHT = (16, 18, 24), (232, 232, 228)
# texture, game tint(s) (prompt palette), what it is used for
TEXTURES = [
    ("star_flash", [(0xFF, 0xFD, 0xF0)], "release flash 5 st, impact flash 8 st"),
    ("spark", [(0xFF, 0xE1, 0x4D), (0x9F, 0xD8, 0xFF)], "shed + burst sparks (yellow, few blue)"),
    ("glow_line", [(0xFF, 0xE1, 0x4D)], "bolt Beams, spear glow Beam, ribbon + ring fade"),
    ("streak", [(0xFF, 0xE1, 0x4D)], "spear Trail (head at left)"),
    ("scorch", [None], "floor Decal (already dark grey)"),
]
CELL, PAD, HEAD = 230, 10, 30


def font(size, bold=True):
    for name in (("segoeuib.ttf" if bold else "segoeui.ttf"), "arialbd.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def tinted(img, tint):
    if tint is None:
        return img
    r, g, b, a = img.split()
    mul = lambda ch, t: ch.point(lambda v: v * t // 255)
    return Image.merge("RGBA", (mul(r, tint[0]), mul(g, tint[1]), mul(b, tint[2]), a))


def on(bg, img, size):
    fit = img.copy()
    fit.thumbnail(size, Image.LANCZOS)
    cell = Image.new("RGB", size, bg)
    cell.paste(fit, ((size[0] - fit.width) // 2, (size[1] - fit.height) // 2), fit)
    return cell


def edge_zoom(img, tint):
    """A 48x48 crop across the texture's right edge region at its middle row, 4x nearest neighbour,
    over the light background: halos / dark fringes show as a band of off-colour pixels."""
    w, h = img.size
    box = (int(w * 0.62), h // 2 - min(24, h // 2), int(w * 0.62) + 48, h // 2 + min(24, h // 2))
    crop = tinted(img.crop(box), tint)
    cell = Image.new("RGB", crop.size, LIGHT)
    cell.paste(crop, (0, 0), crop)
    return cell.resize((crop.width * 4, crop.height * 4), Image.NEAREST)


def main():
    meshes = Image.open(os.path.join(PREV, "meshes_front.png")).convert("RGB")
    labels = json.load(open(os.path.join(PREV, "meshes_labels.json")))
    d = ImageDraw.Draw(meshes)
    for text, x, y in labels.values():
        for i, line in enumerate(text.split("\n")):
            d.text((x - 120, y - 40 + i * 22), line, fill=(255, 225, 77) if i == 0 else (225, 228, 235),
                   font=font(18 if i == 0 else 15, i == 0))
    scale = 1400 / meshes.width
    meshes = meshes.resize((1400, int(meshes.height * scale)), Image.LANCZOS)

    cols = ["white art on dark", "game colour on dark", "game colour on light", "edge 4x on light"]
    rows = []
    for name, tints, use in TEXTURES:
        img = Image.open(os.path.join(TEX, name + ".png")).convert("RGBA")
        size = (CELL, CELL if img.height == img.width else CELL // 4 + 20)
        for tint in tints:
            rows.append((name, use, img, tint, size))

    W = max(1400, PAD + 260 + len(cols) * (CELL + PAD)) + PAD
    H = HEAD + meshes.height + PAD + 34 + sum(r[4][1] + PAD for r in rows) + 60
    sheet = Image.new("RGB", (W, H), (24, 26, 33))
    d = ImageDraw.Draw(sheet)
    d.text((PAD, 4), "Thunder Lance - Stage 5: VFX meshes (next to the R15 rig, 1-stud floor squares) and textures",
           fill=(242, 251, 255), font=font(20))
    sheet.paste(meshes, (PAD, HEAD))
    y = HEAD + meshes.height + PAD
    for i, c in enumerate(cols):
        d.text((PAD + 260 + i * (CELL + PAD), y), c, fill=(168, 230, 255), font=font(15))
    y += 26
    for name, use, img, tint, size in rows:
        tag = "" if tint is None else "  #%02X%02X%02X" % tint
        d.text((PAD, y + 4), f"{name}.png", fill=(255, 225, 77), font=font(16))
        d.text((PAD, y + 26), f"{img.width}x{img.height}{tag}", fill=(225, 228, 235), font=font(13, False))
        d.text((PAD, y + 44), use, fill=(180, 185, 195), font=font(12, False))
        x = PAD + 260
        sheet.paste(on(DARK, img, size), (x, y))
        sheet.paste(on(DARK, tinted(img, tint), size), (x + CELL + PAD, y))
        sheet.paste(on(LIGHT, tinted(img, tint), size), (x + 2 * (CELL + PAD), y))
        z = edge_zoom(img, tint)
        z.thumbnail(size, Image.NEAREST)
        sheet.paste(z, (x + 3 * (CELL + PAD), y))
        y += size[1] + PAD
    d.text((PAD, y + 6), "Textures: white/grey art + alpha, rendered in Blender (ortho camera, Film Transparent, "
           "Standard view transform); colour bled into transparent pixels (no halo); transparent margin "
           "16 px at 512, 8 px at 256 / 128.", fill=(220, 225, 235), font=font(14, False))
    sheet.save(OUT)
    print("wrote", OUT, sheet.size)


main()

"""Spin for Abilities - Frost Jab stage 5 contact sheets: meshes, textures, mist flipbook.

Run with the system Python (needs Pillow), after build_frost_jab_meshes.py, render_frost_jab_meshes.py
and build_frost_jab_textures.py:
    python compose_frost_jab_stage5.py
Writes, in Game/assets/vfx/previews/:
    frost_jab_stage5_meshes.png    every mesh next to the R15 rig (front) + ring/crown from above
    frost_jab_stage5_textures.png  every texture: as stored (white on dark), tinted the way Roblox
                                   will (main #A8E6FF on dark, deep #4FA3D9 on light) and a 4x zoom of
                                   an edge on the light background (halo / fringe check)
    frost_jab_stage5_flipbook.png  the 4x4 mist sheet + frames 1, 5, 9, 13 enlarged, dark and light
"""
import json, os
from PIL import Image, ImageDraw, ImageFont, ImageChops

ROOT = r"C:\Roblox\Spin for ability\Game\assets\vfx"
TEX = os.path.join(ROOT, "textures")
PREV = os.path.join(ROOT, "previews")
SHOTS = os.path.join(PREV, "frost_jab")
DARK, LIGHT = (16, 20, 32), (232, 238, 244)
CORE, MAIN, DEEP = (0xF2, 0xFB, 0xFF), (0xA8, 0xE6, 0xFF), (0x4F, 0xA3, 0xD9)
TEXTURES = [  # file, label, what it is for, (zoom box as fractions x0, y0, x1, y1)
    ("frost_flare", "frost_flare 256", "FLASH: the impact burst", (0.62, 0.18, 0.87, 0.43)),
    ("frost_snowflake", "frost_snowflake 256", "RESIDUAL: flakes over the target", (0.40, 0.02, 0.65, 0.27)),
    ("frost_shard", "frost_shard 512", "MAIN: shard + spike meshes (V = tip at top)", (0.0, 0.0, 0.25, 0.25)),
    ("frost_ring", "frost_ring 512", "SECONDARY: ring mesh (top = outer rim)", (0.0, 0.0, 0.25, 0.25)),
    ("sparkle", "sparkle 256 (reused, Gale Step)", "RESIDUAL: glints", (0.38, 0.0, 0.62, 0.25)),
    ("soft_glow", "soft_glow 256 (reused, Gale Step)", "FLASH / SECONDARY: soft glow", (0.0, 0.3, 0.4, 0.7)),
]


def font(size, bold=True):
    for name in (("segoeuib.ttf" if bold else "segoeui.ttf"), "arialbd.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def over(tex, bg, tint=None, size=None):
    """Composite a white/grey RGBA texture over a flat background, multiplied by tint (like Roblox's
    Color / ImageColor3)."""
    t = tex.convert("RGBA")
    if size:
        t = t.resize(size, Image.LANCZOS)
    if tint:
        t = Image.merge("RGBA", (*ImageChops.multiply(t.convert("RGB"), Image.new("RGB", t.size, tint)).split(),
                                 t.split()[3]))
    base = Image.new("RGBA", t.size, bg + (255,))
    return Image.alpha_composite(base, t).convert("RGB")


def meshes_sheet():
    front = Image.open(os.path.join(SHOTS, "meshes_front.png")).convert("RGB")
    top = Image.open(os.path.join(SHOTS, "meshes_top.png")).convert("RGB").resize((820, 820))
    labels = json.load(open(os.path.join(SHOTS, "meshes_labels.json")))
    d = ImageDraw.Draw(front)
    for text, x, y in labels.values():
        lines = text.split("\n")
        for i, line in enumerate(lines):
            f = font(17 if i == 0 else 14, i == 0)
            w = d.textlength(line, font=f)
            d.text((x - w / 2, y - 22 * (len(lines) - i)), line, fill=(242, 251, 255) if i == 0 else (168, 230, 255), font=f)
    pad, head = 12, 60
    sheet = Image.new("RGB", (front.width + top.width + pad * 3, head + front.height + pad + 40), (24, 26, 33))
    sd = ImageDraw.Draw(sheet)
    sd.text((pad, 12), "Frost Jab - Stage 5: ice meshes next to the R15 rig (5.4 studs tall)  -  180 tris in total "
            "(budget 300), flat shaded", fill=(242, 251, 255), font=font(24))
    sheet.paste(front, (pad, head))
    sheet.paste(top, (front.width + pad * 2, head))
    sd.text((front.width + pad * 2 + 8, head + 8), "frost_ring + frost_crown from above", fill=(255, 220, 60), font=font(17))
    sd.text((pad, head + front.height + 8), "Colour here = UV V (deep -> main -> core): base -> tip on every shard and "
            "spike, inner -> outer edge on the ring. Origins: shard bases, ring/crown centre on the ground. "
            "4 shard variants: 5-, 4-, 6- and 5-sided, 1.1-2.0 studs long.", fill=(220, 225, 235), font=font(15, False))
    out = os.path.join(PREV, "frost_jab_stage5_meshes.png")
    sheet.save(out)
    print("wrote", out, sheet.size)


def textures_sheet():
    C, Z, pad, lab = 240, 240, 10, 46
    cols = ["As stored (white on dark)", "Tinted main #A8E6FF on dark", "Tinted deep #4FA3D9 on light",
            "Edge zoom x4 on light (halo check)"]
    W = 330 + len(cols) * (C + pad) + pad
    H = 60 + 30 + len(TEXTURES) * (C + lab) + pad
    sheet = Image.new("RGB", (W, H), (24, 26, 33))
    d = ImageDraw.Draw(sheet)
    d.text((pad, 12), "Frost Jab - Stage 5: textures (white/grey + alpha; colour added in Roblox)",
           fill=(242, 251, 255), font=font(24))
    for i, c in enumerate(cols):
        d.text((330 + i * (C + pad), 62), c, fill=(255, 220, 60), font=font(14))
    y = 92
    for name, title, use, zoom in TEXTURES:
        tex = Image.open(os.path.join(TEX, name + ".png")).convert("RGBA")
        d.text((pad, y + 10), title, fill=(242, 251, 255), font=font(17))
        d.text((pad, y + 36), f"{tex.width}x{tex.height}", fill=(168, 230, 255), font=font(14, False))
        d.text((pad, y + 58), use, fill=(220, 225, 235), font=font(13, False))
        cells = [over(tex, DARK, None, (C, C)), over(tex, DARK, MAIN, (C, C)), over(tex, LIGHT, DEEP, (C, C))]
        x0, y0, x1, y1 = (round(v * tex.width) for v in zoom)
        crop = tex.crop((x0, y0, x1, y1)).resize((Z, Z), Image.NEAREST)
        cells.append(over(crop, LIGHT, DEEP))
        for i, cell in enumerate(cells):
            sheet.paste(cell, (330 + i * (C + pad), y))
        y += C + lab
    out = os.path.join(PREV, "frost_jab_stage5_textures.png")
    sheet.save(out)
    print("wrote", out, sheet.size)


def flipbook_sheet():
    flip = Image.open(os.path.join(TEX, "frost_mist_flipbook.png")).convert("RGBA")
    pad, head, big = 12, 60, 360
    W = pad + 512 + pad + 4 * (big + pad)
    H = head + 30 + 2 * (big + 30) + pad
    sheet = Image.new("RGB", (W, H), (24, 26, 33))
    d = ImageDraw.Draw(sheet)
    d.text((pad, 12), "Frost Jab - Stage 5: cold mist flipbook, 1024x1024 = 4x4 frames (reading order), "
           "rendered in Blender (animated noise shader)", fill=(242, 251, 255), font=font(22))
    d.text((pad, head), "Whole sheet (tinted main, on dark)", fill=(255, 220, 60), font=font(15))
    sheet.paste(over(flip, DARK, MAIN, (512, 512)), (pad, head + 26))
    x0 = pad + 512 + pad
    cell = flip.width // 4
    for i, f in enumerate((1, 5, 9, 13)):
        row, col = divmod(f - 1, 4)
        fr = flip.crop((col * cell, row * cell, (col + 1) * cell, (row + 1) * cell))
        x = x0 + i * (big + pad)
        d.text((x, head), f"frame {f}  (white on dark)", fill=(255, 220, 60), font=font(15))
        sheet.paste(over(fr, DARK, None, (big, big)), (x, head + 26))
        d.text((x, head + 30 + big + 2), f"frame {f}  (deep on light)", fill=(255, 220, 60), font=font(15))
        sheet.paste(over(fr, LIGHT, DEEP, (big, big)), (x, head + 30 + big + 28))
    out = os.path.join(PREV, "frost_jab_stage5_flipbook.png")
    sheet.save(out)
    print("wrote", out, sheet.size)


meshes_sheet()
textures_sheet()
flipbook_sheet()

"""Spin for Abilities - Frost Jab stage 6 sheet: /vfxtest frost in Studio (0.25x), one loop, layer by layer.

Run with the system Python (needs Pillow):
    python compose_frost_jab_stage6.py
Inputs: Game/assets/vfx/previews/frost_jab/vfxtest_NN.png - Studio viewport captures (Play mode,
/vfxtest frost at TIME_SCALE 0.25, side camera; frames from one burst, ~0.24 s apart = ~0.06 s of
game time). Frame 09 is the end of the previous loop (the slow ending: coat breaking, crumbs falling).
Writes Game/assets/vfx/previews/frost_jab_stage6_vfxtest.png.
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = r"C:\Roblox\Spin for ability\Game\assets\vfx\previews"
SHOTS = os.path.join(ROOT, "frost_jab")
OUT = os.path.join(ROOT, "frost_jab_stage6_vfxtest.png")
CELLS = [  # file number, title, layer note
    (28, "Wind-up", "0. STARTUP: frost glow + glints on the fist"),
    (29, "Hit frame", "1. FLASH: ice star flare, glow, light"),
    (30, "Burst", "2. MAIN: 4 shards fly out  |  3. ring snaps open"),
    (31, "Ring + crown", "3. SECONDARY: spikes rise, mist starts"),
    (33, "Frosted", "3. mist billows  |  4. coat + snowflakes"),
    (36, "Recovery", "4. RESIDUAL: coat, flakes, glints"),
    (40, "Fading", "ring widens and fades, flakes drift up"),
    (44, "Almost gone", "ring gone, last flakes; coat thinning"),
    (9, "Slow ends", "4. coat breaks, ice crumbs fall"),
]
CW, CH, PAD, LAB = 360, 328, 10, 52


def font(size, bold=True):
    for name in (("segoeuib.ttf" if bold else "segoeui.ttf"), "arialbd.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def main():
    cols = 3
    rows = (len(CELLS) + cols - 1) // cols
    W = PAD + cols * (CW + PAD)
    H = 56 + rows * (CH + LAB + PAD) + 40
    sheet = Image.new("RGB", (W, H), (24, 26, 33))
    d = ImageDraw.Draw(sheet)
    d.text((PAD, 12), "Frost Jab - Stage 6: /vfxtest frost in Studio (Play mode, TIME_SCALE 0.25)",
           fill=(242, 251, 255), font=font(22))
    for i, (n, title, note) in enumerate(CELLS):
        r, c = divmod(i, cols)
        x, y = PAD + c * (CW + PAD), 56 + r * (CH + LAB + PAD)
        img = Image.open(os.path.join(SHOTS, f"vfxtest_{n:02d}.png")).convert("RGB")
        img = img.crop((0, 40, img.width, img.height - 20)).resize((CW, CH), Image.LANCZOS)
        d.text((x, y), f"{i + 1}. {title}", fill=(255, 220, 60), font=font(16))
        d.text((x, y + 22), note, fill=(220, 225, 235), font=font(13, False))
        sheet.paste(img, (x, y + LAB - 6))
    d.text((PAD, H - 32), "Real cast at normal speed (hotbar key 4, server hit): 15 VFX objects (9 attacker + 6 target), "
           "Workspace descendants 893 before / 893 three seconds after.", fill=(168, 230, 255), font=font(14, False))
    sheet.save(OUT)
    print("wrote", OUT, sheet.size)


main()

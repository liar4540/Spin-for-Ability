"""Spin for Abilities - Thunder Lance stage 6 sheet: /vfxtest lance in Studio, one row of key moments.

Run with the system Python (needs Pillow):
    python compose_thunder_lance_stage6.py <capture dir> <cast start unix ms> [speed]
The capture dir holds Studio window captures named <unix ms>.png (capture_studio_window.ps1 burst,
same machine clock as the client's DateTime.now()). The test runs at <speed> (default 0.25), so a
capture at wall time T shows game time (T - start) / 1000 * speed. For each moment the nearest capture
is used and its game time printed under it.
Writes Game/assets/vfx/previews/thunder_lance_stage6_vfxtest.png.
"""
import glob, os, sys
from PIL import Image, ImageDraw, ImageFont

OUT = r"C:\Roblox\Spin for ability\Game\assets\vfx\previews\thunder_lance_stage6_vfxtest.png"
VIEWPORT = (294, 177, 1673, 968)  # Studio 3D viewport inside the window capture
FLIGHT = 40 / 160  # 40 studs at 160 studs/s
HIT = 0.5 + (40 - 4 - 2.5) / 160  # release + the tip's flight until the 2.5-stud hitbox touches the dummy
MOMENTS = [("F4-F8 crackle", 0.20), ("F8-F12 spear forms", 0.33), ("F12 held, aimed", 0.42),
           ("F15 RELEASE flash", 0.51), ("flight", 0.58), ("hit + 1 frame flash", HIT + 0.04),
           ("ring + sparks", HIT + 0.12), ("arcs on the dummy", HIT + 0.4), ("scorch fading", HIT + 1.6)]
CW, CH, PAD = 330, 250, 8


def font(size, bold=True):
    for name in (("segoeuib.ttf" if bold else "segoeui.ttf"), "arialbd.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def main():
    shots_dir, start = sys.argv[1], int(sys.argv[2])
    speed = float(sys.argv[3]) if len(sys.argv) > 3 else 0.25
    shots = []
    for path in glob.glob(os.path.join(shots_dir, "*.png")):
        try:
            ms = int(os.path.splitext(os.path.basename(path))[0])
        except ValueError:
            continue
        shots.append(((ms - start) / 1000 * speed, path))
    shots.sort()
    cols = 3
    rows = (len(MOMENTS) + cols - 1) // cols
    sheet = Image.new("RGB", (PAD + cols * (CW + PAD), 44 + rows * (CH + 30 + PAD) + 30), (24, 26, 33))
    d = ImageDraw.Draw(sheet)
    d.text((PAD, 10), "Thunder Lance - Stage 6: /vfxtest lance in Studio (0.25x, dummy 40 studs away, side view)",
           fill=(242, 251, 255), font=font(18))
    for k, (label, game_t) in enumerate(MOMENTS):
        t, path = min(shots, key=lambda s: abs(s[0] - game_t))
        img = Image.open(path).convert("RGB").crop(VIEWPORT)
        img.thumbnail((CW, CH), Image.LANCZOS)
        x = PAD + (k % cols) * (CW + PAD)
        y = 44 + (k // cols) * (CH + 30 + PAD)
        sheet.paste(img, (x, y))
        d.text((x + 2, y + img.height + 4), f"{label}   (game {t:.2f} s)", fill=(255, 225, 77), font=font(14))
    d.text((PAD, sheet.height - 26), f"{len(shots)} captures; game time = (capture ms - cast start ms) / 1000 x {speed}",
           fill=(200, 205, 215), font=font(13, False))
    sheet.save(OUT)
    print("wrote", OUT, sheet.size, "| capture game times", f"{shots[0][0]:.2f}..{shots[-1][0]:.2f}")


main()

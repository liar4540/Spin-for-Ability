"""Spin for Abilities - Thunder Lance stage 7B: the sky strike's key moments in Studio, one sheet.

Run with the system Python (needs Pillow):
    python compose_thunder_lance_stage7b.py <capture dir> <strike starts> <out name> [label] [speed]
<strike starts> = comma-separated unix ms at which each ThunderLanceStrike_<name> folder appeared on the
client (= the spear's impact; logged by the test probe). The capture dir holds Studio window captures named
<unix ms>.png (capture_studio_window.ps1 burst, same clock). A capture at wall time T after a strike
started at S shows game time (T - S) / 1000 * speed (default 0.25) after the impact. Each moment uses the
nearest non-black capture over all strikes (PrintWindow sometimes returns a black viewport).
Writes Game/assets/vfx/previews/<out name>.png.
"""
import glob, os, sys
from PIL import Image, ImageDraw, ImageFont, ImageStat

PREV = r"C:\Roblox\Spin for ability\Game\assets\vfx\previews"
VIEWPORT = (584, 350, 2064, 1320)  # Studio 3D viewport inside the window capture, above the hotbar
# (label, game seconds after the spear's impact) - prompt "Proof to show me" 1
MOMENTS = [("charge", 0.09), ("1st strike", 0.17), ("flicker dip", 0.215), ("2nd strike", 0.25),
           ("shockwave peak", 0.33), ("debris in the air", 0.55), ("smoke at 1 s", 1.0), ("crater at 2.5 s", 2.5)]
CW, CH, PAD = 440, 288, 8


def font(size, bold=True):
    for name in (("segoeuib.ttf" if bold else "segoeui.ttf"), "arialbd.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def main():
    cap_dir, starts_arg, out_name = sys.argv[1], sys.argv[2], sys.argv[3]
    label = sys.argv[4] if len(sys.argv) > 4 else ""
    speed = float(sys.argv[5]) if len(sys.argv) > 5 else 0.25
    starts = [int(s) for s in starts_arg.split(",")]
    caps = sorted(int(os.path.basename(p)[:-4]) for p in glob.glob(os.path.join(cap_dir, "*.png"))
                  if os.path.basename(p)[:-4].isdigit())
    black = {}

    def is_black(ms):
        if ms not in black:
            img = Image.open(os.path.join(cap_dir, f"{ms}.png")).convert("L").crop(VIEWPORT).resize((48, 32))
            black[ms] = ImageStat.Stat(img).mean[0] < 10
        return black[ms]

    cols = 4
    rows = (len(MOMENTS) + cols - 1) // cols
    sheet = Image.new("RGB", (PAD + cols * (CW + PAD), 52 + rows * (CH + 28 + PAD)), (24, 26, 33))
    d = ImageDraw.Draw(sheet)
    d.text((PAD, 8), f"Thunder Lance - Stage 7B: sky strike in Studio {label}", fill=(242, 251, 255), font=font(20))
    d.text((PAD, 32), f"/vfxtest lance at {speed}x (dummy 40 studs away); times are game seconds after the spear's impact",
           fill=(255, 225, 77), font=font(13, False))
    for k, (name, t) in enumerate(MOMENTS):
        best = None
        for start in starts:
            want = start + t / speed * 1000
            if want < caps[0] or want > caps[-1]:
                continue
            for ms in sorted(caps, key=lambda c: abs(c - want))[:12]:
                if not is_black(ms):
                    got = (ms - start) / 1000 * speed
                    if best is None or abs(got - t) < abs(best[0] - t):
                        best = (got, ms)
                    break
        x = PAD + (k % cols) * (CW + PAD)
        y = 52 + (k // cols) * (CH + 28 + PAD)
        if best:
            img = Image.open(os.path.join(cap_dir, f"{best[1]}.png")).convert("RGB").crop(VIEWPORT).resize((CW, CH), Image.LANCZOS)
            sheet.paste(img, (x, y))
            d.text((x + 2, y + CH + 4), f"{k + 1}. {name}   (t = {best[0]:.3f} s)", fill=(255, 225, 77), font=font(14))
            print(f"  {name:18s} wanted {t:.3f} s, got {best[0]:.3f} s ({best[1]})")
        else:
            d.text((x + 2, y + CH + 4), f"{k + 1}. {name}: no capture", fill=(255, 120, 120), font=font(14))
            print(f"  {name:18s} no capture")
    out = os.path.join(PREV, out_name + ".png")
    sheet.save(out)
    print("wrote", out, sheet.size)


main()

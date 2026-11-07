"""Spin for Abilities - Frost Jab stage 3: animated GIFs + motion path sheet.

Run with the system Python (needs Pillow), after render_frost_jab_poses.py (FRAMES 0-13) and the
motion path renders (previews/frost_jab/motion_path_{side,top,34}.png):
    python compose_frost_jab_stage3.py
Writes, in Game/assets/vfx/previews/:
    frost_jab_side_30fps.gif   side view, every frame 0-13 at 30 fps (frames rendered by Blender)
    frost_jab_side_025x.gif    the same frames at 0.25x speed (7.5 fps)
    frost_jab_stage3_paths.png motion path of the right hand from the side, top and 3/4
GIF delays are whole centiseconds, so 30 fps alternates 30/30/40 ms (average 33.3 ms) and 0.25x
alternates 130/130/140 ms (average 133.3 ms). After frame 13 the ready pose holds for 0.5 s (labelled)
so the loop point is visible; the animation itself is frames 0-13 only.
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = r"C:\Roblox\Spin for ability\Game\assets\vfx\previews"
FRAMES_DIR = os.path.join(ROOT, "frost_jab")
FIRST, LAST, HIT = 0, 13, 4
NAMES = {0: "ready", 1: "pull-back", 2: "wind-up (stop)", 4: "HIT", 5: "overshoot", 6: "hold", 10: "recovery",
         13: "ready"}
SIZE = (450, 600)


def font(size, bold=True):
    for name in (("segoeuib.ttf" if bold else "segoeui.ttf"), "arialbd.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def labelled(f, extra=""):
    img = Image.open(os.path.join(FRAMES_DIR, f"pose_side_{f:02d}.png")).convert("RGB").resize(SIZE, Image.LANCZOS)
    d = ImageDraw.Draw(img)
    hit = f == HIT
    text = f"frame {f:2d}  {f / 30:.3f} s  {NAMES.get(f, '')}{extra}"
    d.rectangle((0, 0, SIZE[0], 34), fill=(20, 22, 28))
    d.text((10, 6), text, fill=(168, 230, 255) if hit else (230, 235, 240), font=font(18))
    if hit:
        d.rectangle((1, 1, SIZE[0] - 2, SIZE[1] - 2), outline=(168, 230, 255), width=3)
    return img


def gif(path, base_ms):
    frames = [labelled(f) for f in range(FIRST, LAST + 1)]
    pattern = [base_ms, base_ms, base_ms + 10]
    durations = [pattern[i % 3] for i in range(len(frames))]
    frames.append(labelled(LAST, "  (0.5 s pause, not in anim)"))
    durations.append(500)
    pal = [f.quantize(colors=128, method=Image.Quantize.MEDIANCUT) for f in frames]
    pal[0].save(path, save_all=True, append_images=pal[1:], duration=durations, loop=0, disposal=2)
    anim_ms = sum(durations[:-1])
    print(f"wrote {path}: {len(frames) - 1} frames, {anim_ms} ms for frames 0-13 "
          f"({(len(frames) - 1) / (anim_ms / 1000):.2f} fps)")


def paths_sheet():
    views = [("side", "Side (forward = right)"), ("top", "Top (forward = up)"), ("34", "3/4 front")]
    imgs = [Image.open(os.path.join(FRAMES_DIR, f"motion_path_{v}.png")).convert("RGB") for v, _ in views]
    w, h = imgs[0].size
    pad, head = 10, 70
    sheet = Image.new("RGB", (pad + len(imgs) * (w + pad), head + h + pad + 40), (24, 26, 33))
    d = ImageDraw.Draw(sheet)
    d.text((pad, 8), "Frost Jab - right hand motion path (Blender Motion Paths, wrist bone tail, frames 0-13)",
           fill=(242, 251, 255), font=font(24))
    for i, ((_, title), img) in enumerate(zip(views, imgs)):
        x = pad + i * (w + pad)
        d.text((x, 42), title, fill=(255, 220, 60), font=font(18))
        sheet.paste(img, (x, head))
    d.text((pad, head + h + 8), "Red = before the current frame (4, the hit), green = after. 0 -> 1 -> 2: the fist "
           "swings out and back and stops at 2; 2 -> 4 the strike; 4 -> 6 the hold; 6 -> 13 a wide easing arc "
           "back to the guard.", fill=(220, 225, 235), font=font(15, False))
    out = os.path.join(ROOT, "frost_jab_stage3_paths.png")
    sheet.save(out)
    print("wrote", out, sheet.size)


gif(os.path.join(ROOT, "frost_jab_side_30fps.gif"), 30)
gif(os.path.join(ROOT, "frost_jab_side_025x.gif"), 130)
paths_sheet()

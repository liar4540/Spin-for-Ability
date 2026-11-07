"""Spin for Abilities - Frost Jab stage 4 sheet: Studio playback vs Blender, same frames, same camera.

Run with the system Python (needs Pillow):
    python compose_frost_jab_stage4.py
Inputs in Game/assets/vfx/previews/frost_jab/:
    studio_side_FF.png  Studio window captures: the uploaded-to-be KeyframeSequence (FrostJab_Punch,
                        registered with KeyframeSequenceProvider) on a copy of the game rig, stepped to
                        frame FF, camera = the Blender side camera (same eye/target, same 39.6 deg
                        vertical field of view)
    pose_side_FF.png    Blender renders of the same frames (render_frost_jab_poses.py)
Writes Game/assets/vfx/previews/frost_jab_stage4_studio_vs_blender.png.
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = r"C:\Roblox\Spin for ability\Game\assets\vfx\previews"
SHOTS = os.path.join(ROOT, "frost_jab")
OUT = os.path.join(ROOT, "frost_jab_stage4_studio_vs_blender.png")
FRAMES = [(0, "ready"), (2, "wind-up (anticipation)"), (4, "HIT  (marker)"), (10, "recovery")]
VIEWPORT = (294, 177, 1033, 850)  # Studio 3D viewport inside the window capture
CW, CH, PAD, LABEL = 330, 440, 8, 26
# measured by the stage 4 Studio script: every part, every frame 0-13 (Studio vs Blender)
RESULT = ("Every part, every frame 0-13: worst limb angle 0.22 deg (frame 8, LeftUpperArm), worst part "
          "position 0.0011 studs  ->  PASS (limit 5 deg)")


def font(size, bold=True):
    for name in (("segoeuib.ttf" if bold else "segoeui.ttf"), "arialbd.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def studio(f):
    img = Image.open(os.path.join(SHOTS, f"studio_side_{f:02d}.png")).convert("RGB").crop(VIEWPORT)
    w = round(img.height * 600 / 800)  # same aspect as the Blender render; vertical FOV already equal
    x0 = (img.width - w) // 2
    return img.crop((x0, 0, x0 + w, img.height))


def blender(f):
    return Image.open(os.path.join(SHOTS, f"pose_side_{f:02d}.png")).convert("RGB")


def main():
    rows = [("Studio (KeyframeSequence FrostJab_Punch, played on the game rig)", studio),
            ("Blender (FrostJabRig, frost_jab.blend)", blender)]
    W = PAD + len(FRAMES) * (CW + PAD)
    H = 50 + PAD + len(rows) * (LABEL * 2 + CH + PAD) + 34
    sheet = Image.new("RGB", (W, H), (24, 26, 33))
    d = ImageDraw.Draw(sheet)
    d.text((PAD, 10), "Frost Jab - Stage 4: Studio playback vs Blender (side view, same camera)",
           fill=(242, 251, 255), font=font(24))
    y = 50
    for title, get in rows:
        d.text((PAD, y), title, fill=(255, 220, 60), font=font(18))
        y += LABEL
        for i, (f, label) in enumerate(FRAMES):
            x = PAD + i * (CW + PAD)
            d.text((x + 4, y), f"frame {f}  {label}", fill=(168, 230, 255) if "HIT" in label else (220, 225, 235),
                   font=font(15))
            sheet.paste(get(f).resize((CW, CH), Image.LANCZOS), (x, y + LABEL))
        y += LABEL + CH + PAD
    d.text((PAD, y + 4), RESULT, fill=(255, 220, 60), font=font(16))
    sheet.save(OUT)
    print("wrote", OUT, sheet.size)


main()

"""Star Cannon textures (white on transparent, tinted gold / white in Studio) + its status icon.
Run: python build_star_cannon_textures.py -> Game/assets/vfx/textures/star_cannon_*.png
  soft     512x256  beam glow: a smooth band, feathered edges (outer glow + core)
  flow     512x256  beam energy: streaks along the beam that read as flowing when TextureSpeed scrolls it
  ring     512x512  energy ring travelling down the beam: a bright thin rim with sparkle breaks
  plasma   512x256  v2 beam body: dense turbulent energy, cells + fine streaks, fully opaque middle
  rim      512x256  v2 beam outline: two crisp bright lines just inside both edges + a faint inner line
  *_beam   the beam-layer textures turned 90 degrees (star_cannon_soft/flow/plasma/rim_beam.png +
           blood_moon_veins_beam.png): on a Roblox Beam the image's VERTICAL axis runs along the beam, so
           streaks / edge lines drawn left-right showed as bars across it (stage check 2026-11-27)
  status_heavy.png  gold "overwhelmed" icon (a star pressing down) for the Heavy slow
"""
import math
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "textures")


def noise(shape, cells, seed):
    g = np.random.default_rng(seed).random((cells[0] + 1, cells[1] + 1))
    img = Image.fromarray((g * 255).astype(np.uint8)).resize(shape[::-1], Image.BICUBIC)
    return np.asarray(img, np.float32) / 255


def save(a, name):
    img = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    Image.merge("RGBA", (Image.new("L", img.size, 255),) * 3 + (img,)).save(os.path.join(OUT, f"star_cannon_{name}.png"))
    print("wrote", name)


def soft(w=512, h=256):
    v = np.abs(np.linspace(-1, 1, h, dtype=np.float32))[:, None] * np.ones((1, w), np.float32)
    return np.exp(-(v / 0.45) ** 2)


def flow(w=512, h=256):
    v = np.abs(np.linspace(-1, 1, h, dtype=np.float32))[:, None] * np.ones((1, w), np.float32)
    streaks = sum(noise((h, w), (40 * k, 2 * k), 5 + k) / k for k in (1, 2, 3))
    streaks = np.clip((streaks / 1.83 - 0.35) / 0.4, 0, 1)
    body = np.clip(1 - v / 0.95, 0, 1) ** 0.7
    return body * (0.4 + 0.75 * streaks)


def ring(size=512):
    c = (size - 1) / 2
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    r = np.hypot(xx - c, yy - c) / c
    ang = np.arctan2(yy - c, xx - c)
    rim = np.exp(-((r - 0.9) / 0.035) ** 2)
    halo = np.exp(-((r - 0.88) / 0.12) ** 2) * 0.35
    breaks = 0.65 + 0.35 * np.cos(ang * 9) * np.cos(ang * 4 + 1)
    return np.clip((rim + halo) * breaks, 0, 1)


def heavy_icon(size=256):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = size / 2
    def star(scale, fill):
        pts = []
        for i in range(8):
            a = -math.pi / 2 + i * math.pi / 4
            rr = (size * 0.30 if i % 2 == 0 else size * 0.11) * scale
            pts.append((c + math.cos(a) * rr, size * 0.40 + math.sin(a) * rr))
        d.polygon(pts, fill=fill)
    star(1.18, (60, 35, 0, 255))
    star(1.0, (255, 205, 60, 255))
    for k, y in enumerate((0.74, 0.86)):  # two chevrons pressing down
        w = size * 0.22
        d.line([(c - w, size * y - 14), (c, size * y + 6), (c + w, size * y - 14)], fill=(60, 35, 0, 255), width=22)
        d.line([(c - w, size * y - 14), (c, size * y + 6), (c + w, size * y - 14)], fill=(255, 225, 120, 255), width=10)
    return img


def plasma(w=512, h=256):
    """Turbulent energy: stretched cells (bulges of light), fine streaks, solid in the middle."""
    v = np.abs(np.linspace(-1, 1, h, dtype=np.float32))[:, None] * np.ones((1, w), np.float32)
    cells = noise((h, w), (6, 10), 71) * 0.6 + noise((h, w), (12, 22), 72) * 0.4
    streaks = sum(noise((h, w), (48 * k, 3 * k), 80 + k) / k for k in (1, 2))
    streaks = np.clip((streaks / 1.5 - 0.3) / 0.45, 0, 1)
    body = np.clip(1 - (v / 0.97) ** 3, 0, 1)
    a = body * np.clip(0.55 + 0.45 * cells + 0.35 * streaks, 0, 1)
    return a


def rim(w=512, h=256):
    """Crisp bright lines near both edges (the beam's outline) and a faint one inside."""
    v = np.abs(np.linspace(-1, 1, h, dtype=np.float32))[:, None] * np.ones((1, w), np.float32)
    flicker = 0.75 + 0.25 * noise((h, w), (2, 30), 90)
    edge = np.exp(-((v - 0.86) / 0.035) ** 2)
    inner = np.exp(-((v - 0.55) / 0.02) ** 2) * 0.45
    return np.clip((edge + inner) * flicker, 0, 1)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    save(soft(), "soft")
    save(flow(), "flow")
    save(ring(), "ring")
    save(plasma(), "plasma")
    save(rim(), "rim")
    heavy_icon().save(os.path.join(OUT, "status_heavy.png"))
    for name in ("star_cannon_soft", "star_cannon_flow", "star_cannon_plasma", "star_cannon_rim", "blood_moon_veins"):
        Image.open(os.path.join(OUT, f"{name}.png")).rotate(90, expand=True).save(os.path.join(OUT, f"{name}_beam.png"))
        print("wrote", f"{name}_beam")
    print("wrote status_heavy")

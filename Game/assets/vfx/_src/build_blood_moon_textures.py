"""Blood Moon Slash textures for the crescent's Beams (white on transparent; tinted by Beam.Color).
Run: python build_blood_moon_textures.py  -> Game/assets/vfx/textures/blood_moon_*.png
Beam textures: U (x) runs along the crescent, V (y) across its thickness.
  edge    512x64   razor-thin bright core line with a tight glow
  body    512x256  energy body: dense in the middle, fine streaks that flow along the arc
  smear   512x256  smoky smear: torn, soft edges
  flame   1024x1024 flipbook (4x4): black flame tongues licking up and burning out
  veins   512x256  dark streaks drawn over the body for detail
  status_bleed.png / status_freeze.png: the status icons above enemies (coloured, not tinted)
(body and smear are symmetric across V: camera-facing Beams can show either side first)
"""
import math
import os
import numpy as np
from PIL import Image, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "textures")


def value_noise(shape, cells, seed):
    g = np.random.default_rng(seed).random((cells[0] + 1, cells[1] + 1))
    img = Image.fromarray((g * 255).astype(np.uint8)).resize(shape[::-1], Image.BICUBIC)
    return np.asarray(img, dtype=np.float32) / 255.0


def fbm(shape, cells, octaves, seed):
    total = np.zeros(shape, np.float32)
    amp = norm = 0.0
    amp = 1.0
    for o in range(octaves):
        total += amp * value_noise(shape, (cells[0] * 2 ** o, cells[1] * 2 ** o), seed + 7 * o)
        norm += amp
        amp *= 0.5
    return total / norm


def save(alpha, name):
    a = Image.fromarray((np.clip(alpha, 0, 1) * 255).astype(np.uint8))
    img = Image.merge("RGBA", (Image.new("L", a.size, 255),) * 3 + (a,))
    img.save(os.path.join(OUT, f"blood_moon_{name}.png"))
    print("wrote", name)


def build_edge(w=512, h=64):
    v = np.abs(np.linspace(-1, 1, h, dtype=np.float32))[:, None] * np.ones((1, w), np.float32)
    core = np.clip(1 - v / 0.12, 0, 1)
    glow = np.exp(-(v / 0.35) ** 2) * 0.55
    return core + glow


def build_body(w=512, h=256):
    v = np.linspace(0, 1, h, dtype=np.float32)[:, None] * np.ones((1, w), np.float32)
    streaks = fbm((h, w), (24, 2), 4, 5)  # many fine streaks along U
    streaks = np.clip((streaks - 0.35) / 0.5, 0, 1)
    broad = fbm((h, w), (6, 3), 3, 9)
    # symmetric across the thickness (Beams facing the camera can show either side first)
    d = np.abs(2 * v - 1)
    density = np.clip(1 - d, 0, 1) ** 0.7
    a = density * (0.45 + 0.55 * streaks) * (0.75 + 0.5 * broad)
    return a


def build_smear(w=512, h=256):
    v = np.linspace(0, 1, h, dtype=np.float32)[:, None] * np.ones((1, w), np.float32)
    smoke = fbm((h, w), (10, 3), 5, 21)
    torn = fbm((h, w), (30, 6), 3, 33)
    d = np.abs(2 * v - 1)  # symmetric, ragged on both sides
    reach = 0.55 + 0.45 * smoke
    a = np.clip(1 - d / reach, 0, 1) ** 1.3 * (0.4 + 0.8 * smoke) * (0.7 + 0.5 * torn)
    img = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2))
    return np.asarray(img, np.float32) / 255


# ---- v2 (2026-11-26, after user feedback: darker, more detailed, black flames, status icons) ----
def build_flame_sheet(cell=256):
    """4x4 flipbook: flame tongues that lick upward, flicker and burn out (tinted black in Studio)."""
    sheet = np.zeros((cell * 4, cell * 4), np.float32)
    yy, xx = np.mgrid[0:cell, 0:cell].astype(np.float32)
    u = xx / (cell - 1) - 0.5
    v = 1 - yy / (cell - 1)  # 0 at the bottom, 1 at the top
    for i in range(16):
        t = i / 15
        n1 = value_noise((cell, cell), (6, 4), 100 + i)
        n2 = value_noise((cell, cell), (14, 10), 200 + i)
        sway = 0.12 * np.sin(v * 7 + t * 9) + 0.08 * (n1 - 0.5)
        width = (0.32 - 0.26 * v) * (1.15 - 0.6 * t)  # narrows toward the tip and as it burns out
        body = np.clip(1 - np.abs(u - sway * v) / np.maximum(width, 0.01), 0, 1)
        height = 0.85 - 0.35 * t + 0.2 * (n1 - 0.5)
        body *= np.clip((height - v) / 0.25, 0, 1)
        body *= np.clip(v / 0.08, 0, 1) * (1 - 0.6 * t * (1 - v))
        tongues = np.clip((n2 - 0.35) * 2.2, 0, 1)
        a = np.clip(body * (0.55 + 0.7 * tongues), 0, 1) ** 1.1
        sheet[(i // 4) * cell:(i // 4 + 1) * cell, (i % 4) * cell:(i % 4 + 1) * cell] = a
    img = Image.fromarray((sheet * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
    return np.asarray(img, np.float32) / 255


def build_veins(w=512, h=256):
    """Dark streaks that run along the crescent inside its body (drawn on a dark Beam over the body)."""
    v = np.linspace(0, 1, h, dtype=np.float32)[:, None] * np.ones((1, w), np.float32)
    lines = fbm((h, w), (40, 2), 3, 61)
    lines = np.clip((lines - 0.55) / 0.15, 0, 1)
    breakup = fbm((h, w), (8, 4), 3, 71)
    d = np.abs(2 * v - 1)
    return lines * np.clip(1 - d / 0.85, 0, 1) * np.clip((breakup - 0.25) * 2, 0, 1)


def icon(draw_fn, size=256):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw_fn(img, size)
    return img


def draw_blood(img, size):
    from PIL import ImageDraw
    d = ImageDraw.Draw(img)
    c = size / 2
    r = size * 0.3
    pts = [(c, size * 0.08)]
    for k in range(0, 181, 5):
        a = math.radians(k)
        pts.append((c + r * math.cos(math.pi - a) * 1.0, size * 0.6 + r * math.sin(a)))
    pts.append((c, size * 0.08))
    d.polygon(pts, fill=(20, 0, 4, 255))  # outline (drawn bigger first)
    inner = [(c + (x - c) * 0.84, size * 0.6 + (y - size * 0.6) * 0.84) for x, y in pts]
    d.polygon(inner, fill=(200, 10, 30, 255))
    d.ellipse([c - r * 0.45, size * 0.52, c - r * 0.1, size * 0.72], fill=(255, 120, 130, 200))  # highlight
    return img


def draw_flake(img, size):
    from PIL import ImageDraw
    d = ImageDraw.Draw(img)
    c = size / 2
    for width, color in ((26, (10, 40, 70, 255)), (14, (190, 235, 255, 255))):
        for i in range(6):
            a = i / 6 * math.tau
            tip = (c + math.cos(a) * size * 0.42, c + math.sin(a) * size * 0.42)
            d.line([(c, c), tip], fill=color, width=width)
            for t in (0.5, 0.75):
                bx, by = c + math.cos(a) * size * 0.42 * t, c + math.sin(a) * size * 0.42 * t
                for sgn in (-1, 1):
                    b = a + sgn * 0.8
                    d.line([(bx, by), (bx + math.cos(b) * size * 0.12, by + math.sin(b) * size * 0.12)], fill=color, width=max(6, width - 10))
    return img


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    save(build_edge(), "edge")
    save(build_body(), "body")
    save(build_smear(), "smear")
    save(build_flame_sheet(), "flame")
    save(build_veins(), "veins")
    icon(draw_blood).save(os.path.join(OUT, "status_bleed.png"))
    icon(draw_flake).save(os.path.join(OUT, "status_freeze.png"))
    print("wrote flame, veins, status icons")

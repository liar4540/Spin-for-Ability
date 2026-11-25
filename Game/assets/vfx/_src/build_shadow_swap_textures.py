"""Shadow Swap textures (white on transparent; tinted in Studio via particle/trail Color).
Run: python build_shadow_swap_textures.py  -> Game/assets/vfx/textures/shadow_swap_*.png
  smoke   1024x1024 flipbook, 4x4 = 16 frames: a puff that swells, curls and tears apart into wisps
  wisp    512x128 trail strip: torn, streaky edges that thin out toward both ends
  swirl   512x512 three-armed spiral (materialization swirl on the ground)
"""
import math, os
import numpy as np
from PIL import Image, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "textures")
rng = np.random.default_rng(11)


def value_noise(shape, cells, seed):
    """Smooth value noise (bicubic-upsampled random grid), 0..1, tileable enough for sprites."""
    g = np.random.default_rng(seed).random((cells + 1, cells + 1))
    img = Image.fromarray((g * 255).astype(np.uint8)).resize(shape[::-1], Image.BICUBIC)
    return np.asarray(img, dtype=np.float32) / 255.0


def fbm(shape, base_cells, octaves, seed):
    total = np.zeros(shape, np.float32)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        total += amp * value_noise(shape, base_cells * 2 ** o, seed + o * 17)
        norm += amp
        amp *= 0.5
    return total / norm


def warp(field, dx, dy):
    h, w = field.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    sx = np.clip(xx + dx, 0, w - 1).astype(np.int32)
    sy = np.clip(yy + dy, 0, h - 1).astype(np.int32)
    return field[sy, sx]


def smoke_frame(i, n, size=256):
    t = i / (n - 1)
    c = (size - 1) / 2
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    r = np.hypot(xx - c, yy - c) / c
    ang = np.arctan2(yy - c, xx - c)
    # curl: rotate the noise lookup more toward the outside and over time (a turning puff)
    twist = (0.8 + 2.2 * t) * r
    nx = c + (xx - c) * np.cos(twist) - (yy - c) * np.sin(twist)
    ny = c + (xx - c) * np.sin(twist) + (yy - c) * np.cos(twist)
    big = fbm((size, size), 3, 5, 3)
    detail = fbm((size, size), 9, 4, 9)
    n1 = warp(big, (nx - xx) + (detail - 0.5) * 40 * (0.3 + t), (ny - yy) - (detail - 0.5) * 30 * (0.3 + t))
    n1 = np.clip((n1 - 0.25) / 0.6, 0, 1)  # more contrast: billows, not a blur
    # lumpy silhouette: the edge radius wobbles with angle (a few lobes) and noise
    lobes = 0.86 + 0.05 * np.sin(5 * ang + 1.3) + 0.06 * np.sin(2 * ang - 0.4) + 0.4 * (warp(detail, 0, 0) - 0.5)
    radius = (0.55 + 0.4 * (1 - (1 - t) ** 2)) * lobes  # swells fast, then slows
    falloff = np.clip(1 - (r / radius) ** 3, 0, 1)
    density = falloff * (0.55 + 0.9 * n1)
    # tear apart: raise the threshold over time so it breaks into wisps, and hollow the middle late
    thresh = 0.1 + 0.55 * t ** 1.5
    hollow = np.clip(1 - 0.75 * t * np.clip(1 - r / (radius * 0.7), 0, 1), 0, 1)
    a = np.clip((density * hollow - thresh) / (1 - thresh), 0, 1) ** 0.8
    a *= 1 - 0.3 * t  # thins out as it goes
    return Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))


def build_smoke():
    sheet = Image.new("RGBA", (1024, 1024), (255, 255, 255, 0))
    n = 16
    for i in range(n):
        a = smoke_frame(i, n)
        tile = Image.merge("RGBA", (Image.new("L", a.size, 255),) * 3 + (a,))
        sheet.paste(tile, ((i % 4) * 256, (i // 4) * 256))
    return sheet


def build_wisp(w=512, h=128):
    """Three wavy strands that cross and fray, torn edges, fading at both ends."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    u, v = xx / (w - 1), (yy - (h - 1) / 2) / ((h - 1) / 2)
    fray = fbm((h, w), 7, 4, 33)
    streak = fbm((h // 2, w // 16), 2, 3, 21)
    streak = np.asarray(Image.fromarray((streak * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC), np.float32) / 255
    a = np.zeros((h, w), np.float32)
    for k, (amp, freq, phase, width, strength) in enumerate(
            [(0.35, 2.0, 0.0, 0.22, 1.0), (0.3, 3.0, 2.1, 0.14, 0.8), (0.4, 1.5, 4.0, 0.1, 0.6)]):
        centre = amp * np.sin(np.pi * 2 * freq * u + phase) * np.sin(np.pi * u)
        wdt = width * (0.6 + 0.8 * fray)
        a = np.maximum(a, strength * np.clip(1 - ((v - centre) / wdt) ** 2, 0, 1))
    a *= 0.35 + 0.9 * np.clip((streak - 0.3) / 0.5, 0, 1)
    a *= np.clip(np.sin(np.pi * u), 0, 1) ** 0.5
    a = np.clip(a, 0, 1)
    img = Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
    return Image.merge("RGBA", (Image.new("L", (w, h), 255),) * 3 + (img,))


def build_swirl(size=512, arms=3):
    c = (size - 1) / 2
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    r = np.hypot(xx - c, yy - c) / c
    ang = np.arctan2(yy - c, xx - c)
    spiral = np.cos(arms * (ang + 3.2 * np.log(r + 0.05)))
    arm = np.clip((spiral - 0.35) / 0.65, 0, 1) ** 1.5
    noise = fbm((size, size), 6, 4, 45)
    ring = np.clip(1 - np.abs(r - 0.55) / 0.45, 0, 1) ** 1.2
    a = arm * ring * (0.6 + 0.6 * noise)
    a = np.clip(a, 0, 1)
    img = Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2))
    return Image.merge("RGBA", (Image.new("L", (size, size), 255),) * 3 + (img,))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, fn in [("smoke", build_smoke), ("wisp", build_wisp), ("swirl", build_swirl)]:
        fn().save(os.path.join(OUT, f"shadow_swap_{name}.png"))
        print("wrote", name)

"""Frost Bloom textures (white on transparent; tinted in Studio with ImageColor3 / particle Color).
Run: python build_frost_bloom_textures.py  -> Game/assets/vfx/textures/frost_bloom_*.png"""
import math, os, random
from PIL import Image, ImageDraw, ImageFilter, ImageChops

OUT = os.path.join(os.path.dirname(__file__), "..", "textures")
random.seed(7)

def glowify(img, radius, strength=1.0):
    """Add a soft glow under the crisp lines."""
    a = img.split()[3]
    blur = a.filter(ImageFilter.GaussianBlur(radius)).point(lambda v: min(255, int(v * strength)))
    glow = Image.merge("RGBA", (Image.new("L", img.size, 255),) * 3 + (blur,))
    return Image.alpha_composite(glow, img)

def ring(d, c, r, w, alpha=255):
    d.ellipse([c - r, c - r, c + r, c + r], outline=(255, 255, 255, alpha), width=w)

def rune_glyph(d, x, y, s, ang, kind):
    """Small angular frost glyph made of strokes, rotated to face the centre."""
    ca, sa = math.cos(ang), math.sin(ang)
    def P(u, v):
        return (x + (u * ca - v * sa) * s, y + (u * sa + v * ca) * s)
    shapes = [
        [((0, -1), (0, 1)), ((-0.6, -0.4), (0, 0.1)), ((0.6, -0.4), (0, 0.1))],
        [((-0.5, -1), (0.5, 1)), ((0.5, -1), (-0.5, 1)), ((-0.7, 0), (0.7, 0))],
        [((0, -1), (0.6, 0)), ((0.6, 0), (0, 1)), ((0, 1), (-0.6, 0)), ((-0.6, 0), (0, -1))],
        [((-0.6, -1), (-0.6, 1)), ((-0.6, -0.2), (0.6, -1)), ((-0.6, -0.2), (0.6, 0.6))],
        [((0, -1), (0, 1)), ((-0.6, -0.7), (0.6, -0.7)), ((-0.4, 0.5), (0.4, 0.5))],
        [((-0.6, 1), (0, -1)), ((0, -1), (0.6, 1)), ((-0.3, 0.2), (0.3, 0.2))],
    ]
    for a, b in shapes[kind % len(shapes)]:
        d.line([P(*a), P(*b)], fill=(255, 255, 255, 255), width=max(2, int(s * 0.22)))

def build_rune(size=1024):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = size / 2
    R = size * 0.47
    ring(d, c, R, 8)
    ring(d, c, R * 0.95, 3)
    # glyph band between 0.95 and 0.80
    n = 28
    for i in range(n):
        a = i / n * math.tau
        rr = R * 0.875
        rune_glyph(d, c + math.cos(a) * rr, c + math.sin(a) * rr, size * 0.022, a + math.pi / 2, i * 5 + 3)
    ring(d, c, R * 0.80, 4)
    # tick marks
    for i in range(72):
        a = i / 72 * math.tau
        r1, r2 = R * 0.80, R * (0.76 if i % 6 else 0.70)
        d.line([(c + math.cos(a) * r1, c + math.sin(a) * r1), (c + math.cos(a) * r2, c + math.sin(a) * r2)], fill=(255, 255, 255, 200), width=3)
    ring(d, c, R * 0.62, 3)
    # two interlocked hexagrams (12-point star) as in the reference's inner pattern
    for rot in (0, math.pi / 6):
        for k in range(2):
            pts = [(c + math.cos(rot + k * math.pi / 3 + j * math.tau / 3) * R * 0.62,
                    c + math.sin(rot + k * math.pi / 3 + j * math.tau / 3) * R * 0.62) for j in range(3)]
            d.polygon(pts, outline=(255, 255, 255, 230), width=3)
    ring(d, c, R * 0.36, 4)
    ring(d, c, R * 0.30, 2)
    # inner snowflake
    for i in range(6):
        a = i / 6 * math.tau
        tip = (c + math.cos(a) * R * 0.28, c + math.sin(a) * R * 0.28)
        d.line([(c, c), tip], fill=(255, 255, 255, 255), width=5)
        for t in (0.45, 0.7):
            bx, by = c + math.cos(a) * R * 0.28 * t, c + math.sin(a) * R * 0.28 * t
            for s in (-1, 1):
                b = a + s * 0.7
                d.line([(bx, by), (bx + math.cos(b) * R * 0.07, by + math.sin(b) * R * 0.07)], fill=(255, 255, 255, 255), width=4)
    # diamond points at the 4 compass directions just outside the outer ring
    for i in range(4):
        a = i / 4 * math.tau
        x, y = c + math.cos(a) * R * 0.99, c + math.sin(a) * R * 0.99
        s = size * 0.018
        d.polygon([(x + math.cos(a) * s * 1.6, y + math.sin(a) * s * 1.6), (x + math.cos(a + 1.57) * s, y + math.sin(a + 1.57) * s),
                   (x - math.cos(a) * s * 1.6, y - math.sin(a) * s * 1.6), (x - math.cos(a + 1.57) * s, y - math.sin(a + 1.57) * s)], fill=(255, 255, 255, 255))
    return glowify(img, 10, 1.6)

def build_glow(size=256):
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    px = img.load()
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            r = math.hypot(x - c, y - c) / c
            a = max(0.0, 1 - r) ** 2.2
            px[x, y] = (255, 255, 255, int(a * 255))
    return img

def build_flake(size=128):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = size / 2
    for i in range(6):
        a = i / 6 * math.tau
        d.line([(c, c), (c + math.cos(a) * c * 0.85, c + math.sin(a) * c * 0.85)], fill=(255, 255, 255, 255), width=5)
        for t in (0.4, 0.65):
            bx, by = c + math.cos(a) * c * 0.85 * t, c + math.sin(a) * c * 0.85 * t
            for s in (-1, 1):
                b = a + s * 0.75
                d.line([(bx, by), (bx + math.cos(b) * c * 0.22, by + math.sin(b) * c * 0.22)], fill=(255, 255, 255, 255), width=4)
    return glowify(img, 3, 1.2)

def build_sparkle(size=128):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            dx, dy = abs(x - c) / c, abs(y - c) / c
            star = max(0.0, 1 - (dx * 7 + dy)) + max(0.0, 1 - (dy * 7 + dx))  # 4-point star
            core = max(0.0, 1 - math.hypot(dx, dy) * 3) ** 2
            a = min(1.0, star * 0.9 + core)
            px[x, y] = (255, 255, 255, int(a * 255))
    return img

def build_mist(size=256):
    """Soft cloud puff: blurred random blobs inside a radial falloff."""
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    for _ in range(40):
        r = random.uniform(0.08, 0.2) * size
        x = random.gauss(size / 2, size * 0.13)
        y = random.gauss(size / 2, size * 0.13)
        d.ellipse([x - r, y - r, x + r, y + r], fill=random.randint(60, 140))
    img = img.filter(ImageFilter.GaussianBlur(size * 0.06))
    fall = build_glow(size).split()[3].point(lambda v: min(255, int(v * 1.6)))
    a = ImageChops.multiply(img, fall).point(lambda v: min(255, int(v * 2.2)))
    return Image.merge("RGBA", (Image.new("L", (size, size), 255),) * 3 + (a,))

def build_ring(size=512):
    """Thin glowing ring for the bloom pulse (fades toward its inner edge)."""
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    px = img.load()
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            r = math.hypot(x - c, y - c) / c
            a = 0.0
            if r <= 1:
                a = max(0.0, 1 - abs(r - 0.93) / 0.05) + max(0.0, (r - 0.6) / 0.33) ** 3 * 0.35
            px[x, y] = (255, 255, 255, int(min(1.0, a) * 255))
    return img

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, fn in [("rune", build_rune), ("glow", build_glow), ("flake", build_flake), ("sparkle", build_sparkle), ("mist", build_mist), ("ring", build_ring)]:
        fn().save(os.path.join(OUT, f"frost_bloom_{name}.png"))
        print("wrote", name)

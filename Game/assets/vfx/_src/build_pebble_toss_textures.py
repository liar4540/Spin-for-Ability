"""Spin for Abilities - Pebble Toss, stage 4: particle textures (Blender 5.2).

Run inside Blender (MCP or Text Editor):
    exec(open(r"<this file>").read())

Visual source of truth: images/abilities/pebble toss.png ("Launch Dust", "Motion Trail", the white
star flash on hit). Same method as build_ember_fist.py: drawn per pixel with numpy, white/grey +
alpha, tinted in Studio (vault: 11 Abilities -> Rules). 512x512, transparent.

Outputs (Game/assets/vfx/textures/):
    dust_puff.png      soft, round, cloudy smoke blob (lit from the top, darker underside)
    impact_flare.png   sharp 8-point star (4 long + 4 short spikes) with a bright centre
    speed_lines.png    4 horizontal streaks: solid on the LEFT, fading out to the RIGHT
                       (Beam: put the solid end at the rock)
    ../previews/pebble_stage4_textures.png   all three side by side on dark grey #2E2E33
"""
import bpy, os
import numpy as np

TEX_DIR = r"C:\Roblox\Spin for ability\Game\assets\vfx\textures"
PREVIEW = r"C:\Roblox\Spin for ability\Game\assets\vfx\previews\pebble_stage4_textures.png"
N = 512


def save_png(path, rgba):
    """rgba: float array (h, w, 4) in 0..1, row 0 = top."""
    h, w, _ = rgba.shape
    name = os.path.basename(path)
    old = bpy.data.images.get(name)
    if old:
        bpy.data.images.remove(old)
    img = bpy.data.images.new(name, width=w, height=h, alpha=True)
    img.pixels.foreach_set(np.flipud(np.clip(rgba, 0, 1)).astype(np.float32).ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    return path


def grid(n=N):
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    return (x + 0.5) / n * 2 - 1, (y + 0.5) / n * 2 - 1        # -1..1, y down


def value_noise(n, cells, seed):
    rnd = np.random.default_rng(seed)
    g = rnd.random((cells + 1, cells + 1)).astype(np.float32)
    t = np.linspace(0, cells, n, endpoint=False, dtype=np.float32)
    i = t.astype(int)
    f = t - i
    f = f * f * (3 - 2 * f)
    a = g[i][:, i]; b = g[i][:, i + 1]; c = g[i + 1][:, i]; d = g[i + 1][:, i + 1]
    fx = f[None, :]; fy = f[:, None]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(n, seed, octaves=5, base=4):
    out = np.zeros((n, n), np.float32)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        out += amp * value_noise(n, base * 2 ** o, seed + o)
        total += amp
        amp *= 0.5
    return out / total


def smoothstep(e0, e1, v):
    t = np.clip((v - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def dust_puff():
    """Cauliflower cloud: a few overlapping soft balls, broken up by noise, lit from above."""
    x, y = grid()
    balls = [(0.0, 0.12, 0.62), (-0.32, 0.18, 0.42), (0.34, 0.2, 0.40), (-0.14, -0.22, 0.42),
             (0.2, -0.2, 0.40), (0.0, -0.42, 0.30)]
    dens = np.zeros_like(x)
    light = np.zeros_like(x)
    for bx, by, br in balls:
        d = np.sqrt((x - bx) ** 2 + (y - by) ** 2) / br
        ball = np.clip(1 - d * d, 0, 1)
        dens = np.maximum(dens, ball)
        # each ball is brighter towards its top-left (y down = -1 is up)
        lit = np.clip(0.5 - ((x - bx) * 0.35 + (y - by) * 0.9) / br, 0, 1)
        light = np.where(ball > 0.02, np.maximum(light, lit * ball), light)
    noise = fbm(N, 31)
    alpha = smoothstep(0.08, 0.75, dens + (noise - 0.5) * 0.55) * smoothstep(0.0, 0.2, dens)
    r = np.sqrt(x * x + y * y)
    alpha *= smoothstep(0.98, 0.80, r)                         # never touches the edges
    shade = 0.72 + 0.28 * np.clip(light * 1.4 + (noise - 0.5) * 0.3, 0, 1)
    return np.dstack([shade, shade, shade, alpha * 0.92])


def impact_flare():
    """8-point star: 4 long spikes (vertical/horizontal), 4 short diagonal ones, bright centre."""
    x, y = grid()
    r = np.sqrt(x * x + y * y)
    theta = np.arctan2(y, x)
    star = np.zeros_like(x)
    spikes = [(k * np.pi / 2, 0.96, 0.15) for k in range(4)] + \
             [(np.pi / 4 + k * np.pi / 2, 0.52, 0.12) for k in range(4)]
    for ang, length, width in spikes:
        dth = np.abs((theta - ang + np.pi) % (2 * np.pi) - np.pi)
        # spike edge: width shrinks linearly to a sharp point at `length`
        half = width * np.clip(1 - r / length, 0, 1)
        along = np.clip(r / length, 0, 1)
        inside = dth * np.maximum(r, 1e-4) < half * (1 - along * 0.15)
        edge = smoothstep(0.0, 0.012, half - dth * np.maximum(r, 1e-4))
        star = np.maximum(star, np.where(r < length, edge, 0))
    core = np.clip(1 - r / 0.16, 0, 1) ** 0.8
    halo = np.clip(1 - r / 0.62, 0, 1) ** 3 * 0.45
    alpha = np.clip(np.maximum(star, np.maximum(core, halo)), 0, 1)
    # white everywhere, a touch of grey towards the spike tips so the centre reads brightest
    shade = np.clip(1.0 - 0.25 * smoothstep(0.25, 0.95, r) + core, 0, 1)
    return np.dstack([shade, shade, shade, alpha])


def speed_lines():
    """4 horizontal streaks: thick + solid at the left, thinning and fading out to the right."""
    x, y = grid()
    u = (x + 1) / 2                                            # 0 left .. 1 right
    alpha = np.zeros_like(x)
    # (centre y, thickness at the left, start u, end u)
    streaks = [(-0.42, 0.050, 0.04, 0.78), (-0.12, 0.075, 0.00, 1.00), (0.16, 0.060, 0.08, 0.90),
               (0.44, 0.040, 0.14, 0.70)]
    for cy, thick, u0, u1 in streaks:
        t = np.clip((u - u0) / (u1 - u0), 0, 1)
        half = thick * (1 - t) ** 0.8                           # tapers to a point on the right
        line = smoothstep(0.0, 0.012, half - np.abs(y - cy))
        head = smoothstep(u0, u0 + 0.008, u)                    # crisp left end
        fade = (1 - t) ** 1.6                                   # solid left, fading right
        alpha = np.maximum(alpha, line * head * fade * (u <= u1))
    shade = 0.85 + 0.15 * (1 - u)
    return np.dstack([shade, shade, shade, alpha])


def preview(images, bg=(0x2E / 255, 0x2E / 255, 0x33 / 255), gap=32):
    tiles = []
    for im in images:
        a = im[..., 3:4]
        tiles.append(im[..., :3] * a + np.array(bg, np.float32) * (1 - a))
    h = N + 2 * gap
    w = len(tiles) * N + (len(tiles) + 1) * gap
    out = np.ones((h, w, 3), np.float32) * np.array(bg, np.float32)
    for i, t in enumerate(tiles):
        x0 = gap + i * (N + gap)
        out[gap:gap + N, x0:x0 + N] = t
        # thin tile border so the 512x512 frame is visible
        out[gap - 1, x0:x0 + N] = out[gap + N, x0:x0 + N] = 0.32
        out[gap:gap + N, x0 - 1] = out[gap:gap + N, x0 + N] = 0.32
    return np.dstack([out, np.ones((h, w), np.float32)])


def build():
    os.makedirs(TEX_DIR, exist_ok=True)
    made = {"dust_puff": dust_puff(), "impact_flare": impact_flare(), "speed_lines": speed_lines()}
    for name, im in made.items():
        save_png(os.path.join(TEX_DIR, name + ".png"), im)
        a = im[..., 3]
        edge = max(a[0].max(), a[-1].max(), a[:, 0].max(), a[:, -1].max())
        print(f"{name}.png  {im.shape[1]}x{im.shape[0]}  alpha max {a.max():.2f}  "
              f"covered {np.mean(a > 0.05) * 100:.0f}%  alpha on the border {edge:.2f}")
    save_png(PREVIEW, preview(list(made.values())))
    print("preview", PREVIEW)


build()

"""Spin for Abilities - Ember Fist VFX assets (Blender 5.2, headless).

Run:
    blender -b --factory-startup --python build_ember_fist.py

Visual source of truth: images/abilities/fiery fist.png (vault: 11 Abilities -> Ember Fist:
"Orange-white flash on the fist, small fire burst + shock ring at the hit").

Meshes (1 Blender unit = 1 stud, +Y = forward, +Z = up; vault: 11 Abilities -> Rules):
    reused from the shared kit (../meshes, built by build_vfx.py): shock_ring, crescent_thin
    new:                                                         spike_burst  (impact starburst)
How they reach Roblox: each mesh is RENDERED into a sprite (orthographic, transparent, white/grey
emission) and played on oriented particles in Studio (flat on the ground, upright facing the punch,
or facing the camera). Real MeshParts would need either a manual 3D import or the experience's
"Allow Mesh / Image APIs" setting (runtime EditableMesh); sprites need neither.
Outputs:
    ../meshes/spike_burst.glb                     new kit mesh
    ../textures/ember_sprite_ring.png             shock_ring, seen from above
    ../textures/ember_sprite_burst.png            spike_burst, seen head-on
    ../textures/ember_sprite_arc.png              crescent_thin, seen from above
    ../textures/ember_*.png                       white/grey particle textures, recoloured in Studio
    ../textures/ember_fist_icon.png               ability icon (cropped from the reference image)
    ../previews/ember_fist.png                    layer check at game camera distance

Build script is the source of truth: change a number here and rerun.
"""
import bpy, bmesh, math, os, json, random, zlib
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                                   # Game/assets/vfx
MESH_DIR = os.path.join(ROOT, "meshes")
TEX_DIR = os.path.join(ROOT, "textures")
PREVIEW_DIR = os.path.join(ROOT, "previews")
REFERENCE = os.path.normpath(os.path.join(ROOT, "..", "..", "..", "images", "abilities", "fiery fist.png"))
for d in (TEX_DIR, PREVIEW_DIR):
    os.makedirs(d, exist_ok=True)

KIT_MESHES = ["shock_ring", "crescent_thin", "sphere_shell"]


def rng_for(name):
    """Seed per asset, so adding one never changes the others."""
    return random.Random(zlib.crc32(name.encode()))


# ------------------------------------------------------------------ scene

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_kit(name):
    bpy.ops.import_scene.gltf(filepath=os.path.join(MESH_DIR, name + ".glb"))
    ob = bpy.context.selected_objects[0]
    ob.name = name
    return ob


def new_object(name, bm, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def spike_burst(name, count=14, length=1.0, base_width=0.12, spread_deg=60.0):
    """Starburst of flat tapered spikes fanning forward (+Y) from the origin, length 1 (scale it
    in Studio). Each spike is two crossed cards so it reads from every side.
    U: 0 = root -> 1 = tip, V across. Lengths vary so the outline looks hand-drawn, like the
    reference's impact rays."""
    rnd = rng_for(name)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.verify()
    golden = math.pi * (3 - math.sqrt(5))
    for i in range(count):
        # Even spread over a cone around +Y (sunflower pattern), plus jitter.
        t = (i + 0.5) / count
        tilt = math.radians(spread_deg) * math.sqrt(t) + rnd.uniform(-0.08, 0.08)
        spin = i * golden + rnd.uniform(-0.2, 0.2)
        d = Vector((math.sin(tilt) * math.cos(spin), math.cos(tilt), math.sin(tilt) * math.sin(spin))).normalized()
        L = length * rnd.uniform(0.55, 1.0)
        w = base_width * rnd.uniform(0.7, 1.3)
        side_a = d.cross(Vector((0, 0, 1)))
        if side_a.length < 1e-3:
            side_a = Vector((1, 0, 0))
        side_a.normalize()
        side_b = d.cross(side_a).normalized()
        for side in (side_a, side_b):
            root_l = bm.verts.new(-side * w / 2)
            root_r = bm.verts.new(side * w / 2)
            mid_l = bm.verts.new(d * L * 0.35 - side * w * 0.45)
            mid_r = bm.verts.new(d * L * 0.35 + side * w * 0.45)
            tip = bm.verts.new(d * L)
            for verts, uvs in (([root_l, root_r, mid_r, mid_l], [(0, 0), (0, 1), (0.35, 1), (0.35, 0)]),
                               ([mid_l, mid_r, tip], [(0.35, 0), (0.35, 1), (1, 0.5)])):
                f = bm.faces.new(verts)
                for loop, t2 in zip(f.loops, uvs):
                    loop[uv].uv = t2
    return new_object(name, bm, smooth=False)


def export_glb(ob, path):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLB",
                              export_apply=True, export_materials="NONE")



# ------------------------------------------------------------------ textures (white/grey + alpha)

def save_png(name, rgba):
    """rgba: float array (h, w, 4) in 0..1, row 0 = top."""
    h, w, _ = rgba.shape
    img = bpy.data.images.new(name, width=w, height=h, alpha=True)
    img.pixels.foreach_set(np.flipud(np.clip(rgba, 0, 1)).astype(np.float32).ravel())
    img.filepath_raw = os.path.join(TEX_DIR, name + ".png")
    img.file_format = "PNG"
    img.save()
    return img.filepath_raw


def grid(n):
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


def fbm(n, seed, octaves=4, base=4):
    out = np.zeros((n, n), np.float32)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        out += amp * value_noise(n, base * 2 ** o, seed + o)
        total += amp
        amp *= 0.5
    return out / total


def shade(alpha, core):
    """White-hot core fading to grey: Studio's colour tints the grey, the core stays bright."""
    rgb = 0.55 + 0.45 * core
    return np.dstack([rgb, rgb, rgb, alpha])


def flame_frame(n, seed, phase):
    """Anime flame tongue: teardrop with a pointed, wavering tip and a hot base."""
    x, y = grid(n)
    noise = fbm(n, seed, octaves=4, base=3)
    yy = (y + 1) / 2                                            # 0 top .. 1 bottom
    sway = 0.18 * np.sin(yy * 5.0 + phase) * (1 - yy)
    width = 0.62 * np.clip(yy, 0, 1) ** 0.55                    # narrow at the top, round at the base
    width *= np.where(yy > 0.78, np.sqrt(np.clip(1 - (yy - 0.78) / 0.22, 0, 1)), 1)
    edge = np.abs(x - sway) / np.maximum(width, 1e-3)
    shape = np.clip(1 - edge + (noise - 0.5) * 0.9, 0, 1)
    shape *= np.clip((yy - 0.05) * 6, 0, 1)
    alpha = np.clip(shape * 2.2, 0, 1) ** 1.2
    core = np.clip(1 - np.sqrt((x - sway * 0.5) ** 2 / 0.08 + (yy - 0.72) ** 2 / 0.06), 0, 1)
    return shade(alpha, core)


def textures():
    paths = {}
    # 4-frame flame flipbook (2x2 grid, Roblox FlipbookLayout Grid2x2).
    frames = [flame_frame(256, 11 + k, k * 1.6) for k in range(4)]
    top = np.concatenate([frames[0], frames[1]], axis=1)
    bottom = np.concatenate([frames[2], frames[3]], axis=1)
    paths["Flame"] = save_png("ember_flame", np.concatenate([top, bottom], axis=0))

    n = 256
    x, y = grid(n)
    r = np.sqrt(x * x + y * y)
    # Soft glow with a hot core (fist glow, impact flash).
    glow = np.clip(1 - r, 0, 1) ** 2.2
    paths["Glow"] = save_png("ember_glow", shade(glow, np.clip(1 - r * 2.5, 0, 1)))

    # Spark streak: long thin needle along Y (VelocityParallel stretches it further).
    streak = np.clip(1 - np.abs(x) / (0.12 * (1 - np.abs(y)) + 1e-3), 0, 1) * np.clip(1 - np.abs(y), 0, 1) ** 0.6
    paths["Spark"] = save_png("ember_spark", shade(streak, np.clip(1 - np.abs(x) * 12, 0, 1)))

    # Ember flake: the reference's leaf-shaped cinders (pointed both ends, curved).
    bend = 0.25 * (y ** 2)
    leaf = np.clip(1 - (np.abs(x - bend) / (0.38 * np.sqrt(np.clip(1 - y * y, 0, 1)) + 1e-3)), 0, 1)
    paths["Ember"] = save_png("ember_flake", shade(np.clip(leaf * 1.6, 0, 1), np.clip(leaf * 1.2 - 0.3, 0, 1)))

    # Smoke puff: lumpy soft blob.
    puff = np.clip(1 - r + (fbm(n, 99, octaves=5, base=4) - 0.5) * 0.8, 0, 1) ** 1.5
    paths["Smoke"] = save_png("ember_smoke", np.dstack([np.full_like(r, 0.8)] * 3 + [puff * 0.9]))
    return paths


def icon():
    """Ability icon: the reference sheet's 'Fist Glow' swatch, cropped square, 256 px."""
    src = bpy.data.images.load(REFERENCE)
    w, h = src.size
    px = np.array(src.pixels[:], dtype=np.float32).reshape(h, w, 4)
    px = np.flipud(px)                                           # row 0 = top
    # Fist Glow swatch sits at about x 55..185, y 650..790 on the 1672x941 sheet.
    sx, sy = w / 1672, h / 941
    x0, x1, y0, y1 = int(52 * sx), int(188 * sx), int(652 * sy), int(788 * sy)
    crop = px[y0:y1, x0:x1]
    n = 256
    yi = (np.arange(n) * crop.shape[0] / n).astype(int)
    xi = (np.arange(n) * crop.shape[1] / n).astype(int)
    out = crop[yi][:, xi].copy()
    out[..., 3] = 1
    return save_png("ember_fist_icon", out)


# ------------------------------------------------------------------ mesh sprites

def sprite_material(name, along, ramp_points, edge_axis=None, edge_points=None):
    """Emission-only material, white/grey, whose brightness + alpha follow the mesh's UVs:
    `along` ('U' or 'V') through ramp_points [(pos, value)], optionally multiplied by a second
    ramp on the other axis. value = brightness and alpha together (white core, grey falloff)."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.surface_render_method = "BLENDED"
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    uv = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(uv.outputs["UV"], sep.inputs[0])

    def ramp(axis, points):
        r = nt.nodes.new("ShaderNodeValToRGB")
        els = r.color_ramp.elements
        els[0].position, els[0].color = points[0][0], (points[0][1],) * 3 + (1,)
        els[1].position, els[1].color = points[-1][0], (points[-1][1],) * 3 + (1,)
        for pos, val in points[1:-1]:
            e = els.new(pos)
            e.color = (val,) * 3 + (1,)
        nt.links.new(sep.outputs["X" if axis == "U" else "Y"], r.inputs[0])
        return r.outputs["Color"]

    value = ramp(along, ramp_points)
    if edge_axis:
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = "MULTIPLY"
        mul.inputs["Factor"].default_value = 1
        nt.links.new(value, mul.inputs[6])
        nt.links.new(ramp(edge_axis, edge_points), mul.inputs[7])
        value = mul.outputs[2]
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(value, em.inputs["Color"])
    clear = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    bw = nt.nodes.new("ShaderNodeRGBToBW")
    nt.links.new(value, bw.inputs[0])
    nt.links.new(bw.outputs[0], mix.inputs[0])
    nt.links.new(clear.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])
    return mat


def render_sprite(ob, mat, cam_location, cam_target, ortho_scale, filename, size=512):
    sc = bpy.context.scene
    for other in sc.objects:
        if other.type == "MESH":
            other.hide_render = other is not ob
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    cam = bpy.data.objects.get("sprite_cam")
    if not cam:
        cam = bpy.data.objects.new("sprite_cam", bpy.data.cameras.new("sprite_cam"))
        sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = ortho_scale
    cam.location = Vector(cam_location)
    cam.rotation_euler = (Vector(cam_target) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = size
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sc.render.filepath = os.path.join(TEX_DIR, filename)
    bpy.ops.render.render(write_still=True)
    return sc.render.filepath


def sprites(objs):
    """Render the kit meshes into sprites. Shapes come from the meshes; brightness from their UVs."""
    paths = {}
    # Shock ring from above: V 0 inner -> 1 outer. Soft inside, white-hot outer edge.
    ring_mat = sprite_material("ring", "V", [(0.0, 0.0), (0.45, 0.35), (0.85, 1.0), (1.0, 0.0)])
    paths["Ring"] = render_sprite(objs["shock_ring"], ring_mat, (0, 0, 5), (0, 0, 0), 2.05, "ember_sprite_ring.png")
    # Spike burst head-on (camera in front, looking back along -Y): U 0 root -> 1 tip.
    burst_mat = sprite_material("burst", "U", [(0.0, 1.0), (0.4, 0.8), (1.0, 0.0)])
    paths["Burst"] = render_sprite(objs["spike_burst"], burst_mat, (0, 5, 0), (0, 0, 0), 1.9, "ember_sprite_burst.png")
    # Swing crescent from above: U 0 tail -> 1 head, V 0 inner -> 1 outer (bright outer edge).
    arc_mat = sprite_material("arc", "U", [(0.0, 0.0), (0.55, 0.8), (0.9, 1.0), (1.0, 0.6)],
                              edge_axis="V", edge_points=[(0.0, 0.15), (0.75, 0.7), (1.0, 1.0)])
    # The crescent's circle centre is the origin; its bounds centre is 2.89 studs forward (+Y).
    paths["Arc"] = render_sprite(objs["crescent_thin"], arc_mat, (0, 2.89, 5), (0, 2.89, 0), 14.2, "ember_sprite_arc.png")
    for ob in objs.values():
        ob.hide_render = False
    return paths


# ------------------------------------------------------------------ preview

def emission_mat(name, rgb, strength):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    em = nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*rgb, 1)
    em.inputs["Strength"].default_value = strength
    mat.node_tree.links.new(em.outputs[0], out.inputs[0])
    return mat


def preview(objs):
    """The impact moment at game camera distance: ground ring, upright ring at the fist,
    spike burst forward, fist glow ball, swing crescent behind."""
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 960, 540
    sc.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.02, 0.02, 0.03, 1)
    sc.world = world
    orange = (1.0, 0.35, 0.05)
    white = (1.0, 0.9, 0.7)
    fist = Vector((0, 2.5, 1.2))

    def place(src, name, loc, rot, scale, mat):
        ob = src.copy()
        ob.data = src.data.copy()
        ob.name = name
        sc.collection.objects.link(ob)
        ob.location, ob.rotation_euler, ob.scale = loc, rot, scale
        ob.data.materials.clear()
        ob.data.materials.append(mat)

    place(objs["shock_ring"], "ground_ring", (0, 2.8, 0.02), (0, 0, 0), (5, 5, 1), emission_mat("o", orange, 6))
    place(objs["shock_ring"], "fist_ring", fist + Vector((0, 0.9, 0)), (math.radians(90), 0, 0), (2.2, 2.2, 1),
          emission_mat("w", white, 8))
    place(objs["spike_burst"], "burst", fist + Vector((0, 0.4, 0)), (0, 0, 0), (3.5, 3.5, 3.5), emission_mat("o2", orange, 8))
    place(objs["sphere_shell"], "fist_glow", fist, (0, 0, 0), (0.6, 0.6, 0.6), emission_mat("w2", white, 12))
    place(objs["crescent_thin"], "swing", (0, -0.5, 1.4), (0, math.radians(-70), 0), (0.25, 0.25, 0.25),
          emission_mat("o3", orange, 5))
    for ob in objs.values():
        ob.hide_render = True

    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    sc.collection.objects.link(cam)
    cam.location = Vector((11, -4, 5))
    cam.rotation_euler = (Vector((0, 2, 1)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    sc.render.filepath = os.path.join(PREVIEW_DIR, "ember_fist.png")
    bpy.ops.render.render(write_still=True)
    return sc.render.filepath


# ------------------------------------------------------------------ main

def main():
    clear_scene()
    objs = {name: import_kit(name) for name in KIT_MESHES}
    burst = spike_burst("spike_burst")
    export_glb(burst, os.path.join(MESH_DIR, "spike_burst.glb"))
    objs["spike_burst"] = burst

    report = {"textures": textures(), "sprites": sprites(objs), "icon": icon(), "preview": preview(objs)}
    print("EMBER_FIST_BUILD_OK", json.dumps(report, indent=1))


main()

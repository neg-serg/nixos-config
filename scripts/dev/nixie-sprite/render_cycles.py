#!/usr/bin/env python3
"""The tube, path-traced on the GPU: Blender Cycles with HIP on the Radeon
(RDNA4, gfx1201), with OpenImageDenoise on the result.

Same scene as render_tube.py — the geometry is imported from it, so the two
renderers cannot drift apart — but a different renderer underneath:

    render_tube.py   Mitsuba 3, llvm_ad_rgb: a CPU vectoriser, 1024 spp, no
                     denoiser. The grain in the dark glass is what that costs.
    render_cycles.py Cycles: HIP device, thousands of spp, OIDN. The metals get
                     their anisotropy and the glass its dispersion for free.

    DRJIT_LIBLLVM_PATH=... uv run --with mitsuba --with numpy python \
        scripts/dev/nixie-sprite/render_tube.py /tmp/ms/beauty     # the default
    blender -b --python scripts/dev/nixie-sprite/render_cycles.py -- \
        /tmp/ms/beauty                                             # this one

Blender with HIP on an AMD card, and the Nix cache that hides it:

    nix build --print-out-paths --impure --expr \
        'let p = import (builtins.getFlake "nixpkgs") {}; \
         in p.blender.override { rocmSupport = true; }'

The stock Blender in nixpkgs is built CUDA-only — `compute_device_type` has no
HIP — so the ROCm variant has to be built. The build also needs the Determinate
substituter out of the way: it answers slowly enough that nix times out on every
narinfo and the build never starts, which reads as "the cache is broken".

    NIX_CONFIG="extra-substituters =
    extra-trusted-substituters =
    substituters = https://cache.nixos.org
    trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="

Status: this one is NOT the default, and it is not yet the better renderer.

The GPU path works and is fast — 1024 spp of the full 1120 x 2304 beauty with
the metal and glass passes on top take about four minutes end to end on the
RX 9070 XT, against roughly twenty for the same from Mitsuba. Quality is a
different question: with OpenImageDenoise the thin anode wires come out smeared
and the cage reads as plastic, and without it even 2048 spp leaves a grain
Mitsuba's 1024 does not have (measured: local contrast across the cage 49.4
against Mitsuba's 60.8). Vision reviews of the side-by-side picked Mitsuba every
time. So the sprite in the repo is still Mitsuba's; this file is kept because the
scene is shared, the pass structure is identical, and everything here is what a
later Cycles render will need — the gain, the filters and the materials are
calibrated and documented below.

Rendering is split the way the sprite needs it, not the way a camera sees it:

  * the beauty pass is the room the login screen lives in (dim), where the only
    bright thing is the discharge in the gas;
  * the metal pass is the same geometry under a uniform white world, rendered
    with the glass hidden — that flat coverage is the sprite's alpha;
  * the glass pass is the envelope alone, lit by the studio softboxes and
    nothing else, because its reflections are added on top of the numeral and
    must never hide it.

All three are written as float OpenEXR, which post.py tone-maps into the sprite.
"""

import glob
import math
import os
import sys

# Cycles reaches the HIP runtime through hipew, which looks for libamdhip64.so on
# the loader path — and picking a specific Nix store path for it here would pin
# the script to one ROCm build. The library is found and put on the path first.
for _clr in sorted(glob.glob("/nix/store/*-clr-*/lib/libamdhip64.so")):
    _lib = os.path.dirname(_clr)
    if _lib not in os.environ.get("LD_LIBRARY_PATH", "").split(":"):
        os.environ["LD_LIBRARY_PATH"] = (
            _lib + ":" + os.environ.get("LD_LIBRARY_PATH", "")
        )
    break

import bpy  # noqa: E402
import numpy as np  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_tube as R  # noqa: E402  (geometry only; it imports Mitsuba lazily)

W, HH = 1120, 2304
SAMPLES = int(os.environ.get("CYCLES_SAMPLES", 2048))
GLASS_SAMPLES = int(os.environ.get("CYCLES_GLASS_SAMPLES", 1024))
DENOISE = os.environ.get("CYCLES_DENOISE", "1") not in ("0", "", "false")
LIT = os.environ.get("CYCLES_LIT", "8")
LIT = None if LIT.lower() in ("none", "off", "") else int(LIT)
# The gain from Mitsuba's radiance units to Cycles' watts. Cycles spreads a lamp's
# power over its area in METRES while this scene is in millimetres, so the same
# studio reads far weaker here.
#
# The number was first measured against the anode cage — and the cage is thin
# wires, whose brightness barely moves with the gain, so 4.5e6 came out. It is the
# collar and the glass that carry the studio's actual exposure, and at 4.5e6 they
# arrived at a linear 2.1/2.9 where Mitsuba's are 0.16/0.22: a hundred times too
# hot, straight to white through the tone map. 3.2e5 puts the collar's linear
# value where Mitsuba has it (and the cage a little darker, which is fine — the
# numeral is the only thing in the tube that should be bright).
EXPOSURE_GAIN = float(os.environ.get("CYCLES_GAIN", 4.2e5))
WORLD_GAIN = float(os.environ.get("CYCLES_WORLD_GAIN", 1.0))
CAM_DIST = 300.0


# ---- scene plumbing ---------------------------------------------------------


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def device():
    """The GPU, if Cycles can see one; the CPU otherwise."""
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for backend in ("HIP", "ROCM", "OPTIX", "CUDA", "ONEAPI", "METAL"):
        try:
            prefs.compute_device_type = backend
            prefs.get_devices()
        except Exception:
            continue
        gpus = [d for d in prefs.devices if d.type != "CPU"]
        if gpus:
            for d in prefs.devices:
                d.use = d.type != "CPU"
            print("Cycles device: %s on %s" % (backend, gpus[0].name))
            return backend
    for d in prefs.devices:
        d.use = d.type == "CPU"
    print("Cycles device: CPU (no GPU backend answered)")
    return "NONE"


def mesh(name, verts, faces, smooth=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata(
        [tuple(map(float, v)) for v in verts],
        [],
        [tuple(map(int, f)) for f in faces],
    )
    me.validate()
    if smooth:
        for poly in me.polygons:
            poly.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def principled(name, base, metallic=0.0, rough=0.5, spec=0.5):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*base, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = rough
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = spec
    return mat


def material_glass():
    mat = bpy.data.materials.new("glass")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    # Not a mirror: the polished surface put a sharp image of the softboxes on the
    # glass, and those highlights outshone the discharge. Real envelope glass has
    # a slight draw waviness that spreads them.
    bsdf.inputs["Roughness"].default_value = 0.18
    bsdf.inputs["Transmission Weight"].default_value = 1.0
    bsdf.inputs["IOR"].default_value = 1.52
    return mat


def material_emission(name, rgb, strength):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = (*rgb, 1.0)
    emit.inputs["Strength"].default_value = strength
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    return mat


def assign(ob, mat):
    ob.data.materials.append(mat)


def area_light(name, origin, size, radiance):
    """A studio softbox: same corners, same radiance as the Mitsuba scene."""
    light = bpy.data.lights.new(name, "AREA")
    light.shape = "RECTANGLE"
    light.size = float(size[0])
    light.size_y = float(size[1])
    light.energy = float(np.mean(radiance)) * EXPOSURE_GAIN
    light.color = np.array(radiance, float) / max(np.mean(radiance), 1e-6)
    ob = bpy.data.objects.new(name, light)
    ob.location = origin
    ob.rotation_euler = _look_at_euler(origin, (0, 0, 0))  # back at the tube
    bpy.context.scene.collection.objects.link(ob)
    return ob


def _look_at_euler(origin, target):
    """Euler XYZ that aims a -Z-facing object (camera, area light) at a point.

    Blender's own vector maths does this; the hand-rolled basis that was here
    first aimed every softbox straight up and left the tube in the dark.
    """
    from mathutils import Vector

    direction = Vector(target) - Vector(origin)
    return tuple(direction.to_track_quat("-Z", "Y").to_euler())


def sensor():
    """The camera, framed exactly on the sprite's window.

    The angle is set, not the focal length: `lens` on a 36 mm sensor came out at
    a fraction of a millimetre, and Blender reads a sub-millimetre lens as the
    near-180-degree default, which put the whole tube in a couple of pixels. The
    angle is what the frame is, so the angle is what gets written.
    """
    cam = bpy.data.cameras.new("camera")
    cam.type = "PERSP"
    cam.sensor_fit = "HORIZONTAL"
    cam.sensor_width = 36.0
    cam.angle_x = 2.0 * math.atan((R.MM_W / 2.0) / CAM_DIST)
    ob = bpy.data.objects.new("camera", cam)
    ob.location = (0.0, 0.0, CAM_DIST)
    ob.rotation_euler = _look_at_euler((0.0, 0.0, CAM_DIST), (0.0, 0.0, 0.0))
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.scene.camera = ob
    return ob


def render_settings(samples, out_path):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "GPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = DENOISE
    sc.cycles.denoiser = "OPENIMAGEDENOISE"
    # OIDN on the CPU: the GPU denoiser allocates its own buffers next to the
    # render's, and at 1120x2304 that is what ran the card out of memory.
    sc.cycles.denoising_use_gpu = False
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.005
    sc.cycles.max_bounces = 8
    sc.cycles.transmission_bounces = 8
    sc.cycles.transparent_max_bounces = 8
    sc.cycles.use_light_tree = True
    sc.render.resolution_x = W
    sc.render.resolution_y = HH
    sc.render.resolution_percentage = 100
    # a soft filter is what turns a 0.17 mm wire into a grey smear when the
    # sprite is minified: the box filter is what Mitsuba renders with
    sc.cycles.pixel_filter_type = "BOX"
    sc.cycles.filter_width = 1.0
    sc.render.image_settings.file_format = "OPEN_EXR"
    sc.render.image_settings.color_mode = "RGB"
    sc.render.image_settings.color_depth = "32"
    sc.render.filepath = out_path
    sc.render.film_transparent = False


def world(radiance):
    """The room the tube stands in.

    Mitsuba's `constant` environment is a radiance and so is this, but the gain
    that makes the softboxes sane turns the background into a grey card: the login
    screen behind the sprite is nearly black, so the world stays nearly black too.
    """
    w = bpy.data.worlds.new("env")
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (
        *[c * WORLD_GAIN for c in radiance],
        1.0,
    )
    bg.inputs["Strength"].default_value = 1.0
    bpy.context.scene.world = w


def save_render(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


# ---- the passes -------------------------------------------------------------


def scene_geometry(lit=None):
    shapes, wires, glow = R.build(lit=LIT if lit is None else lit)
    return shapes, wires, glow


def build_common(room_radiance, with_lights, lit=None):
    shapes, wires, glow = scene_geometry(lit)
    glass = material_glass()
    # Base colour on a metal in Cycles IS its reflectance, and that is what the
    # eta/k pair in Mitsuba works out to: (1.5, 2.2) -> 0.46, (1.3, 1.6) -> 0.36.
    # The 0.02 that stood here first turned every part into a black silhouette.
    # The nine cathodes that are NOT lit have to disappear: in a real tube you see
    # the lit numeral and barely the dark wires of the others. At 0.46 reflectance
    # the studio lit all ten and the numeral drowned in a tangle of bright wire.
    cathode = principled(
        "cathode", (0.09, 0.085, 0.08), metallic=1.0, rough=0.70
    )
    anode = principled("anode", (0.36, 0.36, 0.36), metallic=1.0, rough=0.75)
    # The cyan coat, dim enough to stay cyan: at a full dielectric specular the
    # studio's reflection alone pushed the collar to a light grey.
    collar = principled(
        "collar", (0.055, 0.30, 0.42), metallic=0.0, rough=0.30, spec=0.06
    )
    mica = principled("mica", (0.82, 0.80, 0.72), metallic=0.0, rough=0.5)
    # The discharge, in Cycles' units. The emitter is a solid: its radiance IS the
    # number. Past ~8 the tone map turns the core into the pale cream of an
    # overdriven filament, and below ~2 it does not read as burning at all: 4.5
    # lands on the hot orange a nixie has, with the bloom carrying the rest.
    neon = material_emission("neon", (1.0, 0.455, 0.155), 18.0)

    mats = {
        "glass": glass,
        "stem": glass,
        "collar": collar,
        "mica20": mica,
        "mica-16": mica,
    }
    for name, (v, f) in shapes.items():
        assign(mesh(name, v, f), mats.get(name, mica))
    for i, (path, r) in enumerate(wires):
        v, f = R.sweep(path, r)
        assign(
            mesh("wire%d" % i, v, f), cathode if r <= R.RW + 1e-6 else anode
        )
    for i, (path, r) in enumerate(glow):
        v, f = R.sweep(path, r)
        assign(mesh("glow%d" % i, v, f), neon)

    world(room_radiance)
    if with_lights:
        # Large and soft, not small and bright: a lamp's wall of light. A small
        # source of the same power puts a mirror image of itself on the glass, and
        # those highlights came out several times brighter than the discharge — the
        # sprite's brightest pixels were the softboxes, not the numeral. Size does
        # not change a Blender area light's power, so the reflections soften and
        # the lighting stays where it was.
        for name, origin, size, rad in (
            ("key", (-120, 150, 210), (225, 325), (7.0, 7.3, 7.8)),
            ("fill", (190, 40, 120), (175, 275), (2.0, 2.1, 2.4)),
            ("rim", (-50, -30, -190), (150, 250), (1.1, 1.2, 1.4)),
        ):
            area_light(name, origin, size, rad)
    return shapes


def beauty(out, lit=None):
    clear()
    device()
    render_settings(SAMPLES, out + ".exr")
    build_common((0.012, 0.013, 0.017), with_lights=True, lit=lit)
    sensor()
    save_render(out + ".exr")
    print("beauty:", out + ".exr")


def digits(out, digits=range(10)):
    """One beauty pass per numeral: the clock reads a sprite per digit.

    The hardware is the same in all ten, so the metal and glass passes are shared;
    only the discharge moves to the numeral that is lit.
    """
    for d in digits:
        path = "%s_m%d" % (out, d)
        clear()
        device()
        render_settings(SAMPLES, path + ".exr")
        build_common((0.012, 0.013, 0.017), with_lights=True, lit=d)
        sensor()
        save_render(path + ".exr")
        exr_to_npy(path + ".exr", path + ".npy")
        print("digit", d, "->", path + ".npy")


def metal_mask(out):
    """Flat coverage of the hardware, glass hidden: the sprite's alpha.

    The parts are emissive, not white-lit: with a white environment the camera
    sees the environment through every gap and the coverage it measures is the
    room, not the metal.
    """
    clear()
    device()
    render_settings(64, out + "_hw.exr")
    shapes, wires, glow = scene_geometry()
    white = material_emission("coverage", (1.0, 1.0, 1.0), 1.0)
    for name, (v, f) in shapes.items():
        if name == "glass":
            continue
        assign(mesh(name, v, f), white)
    for i, (path, r) in enumerate(wires + [g for g in glow]):
        v, f = R.sweep(path, r)
        assign(mesh("m%d" % i, v, f), white)
    world((0.0, 0.0, 0.0))
    sensor()
    save_render(out + "_hw.exr")
    print("metal mask:", out + "_hw.exr")


def glass_layer(out, gain=0.30):
    """The envelope alone under the studio lights, for the additive layer."""
    clear()
    device()
    render_settings(GLASS_SAMPLES, out + "_glass.exr")
    shapes, _w, _g = scene_geometry()
    v, f = shapes["glass"]
    assign(mesh("glass", v, f), material_glass())
    world((0.012, 0.013, 0.017))
    for name, origin, size, rad in (
        ("key", (-120, 150, 210), (90, 130), (7.0, 7.3, 7.8)),
        ("fill", (190, 40, 120), (70, 110), (2.0, 2.1, 2.4)),
        ("rim", (-50, -30, -190), (60, 100), (1.1, 1.2, 1.4)),
    ):
        area_light(name, origin, size, tuple(c * gain for c in rad))
    sensor()
    save_render(out + "_glass.exr")
    print("glass:", out + "_glass.exr")


def exr_to_npy(path, npy_path):
    """An EXR from Cycles -> the float array the old passes fed to post.py.

    Three channels, top row first: Blender writes bottom-up and post.py reads the
    array with row 0 at the top of the tube, so the flip is not optional.
    """
    img = bpy.data.images.load(path)
    px = np.array(img.pixels[:], np.float32).reshape(
        img.size[1], img.size[0], 4
    )
    rgb = px[::-1, :, :3]
    np.save(npy_path, rgb)
    bpy.data.images.remove(img)
    print("saved", npy_path, rgb.shape)


def smoke(out, samples=24, scale=8):
    """A fast look at the whole scene: the frame, the lights, every material.

    Each full pass is hours at this size, and a wrong lens or a black world would
    only show up at the end of one. This renders the same scene small.
    """
    global W, HH
    W, HH = 1120 // scale, 2304 // scale
    clear()
    device()
    render_settings(samples, out + "_smoke.exr")
    build_common((0.012, 0.013, 0.017), with_lights=True)
    sensor()
    save_render(out + "_smoke.exr")
    exr_to_npy(out + "_smoke.exr", out + "_smoke.npy")
    print("smoke:", out + "_smoke.npy", (W, HH))


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    out = argv[0] if argv else "/tmp/ms/cycles"
    what = set(argv[1:]) or {"beauty", "metal", "glass"}
    if "smoke" in what:
        smoke(out)
        print("CYCLES_DONE", out)
        return
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    if "digits" in what:
        digits(out)
        print("CYCLES_DONE", out)
        return
    if "beauty" in what:
        beauty(out)
        exr_to_npy(out + ".exr", out + ".npy")
    if "metal" in what:
        metal_mask(out)
        exr_to_npy(out + "_hw.exr", out + "_hw.npy")
    if "glass" in what:
        glass_layer(out)
        exr_to_npy(out + "_glass.exr", out + "_glass.npy")
    print("CYCLES_DONE", out)


if __name__ == "__main__":
    main()

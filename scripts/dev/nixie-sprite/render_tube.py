#!/usr/bin/env python3
"""Physically based render of a nixie tube: glass envelope, anode cage, cathode
stack, crimped collar. Mitsuba 3, path tracing, studio softboxes — this is where
files/quickshell/greeter/assets/nixie-tube.png comes from.

    DRJIT_LIBLLVM_PATH=$(ls /nix/store/*-llvm-*-lib/lib/libLLVM.so.* | head -1) \
    uv run --with mitsuba --with numpy python scripts/dev/nixie-sprite/render_tube.py /tmp/beauty
    DRJIT_LIBLLVM_PATH=... uv run --with mitsuba --with numpy --with pillow \
      python scripts/dev/nixie-sprite/post.py /tmp/beauty \
      files/quickshell/greeter/assets/nixie-tube.png

The sprite's window is the shader's item (104 x 214 logical px at 0.2803 mm/px =
29.15 x 60.0 mm), so it lands 1:1 on the tube; the alpha is computed from the same
geometry rather than from the render, because the sprite is an overlay: its interior
has to stay transparent enough for the discharge behind it to read.

The render is 1120 x 2304 — sixteen texels per logical pixel. The tube carries a
0.17 mm anode wire and a 0.39 mm cathode numeral: at 560 x 1152 a wire was one
texel wide, the sprite's own filtering ate it, and the cage turned into a moire of
grey. The size is a power of two on purpose: Qt then mips it cleanly."""

import math
import os
import sys
import numpy as np
import mitsuba as mi

mi.set_variant("llvm_ad_rgb")

# ---- geometry, mm (the sprite's window is the shader's item: 104 x 214 logical px
#      at 0.2803 mm/px = 29.15 x 60.0 mm) ---------------------------------------
MM_W, MM_H = 29.15, 60.0
R, H, WALL = 9.25, 49.34, 1.1
RT, RW = 6.6, 0.22
BASE = 10.6
RB = 9.7
DIG_H, DIG_W = 21.0, 11.5
STACK_Z = np.linspace(-1.1, 1.1, 10)


def revolve(profile, segs=96, rfun=None):
    """Mesh of revolution from a closed 2D profile (radius, height, y up)."""
    verts, faces = [], []
    n = len(profile)
    for i, (r, y) in enumerate(profile):
        for k in range(segs):
            a = 2 * math.pi * k / segs
            rr = r if rfun is None else rfun(r, a, y, i)
            verts.append((rr * math.sin(a), y, rr * math.cos(a)))
    for i in range(n):
        i2 = (i + 1) % n
        for k in range(segs):
            k2 = (k + 1) % segs
            a = i * segs + k
            b = i * segs + k2
            c = i2 * segs + k2
            d = i2 * segs + k
            faces.append((a, b, c))
            faces.append((a, c, d))
    return verts, outward(verts, faces)


def outward(verts, faces):
    """Faces wound so the shell's normals face out.

    A revolve's winding depends on the direction its profile was written in, so
    half the parts (the collar, the stem) came out inside-out: Mitsuba culled
    their outward surface and they vanished from the render. The signed volume
    of the closed shell is what decides; it is invariant to the origin.
    """
    V = np.asarray(verts, float)
    F = np.asarray(faces, int)
    g = V[F].mean(axis=1)
    signed = np.einsum(
        "ij,ij->i",
        g,
        np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]]),
    ).sum()
    if signed < 0:
        F = F[:, ::-1]
        return [tuple(int(i) for i in f) for f in F]
    return [tuple(int(i) for i in f) for f in F]


def sweep(path, r, segs=10):
    """A tube along a 3D poly-line."""
    verts, faces = [], []
    P = np.asarray(path, float)
    for i, p in enumerate(P):
        if i == 0:
            t = P[1] - P[0]
        elif i == len(P) - 1:
            t = P[-1] - P[-2]
        else:
            t = P[i + 1] - P[i - 1]
        t = t / (np.linalg.norm(t) + 1e-9)
        up = (
            np.array([0.0, 0.0, 1.0])
            if abs(t[2]) < 0.9
            else np.array([1.0, 0.0, 0.0])
        )
        u = np.cross(t, up)
        u /= np.linalg.norm(u) + 1e-9
        v = np.cross(t, u)
        for k in range(segs):
            a = 2 * math.pi * k / segs
            verts.append(tuple(p + r * (math.cos(a) * u + math.sin(a) * v)))
    for i in range(len(P) - 1):
        for k in range(segs):
            k2 = (k + 1) % segs
            a = i * segs + k
            b = i * segs + k2
            c = (i + 1) * segs + k2
            d = (i + 1) * segs + k
            faces.append((a, b, c))
            faces.append((a, c, d))
    return verts, outward(verts, faces)


# ---- the numerals as poly-lines (the same skeletons the shader draws) ---------
def digit_paths(d):
    S = []  # segments
    A = []  # arcs (cx, cy, r, a0, a1)
    E = []  # ellipses (cx, cy, rx, ry, span)
    if d == 0:
        E.append((0, 0, 0.30, 0.88, 1.0))
    elif d == 1:
        S += [(0, -1.02, 0, 1.02), (-0.24, 0.55, 0, 1.02)]
    elif d == 2:
        A.append((0, 0.60, 0.31, 0.0, math.pi))
        S += [(0.31, 0.60, -0.32, -1.00), (-0.35, -1.02, 0.35, -1.02)]
    elif d == 3:
        A += [(0, 0.52, 0.52, -1.05, 2.53), (0, -0.52, 0.52, -2.09, 1.05)]
    elif d == 4:
        S += [
            (0.26, 0.95, -0.31, -0.10),
            (-0.31, -0.10, 0.32, -0.10),
            (0.26, 0.95, 0.26, -1.02),
        ]
    elif d == 5:
        S += [(-0.30, 1.02, 0.30, 1.02), (-0.30, 1.02, -0.27, 0.01)]
        A.append((0, -0.30, 0.41, -1.25, 2.28))
    elif d == 6:
        A.append((0, 0.50, 0.30, 0.0, math.pi))
        S.append((-0.30, 0.50, -0.30, -0.52))
        E.append((0, -0.52, 0.30, 0.44, 1.0))
    elif d == 7:
        S += [(-0.32, 1.02, 0.32, 1.02), (0.28, 1.02, -0.09, -1.02)]
    elif d == 8:
        E += [(0, 0.50, 0.27, 0.50, 1.0), (0, -0.50, 0.30, 0.50, 1.0)]
    else:
        E.append((0, 0.54, 0.30, 0.44, 1.0))
        S.append((0.30, 0.48, 0.28, -1.02))
    paths = []
    for ax, ay, bx, by in S:
        n = max(3, int(math.hypot(bx - ax, by - ay) * 8))
        paths.append(
            [
                (ax + (bx - ax) * t / n, ay + (by - ay) * t / n)
                for t in range(n + 1)
            ]
        )
    for cx, cy, r, a0, a1 in A:
        n = max(6, int(abs(a1 - a0) * r * 10))
        paths.append(
            [
                (
                    cx + r * math.cos(a0 + (a1 - a0) * t / n),
                    cy + r * math.sin(a0 + (a1 - a0) * t / n),
                )
                for t in range(n + 1)
            ]
        )
    for cx, cy, rx, ry, span in E:
        n = 96
        paths.append(
            [
                (
                    cx + rx * math.cos(2 * math.pi * t / n * span),
                    cy + ry * math.sin(2 * math.pi * t / n * span),
                )
                for t in range(n + 1)
            ]
        )
    return paths


def emit_ply(verts, faces, path):
    """Smooth-shaded PLY: the glass must not look faceted."""
    V = np.asarray(verts, np.float64)
    F = np.asarray(faces, np.int64)
    # the winding of a revolve() shell follows the direction of its profile, so
    # half of the parts came out inside-out: their outward normals faced the
    # core, Mitsuba culled them, and the collar simply vanished from the render.
    # A closed shell's signed volume settles the question for good.
    G = V[F].mean(axis=1)
    signed = np.einsum(
        "ij,ij->i",
        G,
        np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]]),
    ).sum()
    if signed < 0:
        F = F[:, ::-1]
        faces = [tuple(int(i) for i in f) for f in F]
    F = np.asarray(faces, np.int64)
    N = np.zeros_like(V)
    # normals, for the smooth shading
    for a, b, c in F:
        n = np.cross(V[b] - V[a], V[c] - V[a])
        N[a] += n
        N[b] += n
        N[c] += n
    ln = np.linalg.norm(N, axis=1)
    ln[ln == 0] = 1.0
    N = N / ln[:, None]
    with open(path, "w") as f:
        f.write("ply\nformat ascii 1.0\n")
        f.write(f"element vertex {len(V)}\n")
        f.write("property float x\nproperty float y\nproperty float z\n")
        f.write("property float nx\nproperty float ny\nproperty float nz\n")
        f.write(
            f"element face {len(F)}\nproperty list uchar int vertex_indices\n"
        )
        f.write("end_header\n")
        for v, n in zip(V, N):
            f.write(
                f"{v[0]:.6f} {v[1]:.6f} {v[2]:.6f} {n[0]:.4f} {n[1]:.4f} {n[2]:.4f}\n"
            )
        for a, b, c in F:
            f.write(f"3 {a} {b} {c}\n")
    return path


def build():
    shapes = {}
    # 1. the glass: a shell of revolution — outer wall, dome, inner wall, foot ring
    prof = [(R, -H / 2)]
    prof.append((R, H / 2 - R))
    for k in range(1, 33):
        a = math.pi / 2 * k / 32
        prof.append((R * math.cos(a), H / 2 - R + R * math.sin(a)))
    prof.append((R - WALL, H / 2 - R))
    prof.append((R - WALL, -H / 2))
    verts, faces = revolve(prof, 128)
    shapes["glass"] = (verts, faces)
    # 2. the anode cage: 24 vertical wires + 12 rings
    wires = []
    glow = []  # the neon threads: emissive, they are the discharge's core
    for k in range(16):
        a = 2 * math.pi * k / 16
        x, z = RT * math.sin(a), RT * math.cos(a)
        wires.append(
            ([(x, -H / 2 + BASE * 0.55, z), (x, H / 2 - 3.0, z)], 0.085)
        )
    for k in range(9):
        y = -H / 2 + BASE * 0.6 + (H - BASE * 0.6 - 4.5) * k / 8
        ring = [
            (
                RT * math.sin(2 * math.pi * t / 64),
                y,
                RT * math.cos(2 * math.pi * t / 64),
            )
            for t in range(65)
        ]
        wires.append((ring, 0.075))
    # 3. the cathode stack: ten numerals in a tungsten wire frame
    for i, zc in enumerate(STACK_Z):
        depth = (i - 4.5) * 0.05
        for path in digit_paths(i):
            pts = [
                (
                    x * DIG_W / 2.0 + depth,
                    y * DIG_H / 2.3 - 0.8 - depth * 0.8,
                    zc,
                )
                for (x, y) in path
            ]
            wires.append((pts, RW))
            # the discharge itself: the same glyph, drawn once more as a thin
            # emissive thread a little nearer the viewer. It is the glow's
            # source, and the only part of the tube that is not a solid.
            glow.append(
                (
                    [(x - 0.06, y - 0.06, z + 0.16) for (x, y, z) in pts],
                    RW * 0.5,
                )
            )
    # 4. the rods the stack hangs on
    for sx in (-1, 1):
        wires.append(
            (
                [
                    (sx * RT * 0.62, -H / 2 + BASE * 0.7, 0.0),
                    (sx * RT * 0.62, H / 2 - 3.5, 0.0),
                ],
                0.35,
            )
        )
    # 4b. the mica spacers: thin translucent discs the stack hangs from
    for y in (H / 2 - 4.6, -H / 2 + BASE * 0.62 + 1.2):
        disc = []
        for k in range(49):
            aa = 2 * math.pi * k / 48
            disc.append(
                (RT * 0.94 * math.cos(aa), y, RT * 0.94 * math.sin(aa))
            )
        verts, faces = [], []
        for k, (dx, dy, dz) in enumerate(disc):
            verts.append((dx, dy - 0.12, dz))
            verts.append((dx, dy + 0.12, dz))
        for k in range(48):
            a0, b0 = 2 * k, 2 * k + 1
            a1, b1 = 2 * k + 2, 2 * k + 3
            faces += [(a0, b0, b1), (a0, b1, a1)]
        shapes[f"mica{int(y)}"] = (verts, faces)
    # 4c. the stem: the pinched glass foot inside the collar
    stem = []
    for k in range(33):
        aa = -1.0 + 2.0 * k / 32
        r = 2.6 * math.sqrt(max(0.0, 1.0 - (aa * 0.9) ** 2))
        stem.append((r, -H / 2 + BASE * 0.05 + 2.2 * abs(aa), 0.0))
    sverts, sfaces = revolve(
        [(0.0, -H / 2 + BASE * 0.7), (2.5, -H / 2 + BASE * 0.55)]
        + [(r, y) for (r, y, _) in stem]
        + [(0.0, -H / 2 + BASE * 0.05)],
        48,
    )
    shapes["stem"] = (sverts, sfaces)
    # 5. the collar: crimped metal with flutes, closed at the bottom
    cprof = [
        (R, -H / 2),
        (RB, -H / 2 + 0.6),
        (RB, -MM_H / 2 + 0.4),
        (RB * 0.62, -MM_H / 2 + 0.1),
        (0.0, -MM_H / 2 + 0.1),
        (0.0, -H / 2),
    ]
    verts, faces = revolve(
        cprof,
        160,
        rfun=lambda r, a, y, i: (
            r * (1.0 + 0.022 * math.sin(14 * a)) if abs(r - RB) < 1e-6 else r
        ),
    )
    shapes["collar"] = (verts, faces)
    return shapes, wires, glow


def build_scene(
    only=None,
    flat=False,
    W=1120,
    HH=2304,
    spp=1024,
    out="/tmp/ms/beauty",
    glass=False,
    glass_gain=0.30,
):
    """Render the tube.


    only=None renders the full beauty pass; "hardware" and "glass" keep just that
    part of the scene, and with flat=True every material is a white diffuse lit by
    a uniform environment — those two passes are the coverage masks the sprite's
    alpha is assembled from (see masks.py).

    glass=True renders the envelope on its own, in a room dim enough that its
    reflections stay a thin additive layer over the numerals (see the glass).
    """
    shapes, wires, glow = build()
    scene = {}
    scene["type"] = "scene"
    # glass: a dielectric shell with a smooth surface
    scene["glass"] = {"type": "dielectric", "int_ior": 1.52, "ext_ior": 1.0}
    # tungsten cathodes and a nickel-plated anode: the metals of a real tube
    # explicit IORs: the pip wheel ships no material tables (Cr, Ni, W)
    scene["cathode"] = {
        "type": "roughconductor",
        "alpha": 0.32,
        "distribution": "ggx",
        "eta": {"type": "rgb", "value": [3.2, 3.0, 2.8]},
        "k": {"type": "rgb", "value": [2.9, 2.7, 2.5]},
    }
    # the cage is what is seen THROUGH the glass: matte, dark and thin. A glossy
    # conductor turns every wire into a bright line, and the numerals drown in the
    # lattice — the cage should read as a dim screen, not as chrome.
    scene["anode"] = {
        "type": "roughconductor",
        "alpha": 0.55,
        "distribution": "ggx",
        "eta": {"type": "rgb", "value": [1.4, 1.35, 1.30]},
        "k": {"type": "rgb", "value": [2.2, 2.1, 2.0]},
    }

    # the neon threads: thin emissive tubes laid over the glyphs — the tube's
    # discharge, and the only light source inside the glass
    scene["neon"] = {
        "type": "diffuse",
        "reflectance": {"type": "rgb", "value": [0.02, 0.02, 0.02]},
    }
    scene["neonEmitter"] = {
        "type": "area",
        "radiance": {"type": "rgb", "value": [16.0, 7.5, 2.6]},
    }
    # the collar is painted metal: a plain dielectric cyan coat over it, glossy
    # the collar's cyan: dim enough that the tone reads as paint and not as a
    # blown-out white block. A bright coat under this studio turns cream.
    scene["collarM"] = {
        "type": "roughplastic",
        "distribution": "ggx",
        "alpha": 0.14,
        "diffuse_reflectance": {"type": "rgb", "value": [0.10, 0.52, 0.68]},
        "specular_reflectance": {"type": "rgb", "value": [0.22, 0.26, 0.28]},
    }
    os.makedirs("/tmp/ms/mesh", exist_ok=True)
    if glass:
        # the envelope alone: the metal would occlude it and its own highlights
        # are a separate layer of the sprite
        keep = {"glass"}
    else:
        keep = set(shapes)

    for name, (v, f) in shapes.items():
        if name not in keep:
            continue
        ply = emit_ply(v, f, f"/tmp/ms/mesh/{name}.ply")
        if name == "glass":
            bsdf = {"type": "dielectric", "int_ior": 1.52, "ext_ior": 1.0}
        elif name == "collar":
            bsdf = scene["collarM"]

        elif name == "stem":
            bsdf = {"type": "dielectric", "int_ior": 1.52, "ext_ior": 1.0}
        else:  # the mica spacers
            bsdf = {
                "type": "diffuse",
                "reflectance": {"type": "rgb", "value": [0.82, 0.80, 0.72]},
            }
        scene[name] = {
            "type": "ply",
            "filename": ply,
            "face_normals": False,
            "bsdf": bsdf,
        }
    for i, (path, r) in enumerate([] if glass else wires):
        v, f = sweep(path, r)
        ply = emit_ply(v, f, f"/tmp/ms/mesh/wire{i}.ply")
        mat = "cathode" if r <= RW + 1e-6 else "anode"
        scene[f"wire{i}"] = {
            "type": "ply",
            "filename": ply,
            "face_normals": False,
            "bsdf": scene[mat],
        }
    # the discharge: the same glyphs again, as emissive threads
    for i, (path, r) in enumerate([] if glass else glow):
        v, f = sweep(path, r)
        ply = emit_ply(v, f, f"/tmp/ms/mesh/glow{i}.ply")
        scene[f"glow{i}"] = {
            "type": "ply",
            "filename": ply,
            "face_normals": False,
            "bsdf": scene["neon"],
            "emitter": scene["neonEmitter"],
        }
    # camera: a long lens, effectively orthographic over the window
    dist = 300.0
    fov = 2 * math.degrees(math.atan((MM_W / 2) / dist))
    scene["sensor"] = {
        "type": "perspective",
        "fov": fov,
        "fov_axis": "x",
        "to_world": mi.ScalarTransform4f.look_at(
            origin=[0, 0, dist], target=[0, 0, 0], up=[0, 1, 0]
        ),
        "film": {
            "type": "hdrfilm",
            "width": W,
            "height": HH,
            "pixel_format": "rgb",
            "component_format": "float32",
            "rfilter": {"type": "box"},
            "sample_border": True,
        },
        "sampler": {"type": "independent", "sample_count": spp},
    }

    # studio: a big soft key up-left, a fill on the right, a rim behind; a dim ambient
    def softbox(origin, target, size, radiance):
        T = mi.ScalarTransform4f.look_at(
            origin=origin, target=target, up=[0, 1, 0]
        ) @ mi.ScalarTransform4f.scale([size[0], size[1], 1.0])
        return {
            "type": "rectangle",
            "to_world": T,
            "emitter": {
                "type": "area",
                "radiance": {"type": "rgb", "value": radiance},
            },
        }

    # the glass pass wants a room, not a studio: its highlights read as the
    # envelope's own reflections only while they stay a thin layer over the digits
    gain = glass_gain if glass else 1.0

    scene["key"] = softbox(
        [-120, 150, 210],
        [0, 0, 0],
        [90, 130],
        [7.0 * gain, 7.3 * gain, 7.8 * gain],
    )
    scene["fill"] = softbox(
        [190, 40, 120],
        [0, 0, 0],
        [70, 110],
        [2.0 * gain, 2.1 * gain, 2.4 * gain],
    )
    scene["rim"] = softbox(
        [-50, -30, -190],
        [0, 0, 0],
        [60, 100],
        [1.1 * gain, 1.2 * gain, 1.4 * gain],
    )
    scene["env"] = {
        "type": "constant",
        "radiance": {"type": "rgb", "value": [0.012, 0.013, 0.017]},
    }
    scene["integrator"] = {
        "type": "path",
        "max_depth": 10,
        "rr_depth": 5,
        "hide_emitters": True,
    }
    sc = mi.load_dict(scene)
    img = mi.render(sc, spp=spp, seed=7)
    a = np.array(img)
    np.save("/tmp/ms/glass.npy" if glass else out + ".npy", a)
    print(
        "rendered",
        a.shape,
        "exposure mid:",
        float(np.median(a[a.shape[0] // 2])),
    )
    return a


def main(out="/tmp/ms/beauty", glass=False):
    build_scene(out=out, glass=glass)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    main(
        args[0] if args else "/tmp/ms/beauty",
        glass="--glass" in sys.argv,
    )
if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "/tmp/ms/beauty")

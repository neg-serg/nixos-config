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
has to stay transparent enough for the discharge behind it to read."""

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
RT, RW = 6.6, 0.30
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
    return verts, faces


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
    return verts, faces


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
    N = np.zeros_like(V)
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
    for k in range(24):
        a = 2 * math.pi * k / 24
        x, z = RT * math.sin(a), RT * math.cos(a)
        wires.append(
            ([(x, -H / 2 + BASE * 0.55, z), (x, H / 2 - 3.0, z)], 0.22)
        )
    for k in range(12):
        y = -H / 2 + BASE * 0.6 + (H - BASE * 0.6 - 4.5) * k / 11
        ring = [
            (
                RT * math.sin(2 * math.pi * t / 64),
                y,
                RT * math.cos(2 * math.pi * t / 64),
            )
            for t in range(65)
        ]
        wires.append((ring, 0.20))
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
    return shapes, wires


def main(out, spp=192, W=560, HH=1152):
    shapes, wires = build()
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
    scene["anode"] = {
        "type": "roughconductor",
        "alpha": 0.22,
        "distribution": "ggx",
        "eta": {"type": "rgb", "value": [1.9, 1.8, 1.7]},
        "k": {"type": "rgb", "value": [3.4, 3.2, 3.0]},
    }
    scene["collarM"] = {
        "type": "roughconductor",
        "alpha": 0.14,
        "distribution": "ggx",
        "eta": {"type": "rgb", "value": [2.2, 2.1, 2.0]},
        "k": {"type": "rgb", "value": [3.3, 3.1, 2.9]},
    }
    os.makedirs("/tmp/ms/mesh", exist_ok=True)
    for name, (v, f) in shapes.items():
        ply = emit_ply(v, f, f"/tmp/ms/mesh/{name}.ply")
        bsdf = {"glass": scene["glass"], "collar": scene["collarM"]}[name]
        scene[name] = {
            "type": "ply",
            "filename": ply,
            "face_normals": False,
            "bsdf": bsdf,
        }
    for i, (path, r) in enumerate(wires):
        v, f = sweep(path, r)
        ply = emit_ply(v, f, f"/tmp/ms/mesh/wire{i}.ply")
        mat = "cathode" if r <= RW + 1e-6 else "anode"
        scene[f"wire{i}"] = {
            "type": "ply",
            "filename": ply,
            "face_normals": False,
            "bsdf": scene[mat],
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

    scene["key"] = softbox(
        [-120, 150, 210], [0, 0, 0], [90, 130], [7.0, 7.3, 7.8]
    )
    scene["fill"] = softbox(
        [190, 40, 120], [0, 0, 0], [70, 110], [2.0, 2.1, 2.4]
    )
    scene["rim"] = softbox(
        [-50, -30, -190], [0, 0, 0], [60, 100], [1.1, 1.2, 1.4]
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
    np.save(out + ".npy", a)
    print(
        "rendered",
        a.shape,
        "exposure mid:",
        float(np.median(a[a.shape[0] // 2])),
    )
    return a


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "/tmp/ms/beauty")

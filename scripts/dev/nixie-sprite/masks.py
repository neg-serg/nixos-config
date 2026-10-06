#!/usr/bin/env python3
"""Coverage masks for the tube sprite: what is metal and what is glass, rendered
flat and separately, so the sprite's alpha can be per material instead of per
brightness (which turned the glass's own reflections into metal)."""

import sys

import numpy as np

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import mitsuba as mi
import render_tube as R

mi.set_variant("llvm_ad_rgb")


def coverage(only, out, spp=64, W=560, HH=1152):
    shapes, wires = R.build()
    white = {
        "type": "diffuse",
        "reflectance": {"type": "rgb", "value": [1.0, 1.0, 1.0]},
    }
    scene = {
        "type": "scene",
        "env": {
            "type": "constant",
            "radiance": {"type": "rgb", "value": [1.0, 1.0, 1.0]},
        },
    }
    for name, (v, f) in shapes.items():
        if only == "hardware" and name == "glass":
            continue
        ply = R.emit_ply(v, f, f"/tmp/ms/mesh/mask_{name}.ply")
        scene[name] = {
            "type": "ply",
            "filename": ply,
            "face_normals": False,
            "bsdf": white,
        }
    for i, (path, r) in enumerate(wires):
        if only == "glass":
            continue
        v, f = R.sweep(path, r)
        ply = R.emit_ply(v, f, f"/tmp/ms/mesh/mask_wire{i}.ply")
        scene[f"wire{i}"] = {
            "type": "ply",
            "filename": ply,
            "face_normals": False,
            "bsdf": white,
        }
    scene["sensor"] = {
        "type": "perspective",
        "fov": 2 * np.degrees(np.arctan((R.MM_W / 2) / 300.0)),
        "fov_axis": "x",
        "to_world": mi.ScalarTransform4f.look_at(
            origin=[0, 0, 300], target=[0, 0, 0], up=[0, 1, 0]
        ),
        "film": {
            "type": "hdrfilm",
            "width": W,
            "height": HH,
            "pixel_format": "rgb",
            "component_format": "float32",
            "rfilter": {"type": "box"},
        },
        "sampler": {"type": "independent", "sample_count": spp},
    }
    scene["integrator"] = {
        "type": "path",
        "max_depth": 3,
        "hide_emitters": True,
    }
    img = np.array(mi.render(mi.load_dict(scene), spp=spp, seed=3))
    m = np.clip(img.mean(axis=2), 0, 1)
    np.save(out, m)
    print(only, "coverage:", out, "mean %.3f max %.2f" % (m.mean(), m.max()))


if __name__ == "__main__":
    coverage("hardware", sys.argv[1] + "_hw.npy")
    coverage("glass", sys.argv[1] + "_glass.npy")

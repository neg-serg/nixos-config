#!/usr/bin/env python3
"""The glass alone, lit: the light it adds to the screen (its reflections, its rim).
The sprite overlays it additively — a reflection adds light, it does not hide what
is behind it, and treating it as opacity is what made the tube read as metal.
"""

import sys

import numpy as np

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import mitsuba as mi
import render_tube as R

mi.set_variant("llvm_ad_rgb")


def main(out, spp=512):
    shapes, _ = R.build()
    scene = {
        "type": "scene",
        "env": {
            "type": "constant",
            "radiance": {"type": "rgb", "value": [0.012, 0.013, 0.017]},
        },
        "glass": {"type": "dielectric", "int_ior": 1.52, "ext_ior": 1.0},
    }
    v, f = shapes["glass"]
    ply = R.emit_ply(v, f, "/tmp/ms/mesh/glassonly.ply")
    scene["glassShape"] = {
        "type": "ply",
        "filename": ply,
        "face_normals": False,
        "bsdf": scene["glass"],
    }

    def softbox(origin, target, size, rad):
        T = mi.ScalarTransform4f.look_at(
            origin=origin, target=target, up=[0, 1, 0]
        ) @ mi.ScalarTransform4f.scale([size[0], size[1], 1.0])
        return {
            "type": "rectangle",
            "to_world": T,
            "emitter": {
                "type": "area",
                "radiance": {"type": "rgb", "value": rad},
            },
        }

    scene["key"] = softbox(
        [-120, 150, 210], [0, 0, 0], [90, 130], [7.0, 7.3, 7.8]
    )
    scene["fill"] = softbox(
        [190, 40, 120], [0, 0, 0], [70, 110], [2.0, 2.1, 2.4]
    )
    scene["rim"] = softbox(
        [-60, -40, -170], [0, 0, 0], [80, 120], [1.8, 1.9, 2.2]
    )
    scene["sensor"] = {
        "type": "perspective",
        "fov": 2 * np.degrees(np.arctan((R.MM_W / 2) / 300.0)),
        "fov_axis": "x",
        "to_world": mi.ScalarTransform4f.look_at(
            origin=[0, 0, 300], target=[0, 0, 0], up=[0, 1, 0]
        ),
        "film": {
            "type": "hdrfilm",
            "width": 560,
            "height": 1152,
            "pixel_format": "rgb",
            "component_format": "float32",
            "rfilter": {"type": "box"},
        },
        "sampler": {"type": "multijitter", "sample_count": spp},
    }
    scene["integrator"] = {
        "type": "path",
        "max_depth": 8,
        "hide_emitters": True,
    }
    img = np.array(mi.render(mi.load_dict(scene), spp=spp, seed=5))
    np.save(out, img)
    print(
        "glass pass:",
        out,
        img.shape,
        "mean %.3f max %.2f" % (img.mean(), img.max()),
    )


if __name__ == "__main__":
    main(sys.argv[1])

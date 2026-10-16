#!/usr/bin/env python3
"""Keep LD_LIBRARY_PATH in the PTC worker environment.

The PTC runtime tombstones every ambient env key except
STARTUP_ENVIRONMENT_NAMES, LD_LIBRARY_PATH included; the official Node
build has no RPATH (nodejs-official.nix) and needs it on the loader
path, so worker spawns failed with exit 127 before booting.
"""

import sys
from functools import partial

from patchlib import patch_file

ROOT = sys.argv[1]  # .../node_modules/@deepseek-ai

patch = partial(patch_file, ROOT, prog="patch-ptc-env", announce=True)

PTC = "dsh-ptc-runtime-node/lib/index.js"
patch(
    PTC,
    [
        # Every other ambient key still gets a tombstone: program code
        # must see an empty process.env (cleared again after boot).
        (
            'const env = Object.fromEntries(Object.keys(process.env).filter((key) => !STARTUP_ENVIRONMENT_NAMES.has(key.toUpperCase()) && key.toUpperCase() !== "ELECTRON_RUN_AS_NODE").map((key) => [key, void 0]));',
            'const env = Object.fromEntries(Object.keys(process.env).filter((key) => !STARTUP_ENVIRONMENT_NAMES.has(key.toUpperCase()) && key.toUpperCase() !== "ELECTRON_RUN_AS_NODE").map((key) => [key, key.toUpperCase() === "LD_LIBRARY_PATH" ? process.env[key] : void 0]));',
            1,
        ),
    ],
)

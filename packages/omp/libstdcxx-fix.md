# libstdc++.so.6 Fix for onnxruntime-node in omp

## Root Cause

`onnxruntime-node` (v1.24.3, bundled under `@huggingface/transformers`) loads a platform-specific native addon. On Linux x64:

```
node_modules/@huggingface/transformers/node_modules/onnxruntime-node/
  bin/napi-v6/linux/x64/
    libonnxruntime.so.1      ← ELF shared library
    onnxruntime_binding.node ← Node.js native addon
```

`binding.js` line 10 does `require("../bin/napi-v6/${platform}/${arch}/onnxruntime_binding.node")`, which triggers `dlopen` of `onnxruntime_binding.node`, which transitively loads `libonnxruntime.so.1`.

**`libonnxruntime.so.1` NEEDS `libstdc++.so.6`** — it links against:

| Library | Status |
|---|---|
| `libstdc++.so.6` | **not found** ← FAILS |
| `libgcc_s.so.1` | found (from xgcc-15.2.0-libgcc) |
| `libdl.so.2`, `librt.so.1`, `libpthread.so.0`, `libm.so.6`, `libc.so.6`, `ld-linux-x86-64.so.2` | found (from glibc) |

The current `makeWrapper` wraps the binary with **no `LD_LIBRARY_PATH`** at all:

```bash
makeWrapper ${lib.getExe bun} $out/bin/omp \
  --add-flags "run $out/share/omp/dist/cli.js"
```

So when `process.dlopen` tries to resolve `onnxruntime_binding.node` → `libonnxruntime.so.1`, the dynamic linker can't find `libstdc++.so.6` because it's not in the standard library search path (Nix doesn't use `/usr/lib`).

---

## Proposed Fixes

### Fix 1 (Recommended): Add `libstdc++` via `--prefix LD_LIBRARY_PATH`

**Pros**: Idiomatic Nix pattern (used elsewhere in repo: `packages/wl/default.nix` for `vulkan-loader`); minimal change; composable with other libs if needed later.

**Cons**: Slightly more verbose than buildInputs-based approach; must list every needed lib explicitly.

**Change** (`/etc/nixos/packages/omp/default.nix`):

```diff
  nativeBuildInputs = [ makeWrapper ];
+  buildInputs = [ stdenv.cc.cc.lib ];

  postPatch = ''
    # Inject package-lock.json (not bundled in the npm tarball)
    cp ${./package-lock.json} package-lock.json
    ...
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/omp $out/bin
    cp -r . $out/share/omp/
    # Use bun as runtime (omp uses bun-specific APIs)
    makeWrapper ${lib.getExe bun} $out/bin/omp \
-      --add-flags "run $out/share/omp/dist/cli.js"
+      --add-flags "run $out/share/omp/dist/cli.js" \
+      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}
    runHook postInstall
  '';
```

---

### Fix 2: Use `--prefix LD_LIBRARY_PATH` with `libstdcxx5`

**Pros**: Explicit package name (`libstdcxx5` alias for `gcc.cc.lib`); same mechanism.

**Cons**: `libstdcxx5` is just an alias, no semantic difference; other approaches are more idiomatic.

**Change**:

Import `libstdcxx5` from nixpkgs and use:

```nix
# At top:
, libstdcxx5
# In installPhase:
makeWrapper ... \
  --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ libstdcxx5 ]}
```

---

### Fix 3: Use `NIX_LDFLAGS` auto-propagated via `buildInputs`

**Pros**: `buildInputs` are propagated to the build environment's `NIX_LDFLAGS` automatically; no manual `--prefix` needed if we somehow make the native addon aware.

**Cons**: `NIX_LDFLAGS` only affects the build link step, not the runtime `LD_LIBRARY_PATH` of the wrapper script. Node.js `process.dlopen` does not read `NIX_LDFLAGS`. **This won't work** unless combined with Fix 1 anyway.

---

## Verification

After applying the fix, rebuilding and running `omp`, the onnxruntime-node native addon should load without the `libstdc++.so.6` error.

To verify the specific ELF dependency is satisfied:

```bash
nix build '.#omp' && ldd result/share/omp/node_modules/@huggingface/transformers/node_modules/onnxruntime-node/bin/napi-v6/linux/x64/libonnxruntime.so.1 | grep stdc++
```

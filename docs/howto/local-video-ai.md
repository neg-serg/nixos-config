# Local video-AI stack (odin, ComfyUI)

Image/video/3D generation through ComfyUI on RX 9070 XT (gfx1201).

## Launch

`/zero/ai/video/comfyui/start-comfyui.sh` — launcher:

- **HSA_OVERRIDE_GFX_VERSION=12.0.0 REQUIRED** (pip-torch does not know gfx1201; an empty value =
  "No HIP GPUs"). Do not remove.
- LD_LIBRARY_PATH: nix libs + libglvnd + e2fsprogs (needed by pymeshlab/Hunyuan3D).
- `--novram`: works around the known Wan 2.2 slowdown on ROCm.
- UI: http://127.0.0.1:8188

## Models (/zero/ai/video/models + comfyui/models/diffusion_models)

| Model                         | Status                                                                         |
| ----------------------------- | ------------------------------------------------------------------------------ |
| LTX 2.3 (63G)                 | ✅ verified by rendering (frames in comfyui-output)                            |
| Wan 2.1/2.2 (all)             | ❌ removed (2026-08-20, ~75GB) — not needed; user decided                      |
| HunyuanVideo 1.5              | ✅ files present                                                               |
| Hunyuan3D-2.0                 | ✅ fixed (pymeshlab + libglvnd/e2fsprogs in the launcher), workflow not run    |
| Qwen-Image, SDXL, FLUX (image)| ✅ files present                                                               |
| triposr (3D from photo)       | ✅ verified (glb in comfyui-output)                                            |

## Limitations

- **VRAM**: the desktop (Hyprland+Vivaldi) holds ~13GB of 17GB — full LTX 22B renders do not fit. To
  render: free the GPU or lower the resolution/frame count.
- Parallel agents/sessions do not rebuild the system — only `nh os switch`.

## Key nodes

- Workflows: /zero/ai/video/workflows/ (UI format; conversion to API — see /tmp/wan-final3.py as a
  template, but better to author the API format directly).
- custom_nodes: WanVideoWrapper (GGUF), VideoHelperSuite, Hunyuan3DWrapper, LTXVideo, GGUF,
  IPAdapter.
- Output: /zero/ai/video/comfyui/output/ and comfyui-output/.

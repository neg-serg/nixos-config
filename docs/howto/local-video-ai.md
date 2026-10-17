# Local video-AI stack (trantor, ComfyUI)

Image/video/3D generation through ComfyUI on RX 9070 XT (gfx1201).

## Launch

`~/.local/bin/comfyui` (preferred — it builds `LD_LIBRARY_PATH` dynamically) or
`/zero/ai/video/comfyui/start-comfyui.sh` (pinned store paths) — both start the same server:

- **HSA_OVERRIDE_GFX_VERSION=12.0.0 REQUIRED** (pip-torch does not know gfx1201; an empty value =
  "No HIP GPUs"). Do not remove.
- LD_LIBRARY_PATH: nix libs + libglvnd + e2fsprogs (needed by pymeshlab/Hunyuan3D).
- `--novram`: works around the known Wan 2.2 slowdown on ROCm.
- UI: http://127.0.0.1:8188

`venv/bin/python` points at the uv-managed CPython 3.14.6
(`~/.local/share/uv/python/cpython-3.14.6-linux-x86_64-gnu/bin`): the Nix store interpreter the venv
was built from was garbage-collected, so the venv was relinked on 2026-10-16 (site-packages and the
ROCm wheels were intact). A shell whose sandbox blocks `/dev/kfd` reports
`torch.cuda.is_available() == False` — start the server from a session terminal or a
`systemd-run --user` unit.

## Models (/zero/ai/video/models + comfyui/models/diffusion_models)

| Model                          | Status                                                                      |
| ------------------------------ | --------------------------------------------------------------------------- |
| LTX 2.3 (63G)                  | ✅ verified by rendering (frames in comfyui-output)                         |
| Wan 2.1/2.2 (all)              | ❌ removed (2026-08-20, ~75GB) — not needed; user decided                   |
| HunyuanVideo 1.5               | ✅ files present                                                            |
| Hunyuan3D-2.0                  | ✅ fixed (pymeshlab + libglvnd/e2fsprogs in the launcher), workflow not run |
| Qwen-Image, SDXL, FLUX (image) | ✅ files present                                                            |
| triposr (3D from photo)        | ✅ verified (glb in comfyui-output)                                         |

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

## Animated wallpaper (still image → seamless loop)

HunyuanVideo 1.5 480p I2V cfg-distilled is the model that fits the 16 GB card (8.3 GB): LTX 2.3 22B
OOMs even at 512x320x97, and the Wan GGUFs were removed (the `Wan2.2-*` symlinks in
`comfyui/models/diffusion_models` are broken).

Graph that keeps the start image faithful:

- `DualCLIPLoader` with type `hunyuan_video_15` (Qwen2.5-VL text encoder) and `CLIPTextEncode` for
  positive/negative;
- `CLIPVisionLoader` + `CLIPVisionEncode` (SigLIP) feeding the optional `clip_vision_output` of
  `HunyuanVideo15ImageToVideo` — without it the scene drifts into a different waterfall by mid-clip,
  with it the start image holds;
- `KSampler` (euler, simple), 8 steps, CFG 1.0, 768x480, 97 frames (4 s @ 24 fps).

A render costs ~16 min on the RX 9070 XT (61 s/step sampling plus CPU VAE decode with `--cpu-vae`;
drop `--cpu-vae` to decode on the GPU when VRAM is free). Knobs: 896x560 or 1024x640 instead of
768x480, 49 frames for a 2 s clip, prompt wording ("static camera", "no scene change").

The frames are cross-faded (tail into head, 1 s) into a seamless MP4, and the `wallpaper-video` user
service (`modules/user/session/wallpaper-video.nix`) plays it with `mpv --loop-file`; hyprwinwrap
pins the window behind the desktop via the declaration in `files/gui/hypr/hyprwinwrap.lua`.

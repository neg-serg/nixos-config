# Локальный видео-ИИ стек (odin, ComfyUI)

Генерация изображений/видео/3D через ComfyUI на RX 9070 XT (gfx1201).

## Запуск

`/zero/ai/video/comfyui/start-comfyui.sh` — лаунчер:

- **HSA_OVERRIDE_GFX_VERSION=12.0.0 ОБЯЗАТЕЛЕН** (pip-torch не знает gfx1201; пустое значение = «No
  HIP GPUs»). Не удалять.
- LD_LIBRARY_PATH: nix-либы + libglvnd + e2fsprogs (нужны pymeshlab/Hunyuan3D).
- `--novram`: обход известного торможения Wan 2.2 на ROCm.
- UI: http://127.0.0.1:8188

## Модели (/zero/ai/video/models + comfyui/models/diffusion_models)

| Модель                             | Статус                                                                         |
| ---------------------------------- | ------------------------------------------------------------------------------ |
| LTX 2.3 (63G)                      | ✅ проверен рендером (кадры в comfyui-output)                                  |
| Wan 2.2 i2v 14B (GGUF Q5) + camera | ✅ файлы есть, рендер не прогонялся (VRAM)                                     |
| Wan 2.2 t2v 14B (GGUF Q5)          | ✅ докачан (2026-08-20), воркфлоу не собран                                    |
| Wan 2.1 t2v 14B                    | ✅ файлы есть                                                                  |
| HunyuanVideo 1.5                   | ✅ файлы есть                                                                  |
| Hunyuan3D-2.0                      | ✅ починен (pymeshlab + libglvnd/e2fsprogs в лаунчере), воркфлоу не прогонялся |
| Qwen-Image, SDXL, FLUX (image)     | ✅ файлы есть                                                                  |
| triposr (3D из фото)               | ✅ проверен (glb в comfyui-output)                                             |

## Ограничения

- **VRAM**: десктоп (Hyprland+Vivaldi) держит ~13GB из 17GB — полные рендеры Wan/LTX 14B не влезают.
  Для рендера: освободи GPU или уменьши разрешение/кадры.
- Воркфлоу wan22-i2v (wan22-i2v-a14b-example.json) валидируется; lora lightx2v опциональна (сейчас —
  4step-лоры в models/loras).
- Параллельные агенты/сессии не пересобирают систему — только `nh os switch`.

## Ключевые узлы

- Воркфлоу: /zero/ai/video/workflows/ (UI-формат, конвертация в API — см. /tmp/wan-final3.py шаблон,
  но лучше строить API-формат сразу).
- custom_nodes: WanVideoWrapper (GGUF), VideoHelperSuite, Hunyuan3DWrapper, LTXVideo, GGUF,
  IPAdapter.
- Выход: /zero/ai/video/comfyui/output/ и comfyui-output/.

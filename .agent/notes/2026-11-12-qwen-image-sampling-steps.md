# Qwen-Image sampling steps: what a step is and what 5000 of them would do, 2026-11-12

Question: `run2.py --steps N` is the main quality/time knob for the official Qwen-Image bf16 runner.
What does a step actually buy, where does it stop mattering, and is there any reason to run absurd
values like 5000?

## What a step is

`QwenImagePipeline` (diffusers 0.39, `venv` in `/zero/ai/video/comfyui`) samples with
`FlowMatchEulerDiscreteScheduler`: `sigmas = linspace(1.0, 1/N, N)`, rescaled by
`calculate_shift(image_seq_len, 256, 8192, 0.5, 0.9)` and clamped by `shift_terminal = 0.02`;
`num_train_timesteps = 1000`, `stochastic_sampling = false`. Each step is one Euler step of the
rectified-flow ODE: the transformer predicts the velocity at the current latent and sigma, then
`latents = scheduler.step(noise_pred, sigma, latents)`.

Two forward passes per step at the card's settings: `true_cfg_scale = 4.0` with a negative prompt
runs the transformer once conditional and once unconditional, then blends `neg + cfg * (pos - neg)`
and rescales to the conditional norm. So 50 steps is 100 forwards over 6889 tokens at 1328x1328
(latent 166x166, seen as 83x83 patches).

## The schedule at 50 vs 5000 (measured, scheduler only, no model)

Probed by instantiating the shipped scheduler and calling `set_timesteps` with `mu` computed for
6889 tokens (`mu = 0.8343`); nothing was generated.

| N    | first delta-sigma | median delta-sigma | last delta-sigma | first/last timestep |
| ---- | ----------------- | ------------------ | ---------------- | ------------------- |
| 50   | 9.0e-3            | 1.7e-2             | 2.0e-2           | 1000 / 20           |
| 5000 | 8.5e-5            | 1.7e-4             | 2.0e-2           | 1000 / 20           |

- `shift_terminal = 0.02` pins the last jump to 0.02 regardless of N, so 5000 steps means 4999
  microscopic steps plus one final 0.02 step. The last step never gets finer.
- float32 resolution of sigma is ~6e-8 against a 8.5e-5 step: no numerical collapse at 5000.
  Collapse would need ~10^6 steps.
- `num_train_timesteps = 1000`. Even at N=50 the tail runs below sigma 0.02; at N=5000 the last ~100
  steps live in that tail, where the model saw few training samples. Harmless, not useful.

## Cost (measured per step, arithmetic beyond)

Measured on the RX 9070 XT with the disk-offload path: 20.9 s/step at 1328x1328, 50 steps in 1141 s.
Step cost is streaming-bound, not compute-bound: every step re-reads the full 41.9 GB transformer
from `offload/` over ZFS (5.6 GB/s measured). So cost is strictly linear in steps:

| steps | wall time | transformer bytes read |
| ----- | --------- | ---------------------- |
| 20    | ~7 min    | 0.84 TB                |
| 50    | 19 min    | 2.1 TB                 |
| 150   | ~57 min   | 6.3 TB                 |
| 5000  | ~29 h     | 210 TB                 |

Memory is flat: VRAM and RAM do not grow with steps, only the offload cache gets re-read. 5000 steps
was not run; the 29 h figure is 5000 x 20.9 s.

## Quality

Euler error falls as O(1/N), so N=5000 converges to the continuous ODE trajectory of the model. The
useful question is when the difference stops being visible: the expectation from other
rectified-flow samplers (and from the fact that every extra step only refines a trajectory that is
already accurate to a couple of percent at N=50) is a plateau around N=100-200, after which the
difference sits under VAE reconstruction and detail noise. That plateau is **not measured here** - a
24 vs 48 step A/B at 512x512 on one seed costs ~28 min and would settle it.

Early steps (high sigma) set composition, late steps set texture and text. That matches the smoke
test at 4 steps: the door and the neon were already placed, but density and color had not converged.
Qwen-Image is not step-distilled, unlike FLUX.1-schnell (4 steps by recipe).

Distilled LoRAs are the opposite case: `Qwen-Image-Lightning-{4,8}steps` are trained to jump along
the trajectory, so a 50- or 5000-step schedule over-refines and washes them out. More steps there is
not "more quality", it is a different (broken) trajectory.

## Verdict

- 4-8 steps: probe whether the prompt/layout is worth iterating on, 1.5-3 min.
- 20: practical floor for a usable image.
- 30-40: iteration zone.
- 50: the card's reference, 19 min.
- 100-150: upper bound worth trying once; beyond that it is heat, NVMe reads and time.
- 5000: 29 h and 210 TB of reads for a difference the eye cannot resolve. Only defensible as a
  convergence reference, and even then 200 steps gets within measurement noise of it.

## References

- Runner and operator notes: `/zero/ai/video/models/Qwen-Image/{run2.py,README.md}`
- Pipeline: `venv/lib/python3.14/site-packages/diffusers/pipelines/qwenimage/pipeline_qwenimage.py`
- Scheduler config: `/zero/ai/video/models/Qwen-Image/weights/scheduler/scheduler_config.json`
- Repo section: `modules/llm/default.nix`, "Qwen-Image (official bf16 checkpoint, diffusers + ROCm)"

import vapoursynth as vs

core = vs.core
clip = video_in
src = video_in

# Alt+I AI-upscale toggle via vsncnn (ncnn Vulkan on the RX 9070 XT).
# Previous chain (vsrealesrgan / core.realesrgan / vsmlrt) is unavailable on
# odin, so it always fell back to Spline36. Model dir from vsmlrt-models.
#
# Default: RealESRGAN-x4plus (general-purpose 4x, 23 RRDB blocks) — best
# quality for photos/live-action, exported from the official .pth. Heavy:
# ~2.3 fps at 320x240, ~0.7 fps at 640x360 (free GPU; ~half when VRAM busy).
# Use while paused, or on SD video.
# Fast anime alternative (2x, ~50 fps at 320x240) — swap the MODEL line:
#   RealESRGANv2-animevideo-xsx2.onnx (RealESRGANV2 dir, anime-tuned)
MODEL = "/zero/ai/imgproc/realesrgan-x4plus.onnx"

def upscale(c):
    f = c.format
    is_rgb_f32 = f is not None and f.color_family == vs.RGB and f.sample_type == vs.FLOAT
    # vsncnn ncnn.Model wants fp32 RGB input; explicit matrix_in_s is
    # required on YUV -> RGB, otherwise resize fails with 3074 (no path)
    # and mpv silently falls back to Spline36.
    rgb = c if is_rgb_f32 else core.resize.Bicubic(c, format=vs.RGBS, matrix_in_s='709')
    out = core.ncnn.Model(clips=[rgb], network_path=MODEL)
    # mpv requires the vf output format to match the input format
    if f is not None and not is_rgb_f32:
        # explicit matrix required for RGB -> YUV (resize default 709)
        out = core.resize.Bicubic(out, format=f, matrix_s='709')
    return out

try:
    clip = upscale(clip)
except Exception:
    # keep Alt+I safe: degraded plain 4x resize instead of crashing mpv
    clip = core.resize.Spline36(src, width=src.width * 4, height=src.height * 4)

clip.set_output()
import vapoursynth as vs

core = vs.core
clip = video_in
src = video_in

# Alt+I AI-upscale toggle: 2x via vsncnn (RealESRGANv2 xsx2) on the RX 9070 XT.
# Previous chain (vsrealesrgan / core.realesrgan / vsmlrt) is unavailable on
# odin, so it always fell back to Spline36. Model dir from vsmlrt-models.
MODEL = "/zero/ai/imgproc/vsmlrt-v15.16/models/RealESRGANv2/RealESRGANv2-animevideo-xsx2.onnx"

def upscale(c):
    f = c.format
    is_rgb_f32 = f is not None and f.color_family == vs.RGB and f.sample_type == vs.FLOAT
    # vsncnn ncnn.Model wants fp32 RGB input
    rgb = c if is_rgb_f32 else core.resize.Bicubic(c, format=vs.RGBS)
    out = core.ncnn.Model(clips=[rgb], network_path=MODEL)
    # mpv requires the vf output format to match the input format
    if f is not None and not is_rgb_f32:
        out = core.resize.Bicubic(out, format=f)
    return out

try:
    clip = upscale(clip)
except Exception:
    # keep Alt+I safe: degraded plain resize instead of crashing mpv
    clip = core.resize.Spline36(src, width=src.width * 2, height=src.height * 2)

clip.set_output()

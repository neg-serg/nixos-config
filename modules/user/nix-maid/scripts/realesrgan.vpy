import vapoursynth as vs
core = vs.core
clip = video_in

scale = 2
want_anime = False

def safe_int(x, default=2):
    try:
        v = int(x)
        return v if v in (2, 4) else default
    except Exception:
        return default

try:
    import vsrealesrgan as vr
    model = 'realesr-animevideov3' if want_anime else 'realesrgan-x4plus'
    try:
        clip = vr.Realesrgan(clip, model=model, scale=scale)
    except Exception:
        try:
            clip = core.realesrgan.Model(clip, model=model, scale=scale)
        except Exception:
            pass
except Exception:
    try:
        import vsmlrt
        clip = vsmlrt.Realesrgan(clip, scale=scale, anime=want_anime)
    except Exception:
        pass

# Fallback
try:
    if clip.width == video_in.width: # if no upscale happened
       clip = core.resize.Spline36(clip, width=clip.width * scale, height=clip.height * scale)
except Exception:
    pass

clip.set_output()

{
  lib,
  pkgs,
  config,
  ...
}:
with lib; let
  xdg = import ../lib/xdg-helpers.nix {inherit lib pkgs;};
  cfg = config.features.media.aiUpscale or {};
  scale = builtins.toString (cfg.scale or 2);
  content = cfg.content or "general";
  # Minimal VapourSynth script compatible with mpv's vapoursynth filter.
  # It consumes the implicit 'video_in' clip provided by mpv and attempts to apply a model.
  # If the expected plugin is unavailable, it falls back to a simple Spline36 resize (no-op if scale=1).
  vpy = ''
    import vapoursynth as vs
    core = vs.core
    clip = video_in

    scale = ${scale}
    want_anime = ${
      if content == "anime"
      then "True"
      else "False"
    }

    def safe_int(x, default=2):
        try:
            v = int(x)
            return v if v in (2, 4) else default
        except Exception:
            return default

    scale = safe_int(scale, 2)

    try:
        # Try vsrealesrgan (ONNX or ncnn-based plugin depending on build)
        import vsrealesrgan as vr
        # Common model names; adjust as available in your plugin build
        model = 'realesr-animevideov3' if want_anime else 'realesrgan-x4plus'
        # Many builds expose vr.Realesrgan; arguments vary by build
        # Fallback to a generic call signature; ignore if not supported
        try:
            clip = vr.Realesrgan(clip, model=model, scale=scale)
        except Exception:
            # Some builds expose core.realesrgan, try that path
            try:
                clip = core.realesrgan.Model(clip, model=model, scale=scale)
            except Exception:
                pass
    except Exception:
        # Try vsmlrt (generic ONNX backend used by many VS SR plugins)
        try:
            import vsmlrt
            # Heuristic: pick a generic realesrgan model name; model discovery depends on your environment
            # If model isn't found, this will raise; we'll fall back below
            clip = vsmlrt.Realesrgan(clip, scale=scale, anime=want_anime)
        except Exception:
            pass

    # Fallback (no plugin available or call failed): simple high-quality upscale
    try:
        clip = core.resize.Spline36(clip, width=clip.width * scale, height=clip.height * scale)
    except Exception:
        pass

    clip.set_output()
  '';
in
  mkIf ((config.features.gui.enable or false) && (cfg.enable or false) && ((cfg.mode or "realtime") == "realtime")) (
    mkMerge [
      (xdg.mkXdgText "mpv/vs/ai/realesrgan.vpy" vpy)
      {
        # Toggle realtime upscale on demand (Alt+I)
        # Note: We do NOT define a profile with 'vf=...' because mpv parses profiles at startup
        # and errors if the 'vapoursynth' filter is not compiled. A runtime toggle is safe.
        programs.mpv.bindings = {
          "Alt+I" = "vf toggle vapoursynth=~~/vs/ai/realesrgan.vpy:buffered-frames=3:concurrent-frames=1";
        };
      }
    ]
  )

_inputs: _final: prev:

{
  ffmpeg = prev.ffmpeg.override {
    withSdl2 = false;
    buildFfplay = false;
    withOpenmpt = true;
  };
  ffmpeg-full = prev.ffmpeg-full.override {
    withSdl2 = false;
    buildFfplay = false;
    withOpenmpt = true;
  };

  swayimg = prev.swayimg.overrideAttrs (old: {
    env.NIX_CFLAGS_COMPILE =
      toString (old.env.NIX_CFLAGS_COMPILE or "")
      + " -O3";
  });
  neg = (prev.neg or { }) // {
    # Ensure mpv is built with VapourSynth support
    mpv-unwrapped = prev.mpv-unwrapped.overrideAttrs (old: {
      buildInputs = (old.buildInputs or [ ]) ++ [ prev.vapoursynth ];
      mesonFlags = (old.mesonFlags or [ ]) ++ [ "-Dvapoursynth=enabled" ];
    });
  };
}

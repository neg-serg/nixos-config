{
  pkgs,
  homeDir ? "/home/neg",
  ...
}:
let
  # Vivaldi bundles its own libffmpeg.so with all codecs (proprietary browser).
  # nixpkgs proprietaryCodecs=true replaces it with an outdated
  # chromium-codecs-ffmpeg-extra snap that lacks
  # av_dynamic_hdr_smpte2094_app5_to_t35 → symbol lookup error.
  #
  # We keep proprietaryCodecs=false (no snap download), but vivaldi-bin has
  # libffmpeg.so as DT_NEEDED and its RUNPATH only covers opt/vivaldi/lib/,
  # not opt/vivaldi/ where the bundled libffmpeg.so lives. Patch RUNPATH below.
  #
  # The flags are the long-standing local setup: Wayland Ozone + Skia, VA-API
  # on AMD, sRGB clamp for direct_scanout, dark about:blank, VivaldiCssMods,
  # the unpacked dark newtab extension, and the loopback CDP endpoint used to
  # inspect the browser's own DOM.
  vivaldi-pkg = pkgs.vivaldi.override {
    commandLineArgs = "--ozone-platform-hint=wayland --force-color-profile=srgb --force-dark-mode --load-extension=${homeDir}/.config/vivaldi/extensions/neg-newtab --enable-features=UseSkiaRenderer,VaapiVideoDecoder,VaapiVideoEncoder,VaapiIgnoreDriverChecks,VivaldiCssMods --disable-features=Vulkan,WaylandWpColorManagerV1 --remote-debugging-port=9222 --remote-allow-origins=*";
    proprietaryCodecs = false;
  };
in
vivaldi-pkg.overrideAttrs (old: {
  buildPhase = old.buildPhase + ''
    patchelf --add-rpath "$out/opt/vivaldi" opt/vivaldi/vivaldi-bin
  '';
})

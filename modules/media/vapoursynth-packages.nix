{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = (config.lib.neg.enabled "gui") && (config.lib.neg.enabled "media.aiUpscale");
  packages = [
    pkgs.vapoursynth # video processing engine used by upscale scripts
    pkgs.python3Packages.vapoursynth # Python bindings for scripting filters
    pkgs.vapoursynth-bestsource # frame-accurate ffmpeg-based source (VS plugin)
    pkgs.vapoursynth-mvtools # motion estimation/compensation: denoise, deinterlace (VS plugin)
    pkgs.vsncnn # NCNN Vulkan runtime for VS: Real-ESRGAN/RIFE/Real-CUGAN/DPIR (GPL-3)
  ];
  pluginDirs = [
    { name = "vsncnn"; dir = "${pkgs.vsncnn}/lib"; }
    { name = "bestsource"; dir = "${pkgs.vapoursynth-bestsource}/lib/vapoursynth"; }
    { name = "mvtools"; dir = "${pkgs.vapoursynth-mvtools}/lib/vapoursynth"; }
  ];
  # VS >= R73 ignores the old VAPOURSYNTH_PLUGINPATH env var: plugins now
  # autoload from a config file (VAPOURSYNTH_CONF_PATH) with UserPluginDir /
  # AutoloadUserPluginDir keys. Symlink every plugin dir into one root so a
  # single UserPluginDir entry covers all of them (scanned recursively).
  pluginRoot = pkgs.runCommand "vapoursynth-plugin-root" { } (
    "mkdir -p $out\n"
    + lib.concatMapStringsSep "\n" (p: "ln -s ${p.dir} $out/${p.name}") pluginDirs
  );
  vsConf = pkgs.writeText "vapoursynth.conf" ''
    UserPluginDir = ${pluginRoot}
    AutoloadUserPluginDir = true
  '';
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
    environment.variables.VAPOURSYNTH_CONF_PATH = vsConf;
  };
}

##
# Module: media/audio/plugins
# Purpose: Make installed audio plugins (VST2/VST3/LV2/CLAP/LADSPA) discoverable
#   by hosts (Carla, yabridge, DAWs). On NixOS each plugin lives isolated in its
#   own /nix/store path, so hosts find nothing unless we aggregate the lib/<fmt>
#   dirs into one location. A buildEnv added to systemPackages lands its lib/*
#   in /run/current-system/sw/lib/, which the *_PATH vars in
#   modules/system/environment.nix already search.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "media.audio.creation";
  # Packages that ship audio plugins. Entries without a lib/<fmt> dir simply
  # contribute nothing to that format (harmless).
  pluginPkgs = [
    pkgs.vital # spectral wavetable synth (VST3/VST2/CLAP)
    pkgs.dexed # DX7 FM synth (standalone only in nixpkgs; kept for future VST3)
    pkgs.lsp-plugins # Linux Studio Plugins collection (LV2/VST/CLAP/LADSPA)
  ];
  # Symlink-join only the plugin-format subdirs so unrelated outputs stay out.
  plugins = pkgs.buildEnv {
    name = "audio-plugins";
    paths = pluginPkgs;
    pathsToLink = [
      "/lib/vst3"
      "/lib/vst"
      "/lib/lxvst"
      "/lib/lv2"
      "/lib/clap"
      "/lib/ladspa"
      "/lib/dssi"
    ];
    ignoreCollisions = true;
  };
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter [ plugins ];
  };
}

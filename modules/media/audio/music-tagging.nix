##
# Module: media/audio/music-tagging
# Purpose: keep the music tagging/embedding toolchain working: the wrappers run
#          on a nix python (GC-rooted) with the music-AI venv on PYTHONPATH, so
#          a nix-collect-garbage run cannot break them the way dangling venv
#          symlinks did (see docs/howto/local-music-ai.md).
# Key options: features.media.audio.musicTagging.*
# Dependencies: the music-AI venv tree on /zero (python3.12 site-packages).
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.features.media.audio.musicTagging;
  enabled = config.lib.neg.enabled "media.audio.musicTagging";
  user = config.lib.neg.mainUser;
in
{
  config = lib.mkIf enabled {
    # The wrappers exec this interpreter and add the venv's site-packages via
    # PYTHONPATH (packages/local-bin/bin/music-*, audio-analysis). Being part
    # of the system closure is the point: the path is rooted, so GC leaves it
    # alone — unlike the store paths the venvs themselves symlink to.
    environment.systemPackages = [
      pkgs.python312 # music-AI venv interpreter (torch/transformers live in the venv)
    ];

    # Model cache for CLAP/MERT: created at activation so the first run does
    # not have to (and so it is not owned by root when it happens).
    systemd.tmpfiles.rules = [
      "d ${cfg.hfHome} 0775 ${user} ${user} -"
    ];
  };
}

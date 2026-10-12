##
# Module: media/audio/music-tagging
# Purpose: keep the music tagging/embedding toolchain working: the wrappers run
#          on a nix python (GC-rooted) with the music-AI venv on PYTHONPATH, so
#          a nix-collect-garbage run cannot break them the way dangling venv
#          symlinks did (see docs/howto/local-music-ai.md). With
#          autoIndex.enable, a weekly user timer also keeps the MERT similarity
#          index fresh without a manual hours-long pass.
# Key options: features.media.audio.musicTagging.*
# Dependencies: the music-AI venv tree on /zero (python3.12 site-packages);
#               the deployed ~/.local/bin/music-index wrapper (nix-maid).
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
  autoIndex = cfg.autoIndex;
  # Per-user unit constructor (lib/systemd-user.nix, see modules/AGENTS.md).
  systemdUser = config.lib.neg.systemdUser;

  # music-index is rendered into ~/.local/bin by nix-maid (the venv interpreter
  # and library paths are substituted at deploy time), so there is no store path
  # to call: like other local-bin units, address the deployed copy via %h.
  #
  # --quiet keeps one progress line per 25 tracks out of the journal; the run
  # summary and failures still land there. --threads 4 trades ~1.8x per-clip
  # speed for keeping most cores free for interactive work (2.05 vs 1.14 s per
  # clip against the 16-thread default, docs/howto/local-music-ai.md); Nice and
  # idle IO below deprioritize what is left.
  refreshScript = config.lib.neg.path "scripts/dev/music-refresh.sh";
  indexArgs =
    "--quiet --threads 4"
    + lib.optionalString (autoIndex.limit > 0) " --limit ${toString autoIndex.limit}"
    + lib.optionalString (autoIndex.extraArgs != [ ]) " ${lib.escapeShellArgs autoIndex.extraArgs}";
in
{
  config = lib.mkMerge [
    (lib.mkIf enabled {
      # The wrappers exec this interpreter and add the venv's site-packages via
      # PYTHONPATH (packages/local-bin/bin/music-*, audio-analysis). Being part
      # of the system closure is the point: the path is rooted, so GC leaves it
      # alone — unlike the store paths the venvs themselves symlink to.
      environment.systemPackages = [
        pkgs.python312 # music-AI venv interpreter (torch/transformers live in the venv)
      ];

      # Model cache for CLAP/MERT and the MTG tagger's EffNet/head models:
      # created at activation so the first run does not have to (and so they
      # are not owned by root when it happens).
      systemd.tmpfiles.rules = [
        "d ${cfg.hfHome} 0775 ${user} ${user} -"
        "d ${cfg.mtgModels} 0775 ${user} ${user} -"
      ];
    })

    # Opt-in weekly refresh (autoIndex): re-runs the indexer, which skips files
    # whose cache key still matches, so only new/changed albums are embedded
    # after the first pass.
    (lib.mkIf (enabled && autoIndex.enable) {
      systemd.user.services.music-index = systemdUser.mkUserService {
        presets = [
          "oneshot"
          "restartOnFailure"
        ];
        description = "Refresh the MERT similarity index incrementally";
        serviceConfig = {
          ExecStart =
            if autoIndex.tagsAndPlaylists then
              # The chain refreshes index -> tags -> playlists; each step is
              # incremental, so an unchanged library costs seconds.
              "${pkgs.bash}/bin/bash ${refreshScript} --index-args '${indexArgs}'"
            else
              "%h/.local/bin/music-index ${indexArgs}";
          # A cold pass over the whole library is hours (12h covers the measured
          # ~6h at the default thread count, ~1.8x that with --threads 4); warm
          # runs finish in minutes. A timeout is not fatal: the per-file cache
          # lets the restart resume instead of re-embedding everything.
          TimeoutStartSec = "12h";
          # The restartOnFailure preset supplies Restart=on-failure; retry while
          # the machine is up so a flaky 04:00 run (network down, interrupted
          # model fetch) does not postpone the refresh a whole week.
          RestartSec = "15min";
          # Background refresh: yield CPU and disk to interactive work.
          Nice = 10;
          IOSchedulingClass = "idle";
        };
      };

      systemd.user.timers.music-index = {
        description = "Timer: refresh the music similarity index weekly";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = autoIndex.onCalendar;
          # Catch up a Sunday missed while the machine was off; the run is
          # incremental.
          Persistent = true;
          Unit = "music-index.service";
        };
      };
    })
  ];
}

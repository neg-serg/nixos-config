# ROCm tooling for the discrete Radeon (RX 9070 XT, gfx1201).
#
# `nightjob` is the operational half of local training: unattended GPU jobs
# with a VRAM budget, a deadline and a morning report.
#
#     nightjob preflight --need-gb 12   # who holds VRAM; close apps via fzf
#     nightjob run --budget 8h -- python train.py
#     nightjob status | logs -f | report
#     nightjob env init                 # ROCm venv at /zero/ai/venvs/train
#
# It launches a transient systemd user unit (KillMode=mixed, so `stop` reaches
# the supervisor and becomes SIGINT for the trainer), samples rocm-smi into a
# CSV next to the log, retries from a checkpoint and writes final.json plus
# report.md in ~/.local/state/nightjob/<unit>/<timestamp>/.  The CLI itself is
# stdlib-only Python, so no training stack enters the system closure.
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.dev.ai.rocm;

  # The wrapper pins the tools the script shells out to, but keeps the
  # caller's PATH: `hyprctl` (window titles in preflight) and `llmctl`
  # (graceful llama-swap unload) come from the session, not from here.
  nightjob = pkgs.writeShellScriptBin "nightjob" ''
    export PATH="${
      lib.makeBinPath [
        pkgs.python3
        pkgs.fzf # interactive multi-select of the apps to close
        pkgs.rocmPackages.rocm-smi # GPU sampler (unused when fdinfo suffices)
        pkgs.pciutils # lspci: the card's marketing name
        pkgs.systemd # systemd-run / systemctl / journalctl
        pkgs.libnotify # notify-send when the job ends
        pkgs.coreutils # tail, sleep
      ]
    }:$PATH"
    exec ${pkgs.python3}/bin/python3 ${./nightjob.py} "$@"
  '';
in
{
  config = lib.mkIf cfg.enable {
    # torch-rocm (a 7.7G Python env) moved to the `rocm` devshell and the
    # `nix run .#torch-rocm` app; only the monitoring CLI stays in the closure.
    environment.systemPackages = [
      pkgs.rocmPackages.rocm-smi # ROCm System Management Interface
      nightjob # overnight GPU jobs: VRAM preflight, systemd runner, report
    ];
  };
}

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
# stdlib-only Python, so no training stack enters the system closure; the tool,
# its wrapper PATH and its test suite live in github:neg-serg/nightjob
# (`pkgs.neg.nightjob`).
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.dev.ai.rocm;
in
{
  config = lib.mkIf cfg.enable {
    # The Nix ROCm torch env is gone (it only ever served the manual devshell and
    # a second, older torch): training builds its own venv from the official ROCm
    # wheels through `nightjob env init`, so only the monitoring CLI and nightjob
    # stay in the closure.
    environment.systemPackages = [
      pkgs.rocmPackages.rocm-smi # ROCm System Management Interface
      pkgs.neg.nightjob # overnight GPU jobs: VRAM preflight, systemd runner, report
    ];
  };
}

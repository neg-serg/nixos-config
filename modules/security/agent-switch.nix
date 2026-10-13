# Module: security/agent-switch — let the agent finish a rollout by itself.
#
# Until now every change ended with "run this sudo command and tell me what it
# said": the human was the last step of every rollout. The NOPASSWD entry for
# `nixos-rebuild` itself is gone on purpose (see modules/security/default.nix) —
# activating the user-writable flake as root IS arbitrary root, and this module
# does not pretend otherwise. What it does is narrow the *shape* of that power:
#
#   - one root-owned oneshot unit performs the activation; there is no free-form
#     command line to hijack,
#   - sudoers allows exactly `systemctl start nixos-agent-switch.service` (with the
#     trailing "" marker, so the rule cannot start any other unit),
#   - the unit activates only the artifact the agent already built and verified:
#     `.agent/switch-request` names the expected toplevel, and the unit refuses
#     when the tree now builds something else — a WIP edit in /etc/nixos cannot
#     ride along by accident,
#   - HEAD, the dirty-file list, the artifact and the activation output all land
#     in the journal (`journalctl -u nixos-agent-switch`).
#
# The cost, spelled out: with this on, anything running as the main user can
# install a root unit by writing the flake and requesting a switch — that is root
# for that user. The request gate keeps accidents out, not an adversary. Flip
# features.security.agentSwitch.enable off (and switch once with a password) to
# remove the mechanism again.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.features.security.agentSwitch or { };
  systemdUser = config.lib.neg.systemdUser;
  host = config.networking.hostName;

  # Written by the agent (see .agent/workflows/rebuild.md), consumed and removed
  # by a successful switch. Gitignored: it must not show up as a tree change.
  requestFile = "/etc/nixos/.agent/switch-request";

  agentSwitch = pkgs.writeShellScript "nixos-agent-switch" ''
    set -euo pipefail
    export PATH=${
      lib.makeBinPath [
        config.nix.package
        pkgs.coreutils # readlink/head/tr for the request-and-artifact checks
        pkgs.git # rev-parse/status, so the journal records what was activated
        pkgs.nixos-rebuild-ng # the switch itself (the same nixos-rebuild-ng the host ships)
      ]
    }

    repo=/etc/nixos
    request=${lib.escapeShellArg requestFile}
    # Env seam so the guards can be exercised as a user (`NIXOS_AGENT_SWITCH_WORK`
    # pointed at a writable dir); the unit itself always uses the tmpfs default.
    work=''${NIXOS_AGENT_SWITCH_WORK:-/run/nixos-agent-switch}

    [ -d "$repo/.git" ] || { echo "not a git flake: $repo" >&2; exit 1; }
    [ -f "$request" ] || {
      echo "no switch request: $request" >&2
      echo "the agent records the verified toplevel there; see .agent/workflows/rebuild.md" >&2
      exit 1
    }

    expected="$(head -n1 "$request" | tr -d '[:space:]')"
    case "$expected" in
      /nix/store/*) ;;
      *) echo "switch request does not name a store path: $expected" >&2; exit 1 ;;
    esac

    echo "agent switch: HEAD=$(git -C "$repo" rev-parse HEAD)"
    dirty="$(git -C "$repo" status --porcelain)"
    if [ -n "$dirty" ]; then
      echo "agent switch: the tree is DIRTY; these changes are part of what gets activated:"
      echo "$dirty"
    fi

    mkdir -p "$work"
    nix build "$repo#nixosConfigurations.${host}.config.system.build.toplevel" \
      --out-link "$work/toplevel" --option substitute false

    built="$(readlink -f "$work/toplevel")"
    if [ "$built" != "$expected" ]; then
      echo "refusing to switch: the tree now builds $built, not the verified $expected" >&2
      echo "rebuild, update $request and start this unit again" >&2
      exit 1
    fi

    nixos-rebuild switch --flake "$repo#${host}" --option substitute false
    rm -f "$request"
    echo "agent switch: activated $built"
  '';
in
lib.mkIf (cfg.enable or false) {
  systemd.services.nixos-agent-switch = systemdUser.mkSystemService {
    description = "Activate the agent-prepared ${host} flake (verified toplevel only)";
    presets = [ "oneshot" ];
    serviceConfig = {
      ExecStart = agentSwitch;
      # A switch builds the closure and then activates it: the 90 s oneshot
      # default would cut the first build short.
      TimeoutStartSec = "infinity";
    };
  };

  security.sudo.extraRules = [
    {
      users = [ config.lib.neg.mainUser ];
      commands = [
        {
          # "" is sudo's exact-arguments marker: without it extra arguments are
          # accepted and the rule would start (or stop) any other unit.
          command = "/run/current-system/sw/bin/systemctl start nixos-agent-switch.service \"\"";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}

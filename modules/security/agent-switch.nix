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
#   - a polkit rule lets the main user start exactly this unit, so the trigger
#     also works inside a session sandbox where setuid sudo cannot run,
#   - the flake build runs with the main user's uid (root's libgit2 refuses a
#     user-owned repository) and only the verified store path is activated as
#     root — profile-set + switch-to-configuration, the same steps nh uses,
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
  mainUser = config.lib.neg.mainUser;
  mainGroup = config.users.users.${mainUser}.group;
  mainHome = config.users.users.${mainUser}.home;

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
        pkgs.util-linux # setpriv: run the build with the repo owner's uid
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

    # The unit runs as root while /etc/nixos belongs to the main user, so git
    # refuses with "detected dubious ownership" and `set -e` aborts the switch
    # before the build (observed 2026-10-14). Ask for safe.directory explicitly
    # instead of depending on root's own git config.
    git_repo() { git -c "safe.directory=$repo" -C "$repo" "$@"; }

    echo "agent switch: HEAD=$(git_repo rev-parse HEAD)"
    dirty="$(git_repo status --porcelain)"
    if [ -n "$dirty" ]; then
      echo "agent switch: the tree is DIRTY; these changes are part of what gets activated:"
      echo "$dirty"
    fi

    install -d -o "${mainUser}" -g "${mainGroup}" -m 0755 "$work"
    # The flake belongs to the main user; root's libgit2 refuses a user-owned
    # repository ("repository path is not owned by current user"), so build
    # with that user's uid and only activate the verified artifact as root.
    setpriv --reuid "${mainUser}" --regid "${mainGroup}" --init-groups \
      env HOME="${mainHome}" XDG_CACHE_HOME="${mainHome}/.cache" \
      nix build "$repo#nixosConfigurations.${host}.config.system.build.toplevel" \
        --out-link "$work/toplevel" --option substitute false

    built="$(readlink -f "$work/toplevel")"
    if [ "$built" != "$expected" ]; then
      echo "refusing to switch: the tree now builds $built, not the verified $expected" >&2
      echo "rebuild, update $request and start this unit again" >&2
      exit 1
    fi

    # Activate exactly the verified artifact: set the system profile and run
    # the generation's own switch-to-configuration (what nixos-rebuild and nh do
    # after building), so no flake evaluation happens as root at all.
    nix-env --profile /nix/var/nix/profiles/system --set "$built"
    NIXOS_INSTALL_BOOTLOADER=1 "$built/bin/switch-to-configuration" switch
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

  # The sandboxed agent cannot exec setuid sudo (`no_new_privs` is set inside
  # the session sandbox), so the NOPASSWD rule above is unreachable for it.
  # Mirror that rule as polkit: mainUser may start exactly this unit, without
  # interactive authentication. Same narrow shape — one unit, one verb; the
  # artifact check inside the unit remains the actual gate.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (
        action.id == "org.freedesktop.systemd1.manage-units" &&
        action.lookup("unit") == "nixos-agent-switch.service" &&
        action.lookup("verb") == "start" &&
        subject.user == "${config.lib.neg.mainUser}"
      ) {
        return polkit.Result.YES;
      }
    });
  '';
}

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
#     in the journal (`journalctl -u nixos-agent-rollout`),
#   - a start without a request file is a no-op that exits 0. The unit has no
#     WantedBy, but switch-to-configuration may still start it while activating
#     an unrelated generation; a failed start there fails the whole activation
#     (2026-10-17: `nh os switch` exited 4 with "Failed to start
#     nixos-agent-switch.service" after the previous run had consumed the file),
#   - the unit file is a constant string, so a switch can never stop the unit
#     that is performing it — see the comment on the environment.etc block below
#     for what that cost on 2026-10-17.
#
# Known limitation (2026-10-17): the polkit rule below is not the boundary it
# looks like. The main user can already manage system units without
# authentication on this host — ''systemd-run --unit=x /bin/sh -c "id -u"''
# printed 0 (root), ''systemctl stop''/''restart'' of unrelated units returned 0,
# and ''pkcheck'' (run as root with the main user as subject) answers
# "authorized" for org.freedesktop.systemd1.manage-units with an arbitrary unit
# name. A rule returning polkit.Result.AUTH_ADMIN for every other manage-units
# action changed nothing, so the authorization does not come from the rules in
# /etc/polkit-1/rules.d; debugging polkitd itself (--debug) is the next step.
# Until that is settled, treat this account as having passwordless root and the
# module as convenience, not as a gate.
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

  # writeShellApplication, not writeShellScript: the unit runs this through
  # /run/current-system/sw/bin, which needs a package with a bin/ directory
  # (a bare store-path file is not linked into the system profile).
  agentSwitch = pkgs.writeShellApplication {
    name = "nixos-agent-switch";
    runtimeInputs = [
      config.nix.package # nix build / nix-env --set
      pkgs.coreutils # readlink/head/tr for the request-and-artifact checks
      pkgs.git # rev-parse/status, so the journal records what was activated
      pkgs.util-linux # setpriv: run the build with the repo owner's uid
      pkgs.systemd # systemd-run: detach the activation into its own scope
    ];
    text = ''
      # The service only *launches* the rollout and returns at once, because
      # switch-to-configuration starts this unit while activating (observed
      # 2026-10-17) and a Type=oneshot start job on an already running instance
      # deadlocks the activation against the process running it. The work lives
      # in a transient unit of its own: it is not in any generation, so a
      # definition change cannot stop it mid-flight.
      if [ "''${NIXOS_AGENT_SWITCH_WORKER:-0}" != 1 ]; then
        # A worker already running (or launched by a spurious start during an
        # activation) makes this launch a no-op; the flock below is the second
        # line of defence against two switches at once.
        if systemctl is-active --quiet nixos-agent-rollout-work.service; then
          echo "nixos-agent-rollout-work is already running; nothing to do"
          exit 0
        fi
        systemd-run --quiet --collect --no-block \
          --unit=nixos-agent-rollout-work \
          --setenv=NIXOS_AGENT_SWITCH_WORKER=1 \
          "$0" "$@"
        exit 0
      fi

      repo=/etc/nixos
      request=${lib.escapeShellArg requestFile}
      # Env seam so the guards can be exercised as a user (`NIXOS_AGENT_SWITCH_WORK`
      # pointed at a writable dir); the unit itself always uses the tmpfs default.
      work=''${NIXOS_AGENT_SWITCH_WORK:-/run/nixos-agent-switch}

      # One switch at a time: an agent rollout, a stray start during an
      # activation and a human `nh os switch` all end in switch-to-configuration,
      # and two of those at once is what scrambled the generations on 2026-10-17.
      mkdir -p "$work"
      exec 9> "$work/lock"
      if ! flock -n 9; then
        echo "another rollout holds $work/lock; nothing to do"
        exit 0
      fi

      [ -d "$repo/.git" ] || { echo "not a git flake: $repo" >&2; exit 1; }
      [ -f "$request" ] || {
        # Missing request is "nothing to do", not a failure: the unit has no
        # WantedBy, but switch-to-configuration can still start it while
        # activating a generation (2026-10-17: an `nh os switch` reported
        # "Failed to start nixos-agent-switch.service" and exited 4 because the
        # request had already been consumed by the previous run). Exiting 1 there
        # turns a stray start into a failed activation of an unrelated switch.
        echo "no switch request: $request — nothing to do"
        echo "the agent records the verified toplevel there; see .agent/workflows/rebuild.md"
        exit 0
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
  };
in
lib.mkIf (cfg.enable or false) {
  # The script is installed into the system profile so the unit can exec it
  # through /run/current-system: the unit file below is a *constant* string, and
  # a constant unit file is the whole point. switch-to-configuration stops and
  # restarts units whose definition changed, and the previous version embedded
  # store paths (ExecStart, PATH, LOCALE_ARCHIVE) that moved on every nixpkgs or
  # script change — including while this very unit was the process running
  # switch-to-configuration. That killed an in-flight activation on 2026-10-17
  # (journal: "stopping the following units: …, nixos-agent-switch.service",
  # then status=15/TERM, profile already pointing at the half-activated
  # generation) and left the machine with the profile and /run/current-system on
  # different generations.
  environment.systemPackages = [ agentSwitch ];

  # The unit must be byte-identical in every generation, because
  # switch-to-configuration stops the units whose definition changed — and on
  # 2026-10-17 that killed an activation from inside the very unit running it.
  # Systemd units cannot be installed through environment.etc (the module owns
  # /etc/systemd/system as a symlink to the read-only system-units store path),
  # so the fields are neutralised instead: the module's defaults are
  # store-path-bearing (ExecStart, PATH from `path`, LOCALE_ARCHIVE and TZDIR
  # from systemd.globalEnvironment), hence the forced string values below. What
  # remains is text that never changes, and the script it execs lives behind
  # /run/current-system, i.e. it is always the active generation's version.
  systemd.services.nixos-agent-rollout = systemdUser.mkSystemService {
    description = "Activate the agent-prepared ${host} flake (verified toplevel only)";
    presets = [ "oneshot" ];
    # Empty: the PATH env comes from the stable string below, not from a
    # makeBinPath list that moves with nixpkgs.
    path = [ ];
    environment = {
      PATH = lib.mkForce "/run/current-system/sw/bin";
      LOCALE_ARCHIVE = lib.mkForce "/run/current-system/sw/lib/locale/locale-archive";
      TZDIR = lib.mkForce "/etc/zoneinfo";
    };
    serviceConfig = {
      ExecStart = "/run/current-system/sw/bin/nixos-agent-switch";
      # A switch builds the closure and then activates it: the 90 s oneshot
      # default would cut the first build short.
      TimeoutStartSec = "infinity";
    };
  };

  # polkit lets the main user — and therefore a sandboxed agent, which cannot
  # exec setuid sudo under `no_new_privs` — start exactly this unit without
  # interactive authentication. One unit, one verb; the artifact check inside
  # the unit remains the actual gate.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (
        action.id == "org.freedesktop.systemd1.manage-units" &&
        action.lookup("unit") == "nixos-agent-rollout.service" &&
        action.lookup("verb") == "start" &&
        subject.user == "${config.lib.neg.mainUser}"
      ) {
        return polkit.Result.YES;
      }
    });

  '';

}

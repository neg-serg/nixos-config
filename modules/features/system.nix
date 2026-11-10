{ lib, mkBool, ... }: {
  options.features.system.logTtys = {
    enable = mkBool "Per-TTY log classification (journalctl viewers on tty8,tty10-tty11,tty13-tty17)" true;
    crit.enable = mkBool "CRIT log viewer on tty8 (emerg..crit)" true;
    err.enable = mkBool "ERR log viewer on tty10 (errors)" true;
    warn.enable = mkBool "WARN log viewer on tty11 (warnings)" true;
    kernel.enable = mkBool "KERNEL log viewer on tty17 (kernel messages)" true;
    auth.enable = mkBool "AUTH log viewer on tty13 (auth messages)" true;
    systemd.enable = mkBool "SYSTEMD log viewer on tty14 (systemd messages)" true;
    network.enable = mkBool "NETWORK log viewer on tty15 (network daemons)" true;
    full.enable = mkBool "FULL log viewer on tty16 (all messages)" true;
    networkUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "NetworkManager.service"
        "sshd.service"
        "nftables.service"
      ];
      description = "Systemd units to monitor on tty15 (network TTY). Override per-host.";
    };
  };

  # Userspace console on the login VTs: kmscon takes over the autovt VTs
  # (tty2-tty6) from the in-kernel console. tty1 stays with greetd and the log
  # TTYs stay kernel consoles — see modules/system/kmscon.nix for the reasons.
  options.features.system.kmscon.enable =
    mkBool "kmscon userspace console instead of agetty on the autovt VTs" true;

  options.features.virt = {
    docker.enable = mkBool "enable docker/podman virtualization" false;
    libvirtd.enable = mkBool "enable libvirtd (KVM/QEMU) virtualization" false;
  };

  # nix-ld: run prebuilt (non-Nix) glibc binaries — GitHub release tarballs,
  # AppImage payloads, vendored toolchains — instead of patchelf'ing each one.
  options.features.system.nixLd.enable =
    mkBool "run foreign dynamically linked binaries via nix-ld" true;

  # sanoid snapshot policy for the datasets holding unrecoverable data.
  options.features.system.zfsSnapshots.enable =
    mkBool "periodic sanoid snapshots for the user-data ZFS datasets" true;

  # Daily cap on the number of system generations (each one pins its whole
  # closure in the store until nix.gc runs).
  options.features.system.generationPrune.enable =
    mkBool "prune system generations beyond the newest 25" true;

  # Auto-rollout of committed /etc/nixos changes. The watcher (user timer in
  # modules/user/nix-maid/sys/user-services/rollout-watch.nix) builds the host
  # toplevel and triggers the root-owned nixos-agent-rollout unit itself, so the
  # human stops being the last step of every rollout. Off by default: enabling
  # it means anything that can write the checkout can get root through it.
  options.features.system.rolloutWatch.enable =
    mkBool "auto-deploy committed repo changes through nixos-agent-rollout" false;

  options.features.system.rolloutWatch.repo = lib.mkOption {
    type = lib.types.str;
    default = "/etc/nixos";
    description = ''
      Live git checkout the watcher deploys from. Not `repoRoot` from
      specialArgs: during a flake evaluation that is the store copy of the
      source, and the watcher must read the real checkout and its .git.
    '';
  };

  options.features.system.rolloutWatch.branch = lib.mkOption {
    type = lib.types.str;
    default = "main";
    description = "Branch whose tip the watcher deploys; another branch or a detached HEAD is left alone.";
  };

  options.features.system.rolloutWatch.interval = lib.mkOption {
    type = lib.types.str;
    default = "*-*-* *:0/2:00";
    description = "OnCalendar expression for the watcher timer.";
  };

  options.features.system.rolloutWatch.riskyPaths = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [
      "secrets/"
      "modules/system/net/vpn/"
      "modules/security/"
      "modules/user/nix-maid/sys/user-services/rollout-watch.nix"
    ];
    description = ''
      Repo paths (regex prefixes) whose change makes the watcher stop and ask for
      a manual switch instead of deploying: a wrong secret, VPN or security-module
      change can lock the host out, and the watcher is itself part of the
      deployment mechanism.
    '';
  };

  options.features.system.rolloutWatch.ntfyUrl = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "ntfy topic URL for rollout reports (e.g. http://127.0.0.1:2586/system); null disables ntfy.";
  };

  options.features.system.rolloutWatch.desktopNotify =
    mkBool "post rollout reports as desktop notifications" true;

  options.features.system.rolloutWatch.telegramSender = lib.mkOption {
    type = lib.types.nullOr lib.types.package;
    default = null;
    description = "telegram-send wrapper for rollout reports (config.trantor.telegram.sender); null disables Telegram.";
  };

  # Weekly bump of the flake inputs that point at neg's own repositories. The
  # user timer (modules/user/nix-maid/sys/user-services/flake-bump.nix) runs
  # scripts/dev/flake-bump-own.sh, which commits flake.lock without pushing;
  # rollout-watch then deploys the commit like any other. Off by default: the
  # timer turns "weekly" into local commits and system switches with no human in
  # the loop, so enabling it is a trust decision, not a preference.
  options.features.system.flakeBump.enable =
    mkBool "bump neg's own flake inputs weekly and commit the lock" false;

  options.features.system.flakeBump.repo = lib.mkOption {
    type = lib.types.str;
    default = "/etc/nixos";
    description = ''
      Live git checkout the bump operates on. Not `repoRoot` from specialArgs:
      during a flake evaluation that is the store copy of the source, and the
      script commits into the checkout that has the .git directory.
    '';
  };

  options.features.system.flakeBump.calendar = lib.mkOption {
    type = lib.types.str;
    default = "Sun *-*-* 04:00:00";
    description = "OnCalendar expression for the weekly bump timer.";
  };

  options.features.system.flakeBump.heavy =
    mkBool "also bump aurora-src and iosevka-neg (long rebuilds)" false;
}

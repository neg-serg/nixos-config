{
  neg,
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
{
  # unbound-hosts.nix is generated data (a list), imported by services/policy.nix —
  # not a module, so it stays out of the auto-import.
  imports = [
    # NERV boot menu — reads the BLS entries systemd-boot writes and hands the
    # picked entry back to systemd-boot
    inputs.nerv-boot.nixosModules.default
  ]
  ++ neg.importDir {
    dir = ./.; # unbound-hosts.nix is generated data (a list), not a module
    includeDirs = true;
    exclude = [ "unbound-hosts.nix" ];
  };
  system.preserveFlake = false;
  # Rollout benchmark trigger: scripts/dev/rollout-bench.sh rewrites this label
  # for every measured round, so a round performs a real (tiny) rollout instead
  # of a fully warm no-op. It repeats nixpkgs' own default (label = version), so
  # the tree builds exactly as it would without the line — keep that property if
  # the value ever changes.
  system.nixos.label = lib.mkDefault config.system.nixos.version;

  # Composable profiles: order matters, last wins on conflicts
  features.profiles = [
    "desktop"
    "dev"
    "gaming"
  ];
  # Password hash from SOPS (kept out of Nix store).
  # sops-nix with key="password_hash" extracts just the hash value from the YAML file.
  sops.secrets."user-password-hash" = {
    sopsFile = config.lib.neg.path "secrets/home/user-password-hash.sops.yaml";
    format = "yaml";
    key = "password_hash";
    mode = "0400";
  };
  users.main.hashedPasswordFile = config.sops.secrets."user-password-hash".path;

  # Console font (visible on tty1-6; plymouth owns the screen during boot)
  console = {
    earlySetup = true;
    font = "${pkgs.terminus_font}/share/consolefonts/ter-124n.psf.gz";
  };

  # Boot splash. `splash` already rides in boot.kernelParams through
  # profiles.performance.quietBoot, so this only adds the daemon, the initrd
  # payload and the theme. adi1090x ships all ~30 themes in one derivation;
  # `selected_themes` keeps the closure to the two we switch between.
  boot.plymouth = {
    enable = true;
    theme = "lone";
    themePackages = [
      (pkgs.adi1090x-plymouth-themes.override {
        selected_themes = [
          "lone"
          "green_blocks"
        ];
      })
    ];
  };

  # Host-specific overrides (above profile defaults)
  # Obsidian installed via Flatpak (to avoid Electron in Nix closure)
  # PGO build of Determinate Nix (packages/nix-det-pgo): -18 % on the toplevel eval,
  # lazy-trees intact, same drvPath. The rebuild restarts nix-daemon; if it ever breaks,
  # the way back is `nixos-rebuild switch --rollback` from a TTY.
  features.nix.pgoNix.enable = true;

  features.web.vivaldi.enable = true;
  features.web.default = "vivaldi";
  features.mail.vdirsyncer.enable = false; # Disabled: no Google OAuth credentials (missing secrets/home/vdirsyncer/google.sops.yaml)
  features.mail.mbsync.enable = false;
  features.net.zapret2.enable = true; # Zapret2 DPI bypass (nfqws2)
  features.net.rknDomains.enable = true; # RKN blocklist -> zapret2 hostlist
  features.net.netHealth.enable = true; # Periodic net/DNS/zapret2 health check with self-heal + ntfy
  features.net.ceno.enable = true; # Ceno/Ouinet P2P client (censorship-circumvention node)
  features.net.proxy.enable = true; # sing-box SOCKS5 proxy (+ xray.service), no full-TUN mode
  features.virt.docker.enable = true; # Podman + docker-compat stack (for the Ceno/Ouinet container)
  features.dev.ai.rocm.enable = true; # ROCm training tooling: nightjob + rocm-smi (torch comes from `nightjob env init` wheels)
  features.dev.unity.enable = true; # unityhub-proxy / unity-proxy: Unity Hub + `unity` CLI through the SOCKS5 proxy
  features.dev.java.enable = false; # no Java work here — keeps the ~630M Maven/JDK stack out of the closure
  features.dev.craftAnything.enable = true; # reverse-engineering workbench (GUI + CLI + MCP), built on first use
  services.speechd.enable = false; # no screen reader — drops speech-dispatcher + MBROLA voices (~650M)
  # WinApps and its VM stack are off for now: the module pulls qemu_kvm,
  # freerdp, virt-viewer, a virt-manager launcher and the RDPWindows libvirt
  # domain (~500 MiB of system closure) for VMs that are shut off. Re-enable
  # these two flags to bring the stack back; the VM images stay untouched in
  # /var/lib/libvirt.
  features.virt.libvirtd.enable = false;
  features.apps.winapps.enable = false;
  # Declarative Wine apps — features.wine.apps.<id>; managed via the `wineapps`
  # CLI (list/install/uninstall/run). Workflow: see the wine-apps DSH skill.
  features.wine.enable = true;
  features.wine.apps = { }; # Windows apps for the wineapps CLI; add only what you need
  features.gui.vicinae.manageConfig = true; # Nix-managed vicinae theme/settings (neg.nvim-style)
  # Pleamar shell (features.gui.pleamar): this is the session's shell — bar,
  # panels, notifications, toast and launcher run as their own units, all
  # 18 scene files compile, and the panels' frame cost is inside the screen's
  # own period (tests/evidence/). It is the only shell in the tree: the
  # Quickshell reference panel and its `quickshell.service` are gone, so
  # nothing else competes for the bottom edge.
  features.gui.pleamar.enable = true;
  # Sonda (features.gui.sonda): a file manager whose search knows the contents
  # of the files, with its window as one more pleamar scene. Installed, not
  # autostarted: the window starts the reader itself, and the models come with
  # the first `sonda setup` (865 MB into ~/.local/share/sonda).
  features.gui.sonda.enable = true;
  # Wallpaper picker (features.gui.wallpaperPicker): the swatch deck — the pleamar
  # scene `picker` since the port, on M4+C+w — browses ~/pic/wl and hands the chosen
  # card to wl-daemon (`wl img {}`), so the login screen, the bar accent and
  # `wl restore` keep following one owner. Its unit is on demand, not autostarted.
  features.gui.wallpaperPicker.enable = true;
  # Weekly incremental refresh of the MERT similarity index (music-index): warm
  # runs embed only new/changed albums. --layer -1 pins the settings of the
  # index built on 2026-10-12; without it the timer would rebuild everything,
  # because the default layer for MERT-v1 is -2 (docs/howto/local-music-ai.md).
  features.media.audio.musicTagging.autoIndex = {
    enable = true;
    # One weekly pass refreshes the index, the MTG tags and the mood/genre
    # playlists; every step skips work whose inputs did not change.
    tagsAndPlaylists = true;
    # Describe new arrivals with the GPU engine (3-6 s each with
    # describeEngine = "auto", so 50 tracks are ~5 min); if the GPU is busy the
    # CPU fallback makes the same pass a couple of hours, which the 04:00 slot
    # and the idle IO class can absorb. Feeds the mf playlists.
    describeLimit = 50;
    extraArgs = [
      "--layer"
      "-1"
      # MERT inference on the ROCm wheel aborted with "Memory access fault by
      # GPU node-1 ... Page not present" (kernel 7.2.7, torch 2.13.0+rocm7.1,
      # 2026-10-12) and left a 1.6 GiB core dump; the weekly run stays on CPU
      # until that is understood. `music-embed --device cuda TRACK.flac` is the
      # one-file way to retest.
      "--device"
      "cpu"
    ];
  };
  # Music Flamingo (music-describe) is a 15.4 GiB checkpoint that lives outside
  # the HuggingFace cache, so point the wrapper at the directory instead of the
  # hub id — otherwise the first run downloads it again into hfHome.
  features.media.audio.musicTagging.describeModel = "/zero/ai/music-ai/music-flamingo";
  # GPU first (3-6 s per track), CPU fallback when ollama or a game holds
  # the VRAM — the nightly describe step and the voice command then never
  # fail, they only get slower.
  features.media.audio.musicTagging.describeEngine = "auto";
  hardware.gpu.corectrl.enable = true;
  # Override default networkUnits: trantor uses systemd-networkd, not NetworkManager
  features.system.logTtys.networkUnits = [
    "systemd-networkd.service" # Primary network configuration
    "sshd.service" # SSH daemon
    "nftables.service" # Firewall
  ];

  # Primary user (single source of truth for name/ids)
  users.main = {
    name = "neg"; # login stays ASCII: home, groups and every path depend on it
    uid = 1000;
    gid = 1000;
    description = "Sergey Miroshnichenko"; # GECOS/real name: who/finger/lock screens
  };

  # Host-specific feature toggles
  features.dev.ai.herdr.enable = true; # Herdr — agent runtime: workspaces/panes for dsh sessions, state sidebar
  features.dev.pkgs.joern = false; # Joern (2.9 GB JVM stack) off: not used on this host
  features.llm.enable = true; # Local LLM stack: Ollama (ROCm, models on /zero/ai/ollama), voxinput
  features.cli.broot.enable = true;
  features.text.wordcraft.enable = true; # WordCraft — Word-style word processor, replaces LibreOffice
  features.hardware.usbAutomount.enable = true;
  features.hardware.bluetooth.enable = true; # BlueZ — BT audio + HID (gamepads/keyboards/mice), needs kernel BT_HIDP/UHID
  # MediaTek MT7927/MT6639 WiFi: in-tree since 7.3 — the mt76 mt7925e driver is
  # built from modules/system/kernel/overlay.config (H22, CONFIG_MT7925E=m), so
  # the out-of-tree cmspam/mt7927-nixos package is gone. Bluetooth was always
  # in-tree (BT_MTK + BT_HCIBTUSB_MTK); the MT6639 RAM-code blob comes from
  # hosts/trantor/hardware/system.nix.
  features.input.kanata.enable = true; # Caps→Ctrl via kanata
  features.input.ruHotkeys.enable = true; # us layout in kitty/mpv on focus (RU hotkey fix)
  features.input.neru.enable = true; # Ctrl+Alt+… hints/grids/vim-keys navigation (neru daemon)
  # features.security.tpmSudo.enable = true; # TPM-backed passwordless sudo — flip AFTER enabling fTPM in UEFI/BIOS
  # AppArmor confinement for the network-facing daemons: the system ones
  # (sshd, unbound, AdGuard Home, ntfy, avahi) and the session ones that parse
  # network data as user neg (sing-box, transmission, aria2). All of them ship
  # in "complain" — denials are logged, nothing is blocked — so the first
  # switch is observation-only. Flip a daemon to "enforce" in
  # modules/features/security.nix after reviewing its denials:
  # modules/security/apparmor.nix.
  features.security.apparmor.enable = true;

  # nixpkgs 26.05: service users need explicit isSystemUser + group.
  # Defined at host level because server modules gate behind mkIf cfg.enable,
  # which may be false while the NixOS service module still defines the user.
  users.users = {
    sshd = {
      isSystemUser = true;
      group = "sshd";
    };
    adguardhome = {
      isSystemUser = true;
      group = "adguardhome";
    };
    unbound = {
      isSystemUser = true;
      group = "unbound";
    };
  };
  users.groups = {
    sshd = { };
    adguardhome = { };
    unbound = { };
  };

  environment.systemPackages = [
    pkgs.nodejs # Node.js — required by npx, MCP servers, git hooks
    pkgs.wtype # Wayland keyboard input simulator (Ctrl+Space→Tab)
    pkgs.kanata # keyboard remapper (Caps→Ctrl, etc.)
    pkgs.podman # container management for distrobox (Docker-compatible)
  ];
}

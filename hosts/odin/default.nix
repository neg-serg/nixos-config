{
  neg,
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
let
  # --- zellij: Russian-layout duplicate binds (ЙЦУКЕН) ------------------------
  # GENERATED from lib/ru-keys.nix (single source of truth) — do not edit the
  # generated chars. Latin binds live in files/gui/zellij/config.kdl with the
  # zellijRuBinds.* markers; the daemon ru-layout already forces us in the
  # terminal, so these duplicates only matter after a manual M4+S switch.
  ruKeys = import ../../lib/ru-keys.nix;

  # Positional constructor for the table below: nixfmt keeps a three-name
  # `inherit` on one line, so each record costs one line instead of five.
  zellijBind = mod: key: action: { inherit mod key action; };

  zellijRuBinds = {
    focus = [
      (zellijBind "Alt " "h" "MoveFocus \"left\"")
      (zellijBind "Alt " "j" "MoveFocus \"down\"")
      (zellijBind "Alt " "k" "MoveFocus \"up\"")
      (zellijBind "Alt " "l" "MoveFocus \"right\"")
      # Emacs-style focus (Alt + npfb)
      (zellijBind "Alt " "n" "MoveFocus \"down\"")
      (zellijBind "Alt " "p" "MoveFocus \"up\"")
      (zellijBind "Alt " "f" "MoveFocus \"right\"")
      (zellijBind "Alt " "b" "MoveFocus \"left\"")
    ];
    resize = [
      (zellijBind "" "h" "Resize \"left\"")
      (zellijBind "" "j" "Resize \"down\"")
      (zellijBind "" "k" "Resize \"up\"")
      (zellijBind "" "l" "Resize \"right\"")
    ];
    tab = [
      (zellijBind "" "l" "GoToNextTab")
      (zellijBind "" "h" "GoToPreviousTab")
      (zellijBind "" "n" "NewTab; SwitchToMode \"normal\"")
      (zellijBind "" "r" "SwitchToMode \"rename-tab\"")
    ];
    scroll = [
      (zellijBind "" "j" "ScrollDown")
      (zellijBind "" "k" "ScrollUp")
      # Emacs-style scroll (n/p)
      (zellijBind "" "n" "ScrollDown")
      (zellijBind "" "p" "ScrollUp")
    ];
  };

  # Generated blocks are indented to match the surrounding keybinds (8 spaces).
  # Built with explicit strings: multi-line '' strings would strip the indent.
  zellijRuBlock =
    binds:
    "        // Russian layout (ЙЦУКЕН) — GENERATED from lib/ru-keys.nix\n"
    + "        // Table: docs/howto/hotkeys-ru-layout.md\n"
    + lib.concatStringsSep "\n" (
      map (d: "        bind \"${d.mod}${ruKeys.toRu d.key}\" { ${d.action}; }") binds
    );

  zellijConfig = builtins.readFile (config.lib.neg.path "files/gui/zellij/config.kdl");
  zellijText = lib.pipe zellijConfig [
    (
      s:
      builtins.replaceStrings
        [
          "        // Russian layout (ЙЦУКЕН) — GENERATED (zellijRuBinds.focus), see hosts/odin/default.nix"
        ]
        [ (zellijRuBlock zellijRuBinds.focus) ]
        s
    )
    (
      s:
      builtins.replaceStrings
        [
          "        // Russian layout (ЙЦУКЕН) — GENERATED (zellijRuBinds.resize), see hosts/odin/default.nix"
        ]
        [ (zellijRuBlock zellijRuBinds.resize) ]
        s
    )
    (
      s:
      builtins.replaceStrings
        [ "        // Russian layout (ЙЦУКЕН) — GENERATED (zellijRuBinds.tab), see hosts/odin/default.nix" ]
        [ (zellijRuBlock zellijRuBinds.tab) ]
        s
    )
    (
      s:
      builtins.replaceStrings
        [
          "        // Russian layout (ЙЦУКЕН) — GENERATED (zellijRuBinds.scroll), see hosts/odin/default.nix"
        ]
        [ (zellijRuBlock zellijRuBinds.scroll) ]
        s
    )
  ];
in
{
  # unbound-hosts.nix is generated data (a list), imported by services/policy.nix —
  # not a module, so it stays out of the auto-import.
  imports = [
    # Out-of-tree MT7927/MT6639 WiFi (mt76/mt7925e) — see hardware flags below
    inputs.mt7927.nixosModules.default
  ]
  ++ neg.importDir {
    dir = ./.; # unbound-hosts.nix is generated data (a list), not a module
    includeDirs = true;
    exclude = [ "unbound-hosts.nix" ];
  };
  system.preserveFlake = false;

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

  # Console font (visible during early boot and on tty1-6)
  console = {
    earlySetup = true;
    font = "${pkgs.terminus_font}/share/consolefonts/ter-124n.psf.gz";
  };

  # Host-specific overrides (above profile defaults)
  # Obsidian installed via Flatpak (to avoid Electron in Nix closure)
  features.web.vivaldi.enable = true;
  features.web.default = "vivaldi";
  features.mail.vdirsyncer.enable = false; # Disabled: no Google OAuth credentials (missing secrets/home/vdirsyncer/google.sops.yaml)
  features.mail.mbsync.enable = false;
  features.net.zapret2.enable = true; # Zapret2 DPI bypass (nfqws2)
  features.net.rknDomains.enable = true; # RKN blocklist -> zapret2 hostlist
  features.net.netHealth.enable = true; # Periodic net/DNS/zapret2 health check with self-heal + ntfy
  features.net.ceno.enable = true; # Ceno/Ouinet P2P client (censorship-circumvention node)
  features.net.proxy.enable = true; # sing-box full-TUN proxy (tun on/off toggle, no autostart) + xray.service
  features.virt.docker.enable = true; # Podman + docker-compat stack (for the Ceno/Ouinet container)
  features.dev.ai.rocm.enable = true; # ROCm PyTorch (gfx1201) for GPU fine-tuning (kernel side: features.hardware.amdgpu.rocm)
  features.virt.libvirtd.enable = true;
  features.apps.winapps.enable = true;
  features.apps.winapps.desktopApps = [
    "excel"
    "word"
    "outlook"
    "cmd"
    "powershell"
  ];
  # Declarative Wine apps — features.wine.apps.<id>; managed via the `wineapps`
  # CLI (list/install/uninstall/run). Workflow: see the wine-apps DSH skill.
  features.wine.enable = true;
  features.wine.apps = { }; # Windows apps for the wineapps CLI; add only what you need
  features.gui.vicinae.manageConfig = true; # Nix-managed vicinae theme/settings (neg.nvim-style)
  hardware.gpu.corectrl.enable = true;
  # Override default networkUnits: odin uses systemd-networkd, not NetworkManager
  features.system.logTtys.networkUnits = [
    "systemd-networkd.service" # Primary network configuration
    "sshd.service" # SSH daemon
    "nftables.service" # Firewall
  ];

  # Primary user (single source of truth for name/ids)
  users.main = {
    name = "neg";
    uid = 1000;
    gid = 1000;
    description = "Neg";
  };

  # Host-specific feature toggles
  features.dev.ai.omp.enable = true; # Oh My Pi (omp) — AI coding agent fork with LSP, DAP, subagents
  features.llm.enable = true; # Local LLM stack: Ollama (ROCm, models on /zero/ai/ollama), colibri engine, voxinput
  # NOTE: colibri-serve deliberately NOT enabled (user's choice 2026-08-28):
  # run manually when needed — see docs/howto/local-llm.md (colibrì section).
  features.cli.broot.enable = true;
  features.hardware.usbAutomount.enable = true;
  features.hardware.bluetooth.enable = true; # BlueZ — BT audio + HID (gamepads/keyboards/mice), needs kernel BT_HIDP/UHID
  # MediaTek MT7927/MT6639 WiFi via out-of-tree mt76 (cmspam/mt7927-nixos).
  # enableBluetooth = false: BT already handled in-tree (6.18 mt6639 backport).
  hardware.mediatek-mt7927 = {
    enable = true;
    enableWifi = true;
    enableBluetooth = false;
    disableAspm = true;
  };
  features.input.kanata.enable = true; # Caps→Ctrl via kanata
  features.input.ruHotkeys.enable = true; # us layout in kitty/mpv on focus (RU hotkey fix)
  # features.security.tpmSudo.enable = true; # TPM-backed passwordless sudo — flip AFTER enabling fTPM in UEFI/BIOS

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
    pkgs.zellij # Terminal workspace with batteries included (Rust)
    pkgs.wtype # Wayland keyboard input simulator (Ctrl+Space→Tab)
    pkgs.kanata # keyboard remapper (Caps→Ctrl, etc.)
    pkgs.podman # container management for distrobox (Docker-compatible)
  ];
  environment.etc."zellij/config.kdl".text = zellijText;
}

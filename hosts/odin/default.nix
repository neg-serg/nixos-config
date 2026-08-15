{
  pkgs,
  config,
  lib,
  ...
}:
let
  entries = builtins.readDir ./.;
in
{
  # unbound-hosts.nix is generated data (a list), imported by services.nix —
  # not a module, so it stays out of the auto-import.
  imports =
    builtins.attrNames entries
    |> builtins.filter (
      n:
      n != "default.nix"
      && n != "unbound-hosts.nix"
      && (entries.${n} == "directory" || lib.hasSuffix ".nix" n)
    )
    |> builtins.map (n: ./. + "/${n}");
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

  # Console font (visible before plymouth and on tty1-6)
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
  features.virt.libvirtd.enable = true;
  features.apps.winapps.enable = true;
  features.apps.winapps.desktopApps = [
    "excel"
    "word"
    "outlook"
    "cmd"
    "powershell"
  ];
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
  features.cli.broot.enable = true;
  features.hardware.usbAutomount.enable = true;
  features.input.kanata.enable = true; # Caps→Ctrl via kanata

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
  boot.plymouth.enable = false; # Plymouth removed — adds boot delay, splash not needed on this host

  environment.systemPackages = [
    pkgs.nodejs # Node.js — required by npx, MCP servers, git hooks
    pkgs.zellij # Terminal workspace with batteries included (Rust)
    pkgs.wtype # Wayland keyboard input simulator (Ctrl+Space→Tab)
    pkgs.kanata # keyboard remapper (Caps→Ctrl, etc.)
    pkgs.podman # container management for distrobox (Docker-compatible)
  ];
  environment.etc."zellij/config.kdl".text = builtins.readFile (
    config.lib.neg.path "files/gui/zellij/config.kdl"
  );
}

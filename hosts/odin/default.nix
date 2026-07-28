{ pkgs, config, ... }:
{
  imports = [
    ./hardware.nix
    ./networking.nix
    ./services.nix
    ./virtualisation/lxc.nix
  ];
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
    sopsFile = ../../secrets/home/user-password-hash.sops.yaml;
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
  features.web.codexStellarium.enable = true;
  features.mail.vdirsyncer.enable = true;
  features.mail.mbsync.enable = false;
  features.hardware.bluetooth.enable = false;
  features.net.proxy.enable = true;
  features.net.lan-proxy.enable = true;
  features.net.transparent-proxy.enable = false; # Disabled: upstream dead, using proxy script fallback
  # Xray upstream dead — disable the service (keep features.net.proxy for env/packages)
  systemd.services.xray.enable = false;
  features.dev.haskell.enable = true; # Enable Haskell toolchain (GHC, cabal, stack, HLS)
  features.virt.libvirtd.enable = true;
  features.apps.winapps.enable = true;
  features.apps.winapps.desktopApps = [ "excel" "word" "outlook" "cmd" "powershell" "vscode" ];
  features.apps.guiAppsFull.enable = false; # Disable heavy GUI apps (GIMP, OBS); gaming profile enables it by default
  features.gui.vicinae.manageConfig = true; # Nix-managed vicinae theme/settings (neg.nvim-style)
  hardware.gpu.corectrl.enable = true;
  features.dev.cpp.enable = true; # Enable C++ toolchain (ccache, gcc, cmake)
  # Override default networkUnits: odin uses systemd-networkd, not NetworkManager
  features.system.logTtys.networkUnits = [
    "systemd-networkd.service" # Primary network configuration
    "sshd.service" # SSH daemon
    "tailscaled.service" # Tailscale VPN
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
  features.dev.ai.pi.enable = false;
  features.cli.broot.enable = true;
  features.dev.tla.enable = true;
  features.hardware.usbAutomount.enable = true;
  features.net.tailscale.enable = true;
  features.input.kanata.enable = true; # Caps→Ctrl via kanata
  features.input.warpd.enable = true; # warpd: keyboard-driven pointer control

  # Roles enabled for this host
  roles = {
    workstation.enable = true;
    homelab.enable = true;
    media.enable = true;
    monitoring.enable = true;
  };
  boot.plymouth.enable = false; # Plymouth removed — adds boot delay, splash not needed on this host

  environment.systemPackages = [
    pkgs.nodejs # Node.js — required by npx, MCP servers, git hooks
    pkgs.zellij # Terminal workspace with batteries included (Rust)
    pkgs.kanata # keyboard remapper (Caps→Ctrl, etc.)
    pkgs.podman # container management for distrobox (Docker-compatible)
    (pkgs.writeShellScriptBin "genlc-media" (builtins.readFile ./../../files/scripts/genlc-media.sh))
  ];
  environment.etc."zellij/config.kdl".text = builtins.readFile ./../../files/gui/zellij/config.kdl;
}

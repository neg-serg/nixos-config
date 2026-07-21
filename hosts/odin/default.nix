{ pkgs, ... }:
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

  # Console font (visible before plymouth and on tty1-6)
  console = {
    earlySetup = true;
    font = "${pkgs.terminus_font}/share/consolefonts/ter-124n.psf.gz";
  };

  # Host-specific overrides (above profile defaults)
  # Obsidian installed via Flatpak (to avoid Electron in Nix closure)
  features.web.vivaldi.enable = true;
  features.web.default = "vivaldi";
  features.mail.vdirsyncer.enable = false;
  features.mail.mbsync.enable = false;
  features.hardware.bluetooth.enable = false;
  features.net.proxy.enable = true;
  features.net.lan-proxy.enable = true;
  features.net.transparent-proxy.enable = false; # Disabled: upstream dead, using proxy script fallback
  # Xray upstream dead — disable the service (keep features.net.proxy for env/packages)
  systemd.services.xray.enable = false;
  features.dev.haskell.enable = true; # Enable Haskell toolchain (GHC, cabal, stack, HLS)
  features.virt.libvirtd.enable = false; # Disable KVM/QEMU (not needed on this host)
  features.apps.guiAppsFull.enable = false; # Disable heavy GUI apps (GIMP, OBS); gaming profile enables it by default
  features.gui.vicinae.enable = true; # Vicinae Wayland app runner + window switcher
  features.gui.vicinae.manageConfig = true; # Nix-managed vicinae theme/settings (neg.nvim-style)
  features.gui.hdr.enable = false; # Disable HDR (DXVK_HDR) — Hyprland not configured for it, causes washed-out fullscreen
  features.dev.cpp.enable = true; # Enable C++ toolchain (ccache, gcc, cmake)
  # Override default networkUnits: odin uses systemd-networkd, not NetworkManager
  features.system.logTtys.networkUnits = [
    "systemd-networkd.service" # Primary network configuration
    "sshd.service" # SSH daemon
    "tailscaled.service" # Tailscale VPN
    "nftables.service" # Firewall
  ];
  boot.plymouth.enable = false; # Plymouth removed — adds boot delay, splash not needed on this host

  # Zellij terminal multiplexer
  environment.systemPackages = [
    pkgs.zellij # Terminal workspace with batteries included (Rust)
  ];

  environment.etc."zellij/config.kdl".text = builtins.readFile ./../../files/gui/zellij/config.kdl;
}

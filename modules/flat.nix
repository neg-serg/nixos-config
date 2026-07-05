{ ... }:
{
  imports = [
    ./appimage/default.nix
    ./apps/obsidian/default.nix
    ./cli/default.nix
    ./core/neg.nix
    ./dev/android/default.nix
    ./dev/benchmarks/default.nix
    ./dev/editor/default.nix
    ./dev/gcc/autofdo.nix
    ./dev/gdb/default.nix
    ./dev/git/pkgs.nix # Nix package manager
    ./dev/opencode.nix
    ./dev/pkgs/default.nix
    ./dev/python/pkgs.nix # Nix package manager
    ./dev/unreal/default.nix
    ./diff-closures.nix
    ./documentation/settings.nix
    ./emulators/pkgs.nix # Nix package manager

    ./features/apps.nix
    ./features/cli.nix
    ./features/core.nix
    ./features/default.nix
    ./features/dev.nix
    ./features/games.nix
    ./features/gui.nix
    ./features/media.nix
    ./features/misc.nix
    ./features/services.nix
    ./features/web.nix

    ./flake-preflight.nix
    ./fonts/default.nix
    ./fun/default.nix
    ./games/default.nix

    ./hardware/amdgpu.nix
    ./hardware/audio/dsp/pkgs.nix # Nix package manager
    ./hardware/audio/hdspe/default.nix
    ./hardware/audio/pipewire/default.nix
    ./hardware/audio/pulseaudio/default.nix
    ./hardware/config.nix
    ./hardware/cooling.nix
    ./hardware/gpu-corectrl.nix
    ./hardware/io/pkgs.nix # Nix package manager
    ./hardware/liquidctl.nix
    ./hardware/pkgs.nix # Nix package manager
    ./hardware/qmk/default.nix
    ./hardware/udev-rules/default.nix
    ./hardware/uinput.nix
    ./hardware/usb-automount.nix
    ./hardware/video/amd/default.nix
    ./hardware/video/pkgs/default.nix
    ./hardware/webcam/pkgs.nix # Nix package manager

    ./llm/default.nix
    ./media/audio/default.nix
    ./media/default.nix

    ./monitoring/grafana/default.nix
    ./monitoring/logs/default.nix
    ./monitoring/loki/default.nix
    ./monitoring/netdata/default.nix
    ./monitoring/php-fpm-exporter/default.nix
    ./monitoring/pkgs/default.nix
    ./monitoring/promtail/default.nix
    ./monitoring/sysstat/default.nix
    ./monitoring/vnstat/default.nix

    ./nix/clblast.nix
    ./nix/default.nix

    ./profiles/services.nix
    ./profiles/default.nix
    ./roles/default.nix
    ./secrets/pass/default.nix
    ./secrets/pkgs.nix # Nix package manager
    ./secrets/yubikey/default.nix
    ./security/default.nix

    ./servers/adguardhome/default.nix
    ./servers/avahi/default.nix
    ./servers/bitcoind/default.nix
    ./servers/duckdns/default.nix
    ./servers/geoclue/default.nix
    ./servers/jellyfin/default.nix
    ./servers/mpd/default.nix
    ./servers/netdata/default.nix
    ./servers/openssh/default.nix
    ./servers/samba/default.nix
    ./servers/unbound/default.nix

    ./shell/default.nix

    ./system/boot.nix
    ./system/environment.nix
    ./system/filesystems.nix
    ./system/irqbalance.nix
    ./system/kernel/default.nix
    ./system/net/default.nix
    ./system/net/rkn/default.nix
    ./system/net/vpn/default.nix
    ./system/net/zapret2/default.nix
    ./system/oomd.nix
    ./system/pkgs.nix # Nix package manager
    ./system/preserve-flake.nix
    ./system/profiles/default.nix
    ./system/swapfile.nix
    ./system/systemd/default.nix
    ./system/tailscale.nix
    ./system/users.nix
    ./system/virt.nix
    ./system/vm/definitions.nix
    ./system/winapps.nix
    ./system/zram.nix

    ./text/default.nix
    ./tools/default.nix
    ./torrent/default.nix

    ./user/dbus.nix
    ./user/fonts.nix
    ./user/games/default.nix
    ./user/gui-packages.nix
    ./user/locale-pkgs.nix # Nix package manager
    ./user/locale.nix
    ./user/locate.nix
    ./user/mail.nix
    ./user/neovim.nix
    ./user/nix-maid/default.nix
    ./user/psd/default.nix
    ./user/session/default.nix
    ./user/theme-packages.nix
    ./user/wrappers/default.nix
    ./user/xdg.nix

    ./web/default.nix
  ];
}

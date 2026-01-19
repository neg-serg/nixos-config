{ ... }:
{
  imports = [
    ./appimage/default.nix
    ./appimage/pkgs.nix # Nix package manager
    ./cli/archives/pkgs.nix # Nix package manager
    ./cli/default.nix
    ./cli/dev.nix
    ./cli/file-ops.nix
    ./cli/media.nix
    ./cli/monitoring.nix
    ./cli/network.nix
    ./cli/system.nix
    ./cli/text.nix
    ./cli/tmux/default.nix
    ./cli/tools.nix
    ./cli/ugrep.nix
    ./core/neg.nix
    ./dev/android/default.nix
    ./dev/benchmarks/default.nix
    ./dev/editor/default.nix
    ./dev/editor/neovim/pkgs.nix # Nix package manager
    ./dev/editor/pkgs.nix # Nix package manager
    ./dev/gcc/autofdo.nix
    ./dev/gdb/default.nix
    ./dev/git/pkgs.nix # Nix package manager
    ./dev/openxr/default.nix
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
    ./flatpak/default.nix
    ./flatpak/pkgs.nix # Nix package manager
    ./fonts/default.nix
    ./fun/default.nix

    ./fun/launchers-packages.nix
    ./fun/misc-packages.nix
    ./games/controllers.nix
    ./games/default.nix
    ./games/tuning.nix
    ./hardware/amdgpu.nix
    ./hardware/audio/dsp/pkgs.nix # Nix package manager
    ./hardware/audio/pipewire/default.nix
    ./hardware/audio/pulseaudio/default.nix
    ./hardware/config.nix
    ./hardware/cooling.nix
    ./hardware/gpu-corectrl.nix
    ./hardware/io/pkgs.nix # Nix package manager
    ./hardware/liquidctl.nix
    ./hardware/pkgs.nix # Nix package manager
    ./hardware/qmk/default.nix
    ./hardware/qmk/pkgs.nix # Nix package manager
    ./hardware/udev-rules/default.nix
    ./hardware/uinput.nix
    ./hardware/usb-automount.nix
    ./hardware/video/amd/default.nix
    ./hardware/video/nvidia/rtx5090.nix
    ./hardware/video/pkgs/default.nix
    ./hardware/webcam/pkgs.nix # Nix package manager
    ./llm/codex-config.nix
    ./llm/default.nix
    ./llm/ollama.nix
    # ./llm/open-webui.nix
    ./llm/pkgs.nix # Nix package manager
    ./media/ai-upscale-packages.nix
    ./media/audio/apps-packages.nix
    ./media/audio/core-packages.nix
    ./media/audio/creation-packages.nix
    ./media/audio/default.nix
    ./media/audio/mpd-packages.nix
    ./media/audio/spotifyd.nix
    ./media/deepfacelab-docker.nix
    ./media/default.nix
    ./media/multimedia-packages.nix
    ./media/vapoursynth-packages.nix
    ./monitoring/grafana/default.nix
    ./monitoring/logs/default.nix
    ./monitoring/loki/default.nix
    ./monitoring/netdata/default.nix
    ./monitoring/php-fpm-exporter/default.nix
    ./monitoring/pkgs/default.nix
    ./monitoring/promtail/default.nix
    ./monitoring/sysstat/default.nix
    ./monitoring/vnstat/default.nix
    ./nix/bpftrace.nix
    ./nix/clblast.nix
    ./nix/default.nix
    ./nix/hyprland.nix
    ./nix/mpv-openvr.nix
    ./nix/multimon-ng.nix

    ./nix/packages-overlay.nix
    ./nix/settings.nix
    ./nix/wb32-dfu-updater.nix
    ./profiles/services.nix
    ./roles/default.nix
    ./roles/homelab.nix
    ./roles/media.nix
    ./roles/monitoring.nix
    ./roles/server.nix
    ./roles/workstation.nix
    ./secrets/pass/default.nix
    ./secrets/pkgs.nix # Nix package manager
    ./secrets/yubikey/default.nix
    ./security/default.nix
    ./security/firejail.nix

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
    ./shell/pkgs.nix # Nix package manager
    ./shell/zsh.nix
    ./system/boot.nix
    ./system/boot/autofdo.nix
    ./system/boot/pkgs.nix # Nix package manager
    ./system/environment.nix
    ./system/filesystems.nix
    ./system/guix.nix
    ./system/irqbalance.nix
    ./system/kernel/default.nix
    ./system/kernel/params.nix
    ./system/kernel/patches-amd.nix
    ./system/kernel/sysctl-mem-extras.nix
    ./system/kernel/sysctl-net-extras.nix
    ./system/kernel/sysctl-writeback.nix
    ./system/kernel/sysctl.nix
    ./system/net/bridge.nix
    ./system/net/default.nix
    ./system/net/nscd.nix
    ./system/net/pkgs.nix # Nix package manager
    ./system/net/proxy.nix
    ./system/net/ssh.nix
    ./system/net/vpn/default.nix
    ./system/net/vpn/pkgs.nix # Nix package manager
    ./system/net/vpn/xray.nix
    ./system/net/wifi.nix
    ./system/oomd.nix
    ./system/pkgs.nix # Nix package manager
    ./system/preserve-flake.nix
    ./system/profiles/aliases.nix
    ./system/profiles/debug.nix
    ./system/profiles/default.nix
    ./system/profiles/performance.nix
    ./system/profiles/security.nix
    ./system/profiles/vm.nix
    ./system/profiles/work.nix
    ./system/swapfile.nix
    ./system/systemd/default.nix
    ./system/systemd/post-boot.nix
    ./system/systemd/timesyncd/default.nix
    ./system/tailscale.nix
    ./system/users.nix
    ./system/virt.nix

    ./system/virt/default.nix

    ./system/winapps.nix
    ./system/zram.nix
    ./text/default.nix
    ./text/manipulate-packages.nix
    ./text/notes-packages.nix
    ./text/read-packages.nix
    ./tools/default.nix
    ./tools/hiddify.nix
    ./tools/pkgs.nix # Nix package manager
    ./torrent/default.nix
    ./user/dbus.nix
    ./user/fonts.nix
    ./user/games/default.nix
    ./user/games/launchers.nix
    ./user/games/performance.nix
    ./user/games/vr.nix
    ./user/gui-packages.nix
    ./user/locale-pkgs.nix # Nix package manager
    ./user/locale.nix
    ./user/locate.nix
    ./user/mail.nix
    ./user/nix-maid/apps

    ./user/nix-maid/cli

    ./user/nix-maid/default.nix
    ./user/nix-maid/fun

    ./user/nix-maid/gui

    ./user/nix-maid/hyprland/main.nix
    ./user/nix-maid/sys

    ./user/nix-maid/web

    ./user/neovim.nix
    ./user/psd/default.nix
    ./user/session/chat.nix
    ./user/session/clipboard.nix
    ./user/session/default.nix
    ./user/session/greetd.nix
    ./user/session/hypr-bindings.nix
    ./user/session/hyprland.nix
    ./user/session/media.nix
    ./user/session/qt.nix
    ./user/session/quickshell.nix
    ./user/session/screenshot.nix
    ./user/session/terminal.nix
    ./user/session/theme.nix
    ./user/session/utils.nix
    ./user/theme-packages.nix
    ./user/wrappers/default.nix
    ./user/xdg.nix
    ./web/default.nix
  ];
}

{
  config,
  lib,
  ...
}:
{
  # Route Hyprland and its portal to the flake-pinned versions
  # Gated behind features.gui.enable to avoid pkgs.hyprland evaluation on headless hosts
  config = lib.mkIf (config.lib.neg.enabled "gui") {
    nixpkgs.overlays = [
      # Hyprland overlays disabled — nixpkgs 0.55.4 is stable and compatible with hyprlock/hypridle
      # inputs.hyprland.overlays.hyprland-packages  # disabled: hyprutils 0.14.0 breaks hyprlock/hypridle
      # inputs.xdg-desktop-portal-hyprland.overlays.default  # disabled: see above
      (final: prev: {
        hyprglass = final.stdenv.mkDerivation {
          # v0.8.1 targets Hyprland 0.56.2 (hyprpm.toml pin) — the 0.55 postPatch
          # that rewrote m_realPosition/m_realSize/m_alpha is obsolete and gone.
          # NOT loaded anywhere: on 2026-09-17 a live `hyprctl plugin load` of this
          # build crashed the compositor twice (SIGABRT with the stack inside
          # libhyprglass.so, +0x5a5cc — see ~/.cache/hyprland/hyprlandCrashReport*.txt);
          # the watchdog then brought Hyprland up in --safe-mode. Re-test in a nested
          # instance before wiring it into the config again.
          pname = "hyprglass";
          version = "0.8.1";
          src = final.fetchFromGitHub {
            owner = "hyprnux";
            repo = "hyprglass";
            rev = "v0.8.1";
            hash = "sha256-yUU0gKu1CXqpUQBtyb3IWNBYZ1bCAm99mfTUV7ceJyg=";
          };

          nativeBuildInputs = with final; [ pkg-config ];
          buildInputs = with final; [
            hyprland
            hyprland.dev
            aquamarine
            hyprutils
            hyprgraphics
            hyprcursor
            hyprlang
            hyprland-protocols
            wayland
            wayland-protocols
            pixman
            libdrm
            libinput
            libGL
            libglvnd
            cairo
            libxkbcommon
            libxcb
            libxcb-util
            libxcb-wm
            libxcb-image
            libxcb-render-util
            libxcb-errors
            glslang
            lua
          ];
          env.PKG_CONFIG_PATH = "${final.hyprland.dev}/share/pkgconfig";

          installPhase = ''
            mkdir -p $out/lib
            cp hyprglass.so $out/lib/
          '';
        };

        hyprlandPlugins = prev.hyprlandPlugins // {
          # hy3 and hyprspace were removed for the nixos-unstable (Hyprland
          # 0.56) migration — their 0.55 CCompositor/monitor API
          # (getMonitorFromCursor/warpCursorTo/m_monitors) no longer compiles
          # against 0.56, which moved monitor access into a State query system
          # and made CCompositor a small class. Re-port them before re-exporting.
        };
      })
    ];
  };
}

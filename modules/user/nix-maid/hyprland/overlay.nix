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
          # Layered backdrop freshness. Two defects in 0.8.1, both measured in a
          # nested 0.56.2 (see the patch header): the layer namespace filters are
          # parsed once at load, when the settings this session pushes (the keys
          # only exist after the plugin registered them) are still absent — an
          # empty whitelist means "glass every layer", so the shell's bar and
          # media card were glassed with the plugin's *cached* backdrop instead of
          # Hyprland's live layer blur, and stayed frozen on the wallpaper of the
          # moment the sample was taken (only re-mapping the surface, with its
          # slide animation, forced a re-sample); and that cache is invalidated
          # only by window events, never by a commit below the glass — a wallpaper
          # switch is exactly such a commit. The patch re-parses the filters when
          # the raw values change and invalidates a layer's cache on any commit
          # that touches its sample region (the re-sample itself stays rate
          # limited by layers.live_resample_fps).
          patches = [ ./hyprglass-layer-backdrop-live.patch ];
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
          # HyprExpo: upstream retired the plugin from hyprwm/hyprland-plugins
          # (hence no nixpkgs attr), sandwichfarm's fork continues it and pins
          # 0.56.2 at commit 5891014c (see its hyprpm.toml). Built with the
          # nixpkgs helper so it links against the same Hyprland as the session;
          # the .so is dlopen'd by hyprexpo-setup at session start (see main.nix).
          hyprexpo = final.hyprlandPlugins.mkHyprlandPlugin {
            pluginName = "hyprexpo";
            version = "0-unstable-2026-09-18";

            # The overview must be the workspace *grid* here, not upstream's scrolling
            # overview: upstream picks by layout — `createOverviewSession()` sends every
            # workspace whose layout is Hyprland's native `scrolling` (our workspace rules
            # set it for most workspaces) to `CScrollingOverview`, a strip of that
            # workspace's columns, and everything else to `COverview`, the grid. The patch
            # adds `plugin:hyprexpo:grid_overview` (default 1) which forces the grid for
            # scrolling workspaces too; the layout itself stays untouched.
            #
            # The second patch (hyprexpo-click-swallow.patch) drops the orphan mouse
            # release of the click that *opened* the overview: the panel capsule
            # toggles on the press, and the release (pointer still over the bar)
            # arrived as a workspace choice — the overview opened and closed within
            # one gesture. Releases in the first 400 ms of a session are ignored;
            # the plugin's own 5% entry guard is too narrow to catch this.
            #
            # Order matters only in that both are plain unified diffs against the
            # same upstream files (grid_overview touches IOverviewSession.cpp,
            # HyprexpoConfig.hpp and PluginConfig.cpp; click-swallow touches
            # Overview.cpp).
            patches = [
              ./hyprexpo-grid-overview.patch
              ./hyprexpo-click-swallow.patch
            ];

            src = final.fetchFromGitHub {
              owner = "sandwichfarm";
              repo = "hyprexpo";
              rev = "5891014c611e1bd56d0121143f0221d46b5c0967";
              hash = "sha256-86gJ8YixG+FeEcnkGHc0O3eCemoDLe9/cOa21VZKdQM=";
            };
            dontUseCmakeConfigure = true;
            # The Makefile links lua through pkg-config (lua5.4, falls back to lua).
            # pkg-config finds it only if the dev output is on PKG_CONFIG_PATH.
            buildInputs = [ final.lua5_4 ];
            env.PKG_CONFIG_PATH = "${final.hyprland.dev}/share/pkgconfig";

            installPhase = ''
              runHook preInstall

              mkdir -p $out/lib
              mv hyprexpo.so $out/lib/libhyprexpo.so

              runHook postInstall
            '';

            meta = {
              homepage = "https://github.com/sandwichfarm/hyprexpo";
              description = "Expose-style workspace overview for Hyprland";
              license = final.lib.licenses.bsd3;
              platforms = final.lib.platforms.linux;
            };
          };

          # HyprWindowShade: per-window, per-layer and per-class fragment shaders
          # (HyprShade-compatible GLSL ES 3.20). Upstream ships a Makefile for hyprpm;
          # the rev is the commit its hyprpm.toml pins for the Hyprland commit we run
          # (efb50993780079460b0cbed1363e2166a2de1d9f = 0.56.2), so the plugin and the
          # compositor stay in one commit family. The .so is dlopen'd by the generated
          # hyprwindowshade-setup helper at session start (see main.nix).
          hyprwindowshade = final.hyprlandPlugins.mkHyprlandPlugin {
            pluginName = "hyprwindowshade";
            version = "0-unstable-2026-09-19";

            src = final.fetchFromGitHub {
              owner = "ManofJELLO";
              repo = "HyprWindowShade";
              rev = "a4c6b8af424a189072427c4c90ef2938e1b481d3";
              hash = "sha256-hFs3AVnH6j9ZnDzfG19pAL9cO+pVl21pT9q9A1c6DNw=";
            };

            dontUseCmakeConfigure = true;
            # The Makefile asks pkg-config for Hyprland's flags and links
            # GLES/EGL/GL, which libglvnd provides.
            buildInputs = [ final.libglvnd ];
            env.PKG_CONFIG_PATH = "${final.hyprland.dev}/share/pkgconfig";

            installPhase = ''
              runHook preInstall

              mkdir -p $out/lib
              mv HyprWindowShade.so $out/lib/libHyprWindowShade.so

              runHook postInstall
            '';

            meta = {
              homepage = "https://github.com/ManofJELLO/HyprWindowShade";
              description = "Per-window, per-layer and per-class fragment shaders for Hyprland";
              license = final.lib.licenses.mit;
              platforms = final.lib.platforms.linux;
            };
          };
        };
      })
    ];
  };
}

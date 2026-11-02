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
        # No glass plugin on purpose: 0.57 ships blur materials natively
        # (decoration:blur:variant — frost, acrylic, prism, haze, aurora, drops,
        # water, ripple, heat_shimmer, fluid_jar in src/render/gl/blur/), applied
        # globally. hyprliquid was never ported past 0.56 (`IHyprRenderer::
        # m_renderData` went with the rewritten renderer), and per-window shaders
        # still come from HyprWindowShade.

        hyprlandPlugins =
          let
            defined = prev.hyprlandPlugins // {
              # hy3: nixpkgs' own 0.56.0.1 build (upstream tag hl0.56.0.1, built by
              # mkHyprlandPlugin against the same Hyprland 0.56.2 commit as the session
              # compositor) plus one local patch, hy3-detach-float.patch: ion3-style
              # detach — the focused node (a window, or the tab group it lives in) can
              # float above the layout while keeping its slot in it, so the neighbours
              # do not reflow and reattaching returns it to exactly the same box. The
              # patch adds the `hy3:detach` dispatcher and the `hy3.detach` Lua factory;
              # the .so is loaded by hy3-setup (main.nix) as before, and the keys live in
              # files/gui/hypr/hyprland.lua (M4+SHIFT+F, D in the tiling submap).
              hy3 = prev.hyprlandPlugins.hy3.overrideAttrs (old: {
                # The tag follows the compositor: nixpkgs still pinned hl0.56.0.1 after the
                # 0.57 bump, and a plugin is ABI-bound to the Hyprland it was built against,
                # so the source is named here instead. hl0.57.0 is upstream's own tag for
                # 0.57; the local patch below is a plain unified diff against `src/` and is
                # rebased onto it when it stops applying.
                version = "0.57.0";
                src = final.fetchFromGitHub {
                  owner = "outfoxxed";
                  repo = "hy3";
                  rev = "4c0199b42967b3511e3520b75cfa1f6411fb7e87"; # tag hl0.57.0
                  hash = "sha256-9qAw3Xsa0xN9b5ERiWEGL1fBq37GLskcrBj/6ax8PU4=";
                };
                patches = (old.patches or [ ]) ++ [ ./hy3-detach-float.patch ];
              });

              # hyprspace stays dropped — its 0.55 CCompositor/monitor API (getMonitorFromCursor/
              # warpCursorTo/m_monitors) no longer compiles against 0.56, which
              # moved monitor access into a State query system and made
              # CCompositor a small class. Re-port it before re-exporting.
              # HyprExpo: upstream retired the plugin from hyprwm/hyprland-plugins
              # (hence no nixpkgs attr), sandwichfarm's fork continues it and its
              # v0.57.0 release targets Hyprland 0.57.0 — the commit this nixpkgs
              # pins. Built with the nixpkgs helper so it links against the same
              # Hyprland as the session; the .so is dlopen'd by hyprexpo-setup at
              # session start (see main.nix).
              hyprexpo = prev.hyprlandPlugins.mkHyprlandPlugin {
                pluginName = "hyprexpo";
                version = "0.57.0";

                # One local patch is left: hyprexpo-click-swallow.patch drops the
                # orphan mouse release of the click that *opened* the overview —
                # the panel capsule toggles on the press, and the release (pointer
                # still over the bar) arrived as a workspace choice, so the
                # overview opened and closed within one gesture. The plugin's own
                # 5% entry guard is too narrow to catch this.
                #
                # 0.57.0 upstreams the grid switch that used to be a second patch:
                # `plugin:hyprexpo:overview_mode = "grid"` (set in
                # files/gui/hypr/hyprexpo.lua) forces the classic grid for
                # workspaces with the native scrolling layout, which `auto` would
                # open as a strip of columns.
                patches = [ ./hyprexpo-click-swallow.patch ];

                src = final.fetchFromGitHub {
                  owner = "sandwichfarm";
                  repo = "hyprexpo";
                  rev = "3ec4d82e52f0d4765b87f6ef14f1883a44e85e27";
                  hash = "sha256-xhu3Un8dUIJSYv/gqQUlP74SkbQgewhv1tgllBcheAQ=";
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

              # GloView: macOS Mission-Control-style overview — live previews of
              # every window plus a workspace strip. Upstream ships CMake + hyprpm
              # and pins Hyprland v0.57.0 in its own flake; the rev below is main as
              # of 2026-10-31, the "Port to Hyprland 0.57" commit (no release tag,
              # and its hyprpm.toml pins 0.56 only), so the plugin is built here
              # against the same nixpkgs Hyprland the session runs. CMake pkg-configs
              # hyprland + glesv2 (libglvnd, already in Hyprland's buildInputs) and
              # searches for a Lua module named lua/lua5.4/luajit; nixpkgs' lua5_5
              # installs the generic lua.pc, so putting lua5_5 first links the
              # interpreter Hyprland itself runs.
              # The .so is dlopen'd by the generated gloview-setup helper at session
              # start (see main.nix).
              gloview = prev.hyprlandPlugins.mkHyprlandPlugin {
                pluginName = "gloview";
                version = "0-unstable-2026-10-31";

                src = final.fetchFromGitHub {
                  owner = "fedsfarm";
                  repo = "gloview";
                  rev = "67857e6f8b715d6d100068ef89ba554c8fecb918";
                  hash = "sha256-M6LBP59p9v241hQ5vSmk6gjhKQavTrImNOGy+HpWwSo=";
                };

                nativeBuildInputs = [ final.cmake ];
                # glib: CMake asks pkg-config for pangocairo, which pulls glib, whose
                # `.pc` names its own private deps (`sysprof-capture-4`, `libpcre2-8`,
                # …). Those resolve through the wrapper's path only when glib itself is
                # an input, so it is named here instead of chasing each dep by hand.
                buildInputs = [
                  final.lua5_5
                  final.glib
                ];
                # Appended, not assigned: an assignment here *replaces* the search path
                # the pkg-config wrapper builds from `buildInputs`, which is what made
                # glib's dependencies unfindable on the 2026-10-30 nixpkgs. Hyprland
                # keeps its `.pc` in `share/pkgconfig`, which is why the path is needed
                # at all.
                preConfigure = ''
                  export PKG_CONFIG_PATH="${final.hyprland.dev}/share/pkgconfig:''${PKG_CONFIG_PATH:-}"
                '';

                meta = {
                  homepage = "https://github.com/fedsfarm/gloview";
                  description = "macOS Mission Control-style window overview for Hyprland";
                  license = final.lib.licenses.gpl3Plus;
                  platforms = final.lib.platforms.linux;
                };
              };

              # Hymission: Mission-Control-style overview — live compositor-side
              # previews of every window, workspace strip, Stage mode, trackpad
              # gestures and a search box. Upstream ships CMake + a hyprpm manifest;
              # its v0.12.1-v0.57.0 release targets Hyprland 0.57.0 (the commit this
              # nixpkgs pins), so plugin and compositor stay in one commit family.
              # Built with the nixpkgs helper against the session's Hyprland. Two
              # artifacts: the plugin module, and the search helper the plugin
              # posix_spawns — it resolves `hymission-search-input` next to its own
              # .so first (src/overview_controller.cpp), so the helper is installed
              # into $out/lib beside libhymission.so instead of upstream's install()
              # libexec dir. Review note: the pinned tree has no network or shell
              # calls; the only spawn is that helper.
              # The .so is dlopen'd by the generated hymission-setup helper at
              # session start (see main.nix): PLUGIN_INIT registers the
              # plugin.hymission.* keys and reloads the config, which must not
              # happen while hyprland.lua is still being parsed.
              hymission = prev.hyprlandPlugins.mkHyprlandPlugin {
                pluginName = "hymission";
                version = "0.12.1";

                src = final.fetchFromGitHub {
                  owner = "gfhdhytghd";
                  repo = "hymission";
                  rev = "d4b2f91f9dc6018154a35d14a79d7bda098f6b08";
                  hash = "sha256-y3tu1fEDlEDQRlvtr3vcZnE+RJRU2DuGDHr+GoZ7QxI=";
                };
                # 0.57's hyprctl command API (`IPC::Socket1::SCommand`,
                # `(const SRequest&) -> SResponse`) is upstream since 0.12.1, so the
                # local hymission-ipc-s1.patch is gone.

                # The helper's own nativeBuildInputs (cmake, pkg-config) do not
                # survive an override, and without cmake in nativeBuildInputs its
                # setup hook never claims configurePhase (the build then falls back
                # to "no configure script, doing nothing").
                nativeBuildInputs = [
                  final.cmake
                  final.pkg-config
                ];
                # CMake pkg-configs hyprland and lua for the plugin (both arrive
                # through mkHyprlandPlugin's hyprland.buildInputs; lua5_5 is the
                # interpreter Hyprland itself links) plus glib-2.0, and the search
                # helper additionally needs the GTK4 stack.
                buildInputs = [
                  final.glib
                  final.gtk4
                  final.libadwaita
                  final.gtk4-layer-shell
                ];
                env.PKG_CONFIG_PATH = "${final.hyprland.dev}/share/pkgconfig";
                # The CTest suite (13 cases, several of them LD_PRELOADed against
                # the Hyprland binary) is a development target; skip it here.
                cmakeFlags = [ "-DBUILD_TESTING=OFF" ];

                # libhymission.so lands in $out/lib through the default phases
                # (install(TARGETS … LIBRARY)), the helper follows it there.
                postInstall = ''
                  install -Dm755 hymission-search-input $out/lib/hymission-search-input
                '';

                meta = {
                  homepage = "https://github.com/gfhdhytghd/hymission";
                  description = "Mission Control-style window overview for Hyprland";
                  license = final.lib.licenses.gpl3Only;
                  platforms = final.lib.platforms.linux;
                };
              };

              # HyprCapture: the compositor half of a screenshot/recording overlay
              # (frozen-compositor artifacts, region/window/scrolling capture,
              # annotation, pinning, recording with sound). Upstream ships
              # nix/package.nix for its own flake, and the release tag names the
              # Hyprland ABI it was cut for — v0.6.0-v0.57.0 is exactly the 0.57.0
              # this nixpkgs ships. The recipe is evaluated from the pinned checkout
              # (its ../cmake and ./aec-sources.json references resolve in the
              # store), so upstream stays the single source of truth for the build:
              # it also builds the private gain-map HEIC codec (libultrahdr +
              # patched libheif), the DTLN TFLite AEC runtime and the pinned models,
              # and embeds $out/bin/hyprcapture-ui as the helper path through
              # builtins.placeholder — the plugin never resolves its helper through
              # PATH. lua5_5 is the interpreter the session's Hyprland links (the
              # unversioned `lua` alias does not survive allowAliases=false). The
              # .so is dlopen'd by the generated hyprcapture-setup helper from the
              # session-target unit (see main.nix), not from hyprland.lua: the
              # plugin reloads the config in PLUGIN_INIT, which must not happen
              # while that file is still being parsed.
              hyprcapture =
                let
                  hyprcaptureSrc = final.fetchFromGitHub {
                    owner = "gfhdhytghd";
                    repo = "HyprCapture";
                    rev = "v0.6.0-v0.57.0";
                    hash = "sha256-M3YB76XNiuN37ARgicl5ImEhiRHgNvxWu9OtxyhunsI=";
                  };
                in
                final.callPackage "${hyprcaptureSrc}/nix/package.nix" {
                  src = hyprcaptureSrc;
                  lua = final.lua5_5;
                  # The overlay below narrows `hyprlandPlugins` to the ported set
                  # via intersectAttrs, so the helper lives only in the previous
                  # set (same reason as the direct mkHyprlandPlugin calls above).
                  hyprlandPlugins = prev.hyprlandPlugins;
                };

              # HyprWindowShade: per-window, per-layer and per-class fragment shaders
              # (HyprShade-compatible GLSL ES 3.20). Upstream ships a Makefile for
              # hyprpm; v0.26 is the release for Hyprland 0.57 (the new window header
              # and the metadata()/isFloating() accessors are already in it), so the
              # plugin and the compositor stay in one commit family. The .so is
              # dlopen'd by the generated hyprwindowshade-setup helper at session
              # start (see main.nix).
              hyprwindowshade = prev.hyprlandPlugins.mkHyprlandPlugin {
                pluginName = "hyprwindowshade";
                version = "0.26";

                src = final.fetchFromGitHub {
                  owner = "ManofJELLO";
                  repo = "HyprWindowShade";
                  rev = "b62fc3d8d04514d7b51e61c281a34231b04e95e3";
                  hash = "sha256-IMAQ6HYmhdSNQhQWSFFnTRYEbOdUPADun6Ecr027PTw=";
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

              # Hyprwinwrap: any window (mpv, a browser, a shader canvas) pinned as a
              # background layer behind the desktop. Upstream is a hyprpm plugin; the
              # rev is the commit its hyprpm.toml pins for Hyprland 0.56.2, the same
              # commit family as the rest of this overlay, so plugin and compositor
              # stay in step. hyprpm builds it with CMake and `install(TARGETS)`
              # drops libhyprwinwrap.so into $out/lib, so the default phases work.
              # The .so is dlopen'd by the generated hyprwinwrap-setup helper at
              # session start (see main.nix); the background-window declarations in
              # files/gui/hypr/hyprwinwrap.lua are pushed through `hyprctl eval`,
              # because a plugin cannot be loaded while hyprland.lua is parsed.
              # One local patch (hyprwinwrap-lua-window-merge.patch): upstream's
              # luaWindow() only appends to gLuaSpecs and leaves the merge to the
              # config.reloaded event, which a runtime `hyprctl eval` never fires —
              # and a reload would clear the list in its config.preReload handler
              # before merging. The patch merges immediately, which is what makes
              # the eval push take effect at all. Verified in a nested 0.56.2
              # instance: after the patch a window matching the pushed class is
              # adopted as a full-screen background window.
              hyprwinwrap = prev.hyprlandPlugins.mkHyprlandPlugin {
                pluginName = "hyprwinwrap";
                version = "0-unstable-2026-09-10";

                src = final.fetchFromGitHub {
                  owner = "gen3vra";
                  repo = "hyprwinwrap";
                  rev = "3b6e337b9ee934ee23179d1445cb8cacfc38af28";
                  hash = "sha256-J3dFF2ibY+SjYoSm2JnBrBu9riVbycQ1q39xnYlNUjM=";
                };

                patches = [ ./hyprwinwrap-lua-window-merge.patch ];
                # 0.57 moved the window header one directory down
                # (`desktop/view/Window.hpp` -> `desktop/view/window/Window.hpp`); every
                # other include this plugin uses still resolves. Kept as a substitution
                # rather than a patch file: it is one string.
                postPatch = ''
                  substituteInPlace main.cpp \
                    --replace-fail "hyprland/src/desktop/view/Window.hpp" \
                                   "hyprland/src/desktop/view/window/Window.hpp"
                '';

                nativeBuildInputs = [ final.cmake ];
                # The CMakeLists asks pkg-config for hyprland, libdrm, libinput,
                # libudev, pangocairo, pixman-1, wayland-server and xkbcommon; all of
                # those (and their .pc files) arrive through mkHyprlandPlugin's
                # hyprland.buildInputs. Only the Lua headers need an explicit input:
                # lua5_5 is the interpreter Hyprland itself links, and its lua55.pc
                # is what the plugin's pkg_search_module(lua55 …) matches.
                # glib: CMake asks pkg-config for pangocairo, which pulls glib, whose
                # `.pc` names its own private deps (`sysprof-capture-4`, `libpcre2-8`,
                # …). Those resolve through the wrapper's path only when glib itself is
                # an input, so it is named here instead of chasing each dep by hand.
                buildInputs = [
                  final.lua5_5
                  final.glib
                ];
                # Appended, not assigned: an assignment here *replaces* the search path
                # the pkg-config wrapper builds from `buildInputs`, which is what made
                # glib's dependencies unfindable on the 2026-10-30 nixpkgs. Hyprland
                # keeps its `.pc` in `share/pkgconfig`, which is why the path is needed
                # at all.
                preConfigure = ''
                  export PKG_CONFIG_PATH="${final.hyprland.dev}/share/pkgconfig:''${PKG_CONFIG_PATH:-}"
                '';

                meta = {
                  homepage = "https://github.com/gen3vra/hyprwinwrap";
                  description = "Display any window as a background wallpaper in Hyprland";
                  license = final.lib.licenses.bsd3;
                  platforms = final.lib.platforms.linux;
                };
              };

              # HyprDynamicCursors: stretch/tilt/rotate cursor effects plus shake
              # to find. nixpkgs pins 0-unstable-2026-07-21, which predates
              # Hyprland 0.56.2: renderSoftwareCursorsFor gained a `screencopy`
              # bool before `forceRender`, so the plugin's hardcoded
              # mangled-signature check rejected the load ("unexpected function
              # signature") and the hook handler forwarded one bool too few. The
              # local patch updates the typedef, handler and signature string to
              # the 0.56.2 arity; everything else in the plugin compiles against
              # the same headers it is built with. The .so is dlopen'd by the
              # generated hyprdynamiccursors-setup helper at session start (see
              # main.nix).
              "hypr-dynamic-cursors" = prev.hyprlandPlugins."hypr-dynamic-cursors".overrideAttrs (old: {
                patches = (old.patches or [ ]) ++ [ ./hypr-dynamic-cursors-hyprland-056-signature.patch ];
              });
            };

            # Plugins that build against Hyprland 0.57. Everything else is a stub until
            # it is ported: the loader scripts run `hyprctl plugin load … || true`, so a
            # missing `.so` costs one line in the session log instead of a broken login.
            # Still stubbed: hyprwinwrap (upstream never moved off 0.56 and the window
            # fields sit behind accessors now) and hypr-dynamic-cursors (builds against
            # 0.57, but upstream SIGSEGV #170 in tilt/stretch/shake is unfixed and the
            # effect is off in the config).
            ported = [
              "hy3"
              "hyprexpo"
              "gloview"
              "hymission"
              "hyprcapture"
              "hyprwindowshade"
            ];
            unported = [
              "hyprwinwrap"
              "hypr-dynamic-cursors"
            ];
          in
          builtins.intersectAttrs (final.lib.genAttrs ported (_: null)) defined
          // final.lib.genAttrs unported (
            name: final.runCommand "${name}-not-ported-to-0.57" { } "mkdir -p $out/lib"
          );
      })
    ];
  };
}

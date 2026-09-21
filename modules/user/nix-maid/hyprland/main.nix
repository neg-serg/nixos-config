{
  pkgs,
  lib,
  config,
  neg,
  inputs ? null,
  ...
}:
let
  guiEnabled = config.lib.neg.enabled "gui";

  environment = import ./environment.nix { inherit lib pkgs; };
  services = import ./services.nix { inherit lib pkgs inputs; };
  files = import ./files.nix { inherit lib neg config; };

  # hy3 and hyprspace were removed for the nixos-unstable (Hyprland 0.56)
  # migration (their 0.55 CCompositor/monitor API no longer compiles).
  # hyprland.lua no longer contains @HY3@/@HYPRSPACE@ placeholders, so no
  # store-path injection is needed.
  # hyprglass has to be loaded before its config keys exist, and a plugin cannot be
  # dlopen'd while hyprland.lua is still being parsed — so the .so is loaded from the
  # session-start hook and the settings (files/gui/hypr/hyprglass.lua, plain config
  # keys, NOT the plugin's Lua API: that path aborts the compositor) are pushed
  # through `hyprctl eval`. builtins.replaceStrings (not pkgs.replaceVars): files.nix
  # assigns the lua text to a home-file `.text` entry, which must be a string.
  hyprglassSetup = pkgs.writeShellScriptBin "hyprglass-setup" ''
    hyprctl_bin=${lib.getExe' pkgs.hyprland "hyprctl"}

    # Already loaded (e.g. the hook re-ran) → the load fails, that is fine
    "$hyprctl_bin" plugin load ${pkgs.hyprglass}/lib/hyprglass.so || true

    # hyprctl eval takes the code as one argument and reads a leading "--" (Lua
    # comment) as a flag, hence the leading newline.
    "$hyprctl_bin" eval "
    $(cat ${pkgs.writeText "hyprglass.lua" (builtins.readFile (config.lib.neg.path "files/gui/hypr/hyprglass.lua"))})" || true

    # The session's Hyprland socket signature is what hyprctl needs, and systemd's
    # user environment does not have it: without this the glass watchdog (and any
    # other user service calling hyprctl) can never reach the compositor and just
    # reports failure forever. Imported at session start, it is there for every
    # service of this session.
    systemctl --user import-environment HYPRLAND_INSTANCE_SIGNATURE XDG_RUNTIME_DIR >/dev/null 2>&1 || true

    # Then the real thing: the deployed base plus the values the Glass panel keeps
    # in ~/.config/hypr/hyprglass.json, and it checks that they landed. The eval
    # above is the fallback for the case where the deployed file is not there yet
    # (the activation order is not guaranteed).
    hyprglass-apply >/dev/null 2>&1 || true
  '';

  # HyprExpo (workspace overview). `hypr-expo` is the one entry point for the panel
  # capsule click, the panel IPC and the SUPER+grave bind: evaluating a plugin
  # namespace that is not registered answers "ok" and does nothing, so the toggle
  # loads (and configures) the plugin itself whenever it is missing. That case is
  # real — the plugin is otherwise loaded only by the session-start hook, and a
  # session that parsed the deployed hyprland.lua while its baked-in
  # hyprexpo-setup path was already gone (an older generation, a GC run) comes up
  # with no hyprexpo at all, which made the capsule click look wired while the
  # overview never appeared.
  #
  # `hypr-expo select` is the third mode: the fork does not read mouse buttons on
  # its own, it only inspects the tile under the pointer when the `select` action is
  # invoked, so hyprland.lua binds the left button to it. That mode never loads the
  # plugin (a plain click must not pull one in) — while the overview is closed the
  # action is a no-op, which is what makes the bind safe.
  #
  # hyprexpo-setup keeps its load-then-push semantics (the .so is dlopen'd first,
  # then files/gui/hypr/hyprexpo.lua is pushed through `hyprctl eval`; re-runnable
  # in a live session to re-apply the file) and is now a thin wrapper over the same
  # script. Both go through hyprctl eval rather than a dispatch for the same
  # reason: the plugin is dlopen'd *after* hyprland.lua is parsed, so
  # hl.plugin.hyprexpo is nil while that file is read, and in Lua config mode
  # `hyprctl dispatch hyprexpo:expo toggle` only mangles the name into
  # `hl.dispatch(hyprexpo:expo toggle)` and dies with "expected a dispatcher"
  # (reproduced in a nested 0.56.2 instance; see docs/howto/hyprland-plugin.md).
  hyprExpoLua = pkgs.writeText "hyprexpo.lua" (
    builtins.readFile (config.lib.neg.path "files/gui/hypr/hyprexpo.lua")
  );
  hyprExpo = pkgs.writeShellScriptBin "hypr-expo" ''
    set -u
    hyprctl_bin=${lib.getExe' pkgs.hyprland "hyprctl"}
    plugin=${pkgs.hyprlandPlugins.hyprexpo}/lib/libhyprexpo.so

    plugin_loaded() {
      "$hyprctl_bin" plugin list 2> /dev/null | grep -q "^Plugin hyprexpo "
    }

    # hyprctl eval takes the code as one argument and reads a leading "--" (Lua
    # comment) as a flag, hence the leading newline.
    push_config() {
      "$hyprctl_bin" eval "
    $(cat ${hyprExpoLua})" || true
    }

    case "''${1:-toggle}" in
      toggle)
        # One physical click can arrive as two toggles (the capsule activates on
        # press while its row also emits a tap): the overview then starts its entry
        # animation and closes again in the same instant — "it starts and stops
        # immediately". Swallow a second toggle that lands within 250 ms of the
        # previous one; that covers the click, the panel IPC entry point and the
        # compositor bind alike, since all three go through this script.
        stamp="''${XDG_RUNTIME_DIR:-/tmp}/hypr-expo-last-toggle"
        now_ms=$(date +%s%3N)
        if [ -r "$stamp" ]; then
          prev_ms=$(cat "$stamp" 2> /dev/null || echo 0)
          [ "$((now_ms - prev_ms))" -lt 250 ] && exit 0
        fi
        printf '%s' "$now_ms" > "$stamp"

        # A missing plugin is loaded and configured here instead of being reported
        # as a successful toggle: without the load the eval below is a no-op.
        if ! plugin_loaded; then
          "$hyprctl_bin" plugin load "$plugin" > /dev/null 2>&1 || exit 1
        fi
        # ...and the config is pushed on *every* toggle, not only after a load.
        # This helper is the only thing that configures the plugin, so a session
        # that re-initialised it — a compositor reload, a build swapped in for
        # testing — otherwise opens the overview with the plugin's defaults: the
        # workspace capsule then looks nothing like the overview a manual
        # `hypr-expo toggle` gives after a push (the reported "dull mess"). One
        # eval of hyprexpo.lua is cheap enough to do per click.
        push_config
        "$hyprctl_bin" eval 'hl.plugin.hyprexpo.expo("toggle")'
        ;;
      push)
        # Session start and live re-configuration: load (the load of an already
        # loaded plugin fails, that is fine), then push the keys even when the
        # plugin was already there, so an edited hyprexpo.lua takes effect.
        "$hyprctl_bin" plugin load "$plugin" > /dev/null 2>&1 || true
        push_config
        ;;
      select)
        # Bound to the left button in hyprland.lua: the fork does not read mouse
        # buttons itself, it only looks at the pointer when this action is invoked.
        # Deliberately no plugin load here — a plain click must not pull the plugin
        # in (and the action is a no-op while the overview is closed, so the bind
        # can sit on the plain button).
        #
        # A click that lands on the bar belongs to the shell: the workspace capsule
        # toggles the overview, and a tile under the bar's position is not what the
        # pointer is aiming at. Without this split the click both closed the
        # overview (through the capsule) and jumped to the tile sitting under the
        # bar — reported as "it switches me to dev again".
        cursor_xy="$("$hyprctl_bin" cursorpos 2> /dev/null | tr -d ' ')"
        cursor_x="''${cursor_xy%%,*}"
        cursor_y="''${cursor_xy##*,}"
        # Panel band, in the compositor's own logical coordinates. The old test
        # compared cursorpos (LOGICAL: 1080 tall here) against hyprctl monitors
        # .height (PHYSICAL: 2160) and therefore never fired — the capsule click
        # kept selecting the tile under the bar. Take the shell's layer boxes
        # instead: they are logical and correct for a top or a bottom bar.
        panel_boxes="$("$hyprctl_bin" -j layers 2> /dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for monitor in (data.values() if isinstance(data, dict) else []):
    for level in (monitor.get("levels") or {}).values():
        for layer in level:
            ns = layer.get("namespace") or ""
            if ns.startswith("qs-") or ns.startswith("quickshell"):
                print(layer["x"], layer["y"], layer["x"] + layer["w"], layer["y"] + layer["h"])
' 2> /dev/null || true)"
        printf '%s select cursor=%s,%s panels=[%s]\n' "$(date +%T)" "''${cursor_x:-?}" "''${cursor_y:-?}" "$(printf '%s' "$panel_boxes" | tr '\n' ';')" >> /tmp/hypr-expo-select.log 2> /dev/null || true
        in_panel=0
        if [ -n "''${cursor_x:-}" ] && [ -n "''${cursor_y:-}" ]; then
          while read -r x0 y0 x1 y1; do
            [ -n "''${x0:-}" ] || continue
            if [ "$cursor_x" -ge "$x0" ] && [ "$cursor_x" -le "$x1" ] && [ "$cursor_y" -ge "$y0" ] && [ "$cursor_y" -le "$y1" ]; then
              in_panel=1
              break
            fi
          done <<< "$panel_boxes"
        fi
        # Safety net for the case where the layer query came back empty: the bar is
        # 25 logical pixels tall on a 1080-tall screen, so anything inside the last
        # 40 logical pixels belongs to the shell. Derive that from physical height
        # and scale when the boxes are missing.
        if [ "$in_panel" -eq 0 ] && [ -z "$panel_boxes" ] && [ -n "''${cursor_y:-}" ]; then
          monitor_logical_h="$("$hyprctl_bin" -j monitors 2> /dev/null | python3 -c '
import json, sys
try:
    monitors = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if monitors:
    scale = monitors[0].get("scale") or 1
    print(int(monitors[0]["height"] / scale))
' 2> /dev/null || true)"
          if [ -n "$monitor_logical_h" ] && [ "$cursor_y" -ge "$((monitor_logical_h - 40))" ]; then
            in_panel=1
          fi
        fi
        if [ "$in_panel" -eq 1 ]; then
          # Bar zone: never pick a tile here. The click belongs to the shell (the
          # workspace capsule toggles the overview); the plugin stays out of it.
          exit 0
        fi
        "$hyprctl_bin" eval 'hl.plugin.hyprexpo.expo("select")'
        ;;
      *)
        echo "usage: hypr-expo [toggle|push|select]" >&2
        exit 2
        ;;
    esac
  '';
  hyprexpoSetup = pkgs.writeShellScriptBin "hyprexpo-setup" ''
    exec ${hyprExpo}/bin/hypr-expo push
  '';

  # HyprWindowShade: same load-then-push pattern as hyprglass/hyprexpo. Its actions
  # are only surfaced through hl.plugin.HyprWindowShade.* after the .so is loaded,
  # so the rules in files/gui/hypr/hyprwindowshade.lua are pushed with hyprctl eval.
  hyprwindowshadeSetup = pkgs.writeShellScriptBin "hyprwindowshade-setup" ''
    hyprctl_bin=${lib.getExe' pkgs.hyprland "hyprctl"}

    # Already loaded (e.g. the hook re-ran) → the load fails, that is fine
    "$hyprctl_bin" plugin load ${pkgs.hyprlandPlugins.hyprwindowshade}/lib/libHyprWindowShade.so || true

    # hyprctl eval takes the code as one argument and reads a leading "--" (Lua
    # comment) as a flag, hence the leading newline.
    "$hyprctl_bin" eval "
    $(cat ${pkgs.writeText "hyprwindowshade.lua" (builtins.readFile (config.lib.neg.path "files/gui/hypr/hyprwindowshade.lua"))})" || true
  '';
  hyprlandLuaText =
    builtins.replaceStrings
      [ "@hyprglass_setup@" "@hyprexpo_setup@" "@hyprwindowshade_setup@" ]
      [
        "${hyprglassSetup}/bin/hyprglass-setup"
        "${hyprexpoSetup}/bin/hyprexpo-setup"
        "${hyprwindowshadeSetup}/bin/hyprwindowshade-setup"
      ]
      (builtins.readFile (config.lib.neg.path "files/gui/hypr/hyprland.lua"));
in
{
  # System-level Hyprland pieces (hyprglass overlay) — consolidated here from
  # the old `modules/nix` Hyprland module so the whole compositor stack lives in
  # one domain.
  imports = [ ./overlay.nix ];

  config = lib.mkIf guiEnabled (
    lib.mkMerge [
      {
        # hyprglass-setup is in PATH as well, so the glass can be (re)applied in a
        # running session without logging out (the start hook only fires on start).
        environment.systemPackages = services.packages ++ [
          hyprglassSetup
          hyprexpoSetup
          hyprwindowshadeSetup
          hyprExpo # `hypr-expo toggle|push`: loads the overview plugin on demand
        ];

        systemd.user.targets = services.systemdTargets;
        systemd.user.services = services.systemdServices;
      }

      (files.generateFileLinks {
        hyprlandConfText = environment.hyprlandConf;
        inherit hyprlandLuaText;
      })
    ]
  );
}

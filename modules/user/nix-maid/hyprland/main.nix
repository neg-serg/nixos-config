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

  # HyprExpo follows the same load-then-push pattern as hyprglass: the .so is
  # dlopen'd first, then the plugin's registered config keys are pushed with
  # `hyprctl eval` (files/gui/hypr/hyprexpo.lua). The bind in hyprland.lua uses
  # `hyprctl dispatch hyprexpo:expo toggle` instead of hl.plugin.hyprexpo.* —
  # the plugin is not loaded while hyprland.lua is parsed, so the Lua namespace
  # is nil at that point.
  hyprexpoSetup = pkgs.writeShellScriptBin "hyprexpo-setup" ''
    hyprctl_bin=${lib.getExe' pkgs.hyprland "hyprctl"}

    # Already loaded (e.g. the hook re-ran) → the load fails, that is fine
    "$hyprctl_bin" plugin load ${pkgs.hyprlandPlugins.hyprexpo}/lib/libhyprexpo.so || true

    # hyprctl eval takes the code as one argument and reads a leading "--" (Lua
    # comment) as a flag, hence the leading newline.
    "$hyprctl_bin" eval "
    $(cat ${pkgs.writeText "hyprexpo.lua" (builtins.readFile (config.lib.neg.path "files/gui/hypr/hyprexpo.lua"))})" || true
  '';
  hyprlandLuaText =
    builtins.replaceStrings
      [ "@hyprglass_setup@" "@hyprexpo_setup@" ]
      [ "${hyprglassSetup}/bin/hyprglass-setup" "${hyprexpoSetup}/bin/hyprexpo-setup" ]
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
        environment.systemPackages = services.packages ++ [ hyprglassSetup hyprexpoSetup ];

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

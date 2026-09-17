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
  hyprglassSetup = pkgs.writeShellScript "hyprglass-setup" ''
    hyprctl_bin=${lib.getExe' pkgs.hyprland "hyprctl"}

    # Already loaded (e.g. the hook re-ran) → the load fails, that is fine
    "$hyprctl_bin" plugin load ${pkgs.hyprglass}/lib/hyprglass.so || true

    # hyprctl eval takes the code as one argument and reads a leading "--" (Lua
    # comment) as a flag, hence the leading newline.
    "$hyprctl_bin" eval "
    $(cat ${pkgs.writeText "hyprglass.lua" (builtins.readFile (config.lib.neg.path "files/gui/hypr/hyprglass.lua"))})" || true
  '';

  hyprlandLuaText = builtins.replaceStrings [ "@hyprglass_setup@" ] [ "${hyprglassSetup}" ] (
    builtins.readFile (config.lib.neg.path "files/gui/hypr/hyprland.lua")
  );
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
        environment.systemPackages = services.packages ++ [ hyprglassSetup ];

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

{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
  mkIf (config.features.gui.enable or false) (lib.mkMerge [
    # Generate ~/.local/bin scripts using mkLocalBin (pre-clean + exec + force)
    {
      home.file = let
        binDir = config.neg.repoRoot + "/packages/local-bin/bin";
        binFiles =
          if builtins.pathExists binDir
          then lib.filterAttrs (_: v: v == "regular") (builtins.readDir binDir)
          else {};
        autoSkip = ["ren"];
        mkAuto = name: {
          name = ".local/bin/${name}";
          value = {
            executable = true;
            text = builtins.readFile (binDir + "/${name}");
          };
        };
        autoEntries =
          builtins.listToAttrs (
            map mkAuto (lib.filter (n: !(lib.elem n autoSkip)) (builtins.attrNames binFiles))
          );
        mkEnt = e: {
          name = ".local/bin/${e.name}";
          value = {
            executable = true;
            text = builtins.readFile e.src;
          };
        };
        scriptRoot = config.neg.repoRoot + "/packages/local-bin/scripts";
        specialScripts = [
          {
            name = "autoclick-toggle";
            src = scriptRoot + "/autoclick-toggle";
          }
          {
            name = "hypr-shortcuts";
            src = scriptRoot + "/hypr-shortcuts.sh";
          }
          {
            name = "journal-clean";
            src = scriptRoot + "/journal-clean.sh";
          }
          {
            name = "music-highlevel";
            src = scriptRoot + "/music-highlevel";
          }
          {
            name = "pass-2col";
            src = scriptRoot + "/pass-2col";
          }
          {
            name = "punzip";
            src = scriptRoot + "/punzip";
          }
        ];
        base = builtins.listToAttrs (map mkEnt specialScripts);
        # Special case: vid-info needs path substitution for libs
        sp = pkgs.python3.sitePackages;
        libpp = "${pkgs.neg.pretty_printer}/${sp}";
        libcolored = "${pkgs.python3Packages.colored}/${sp}";
        tpl = builtins.readFile (scriptRoot + "/vid-info.py");
        vidInfoText = lib.replaceStrings ["@LIBPP@" "@LIBCOLORED@"] [libpp libcolored] tpl;
        # Special case: ren needs path substitution for libs as well
        renTpl = builtins.readFile (scriptRoot + "/ren");
        renText = lib.replaceStrings ["@LIBPP@" "@LIBCOLORED@"] [libpp libcolored] renTpl;
      in
        autoEntries
        // base
        // {
          ".local/bin/vid-info" = {
            executable = true;
            text = vidInfoText;
          };
          ".local/bin/ren" = {
            executable = true;
            text = renText;
          };
          # Provide a stable wrapper for Pyprland CLI with absolute path,
          # so Hypr bindings don't rely on PATH. Kept at ~/.local/bin/pypr-client
          # to preserve existing config and muscle memory.
          ".local/bin/pypr-client" = {
            executable = true;
            text = let
              exe = lib.getExe' pkgs.pyprland "pypr";
            in ''
              #!/usr/bin/env bash
              set -euo pipefail
              exec ${exe} "$@"
            '';
          };
          # Robust starter for Pyprland: determines the current Hyprland
          # instance signature before launching so that restarts/crashes
          # of Hyprland don't leave pyprland bound to a stale socket.
          ".local/bin/pypr-run" = {
            executable = true;
            text = let
              exe = lib.getExe' pkgs.pyprland "pypr";
            in ''
              #!/usr/bin/env bash
              set -euo pipefail

              runtime="$XDG_RUNTIME_DIR"
              if [ -z "$runtime" ]; then
                runtime="/run/user/$(id -u)"
              fi
              sig="$HYPRLAND_INSTANCE_SIGNATURE"

              # Validate existing signature; otherwise select newest hypr instance
              if [ -n "$sig" ] && [ -S "$runtime/hypr/$sig/.socket.sock" ]; then
                :
              else
                if [ -d "$runtime/hypr" ]; then
                  newest="$(ls -td "$runtime/hypr"/* 2>/dev/null | head -n1 || true)"
                  if [ -n "$newest" ]; then
                    cand="$(basename -- "$newest" || true)"
                    if [ -S "$runtime/hypr/$cand/.socket.sock" ] || [ -S "$runtime/hypr/$cand/.socket2.sock" ]; then
                      sig="$cand"
                    else
                      sig=""
                    fi
                  fi
                else
                  sig=""
                fi
              fi

              if [ -z "$sig" ]; then
                echo "pypr-run: Hyprland not detected (no signature)." >&2
                exit 1
              fi

              export HYPRLAND_INSTANCE_SIGNATURE="$sig"
              exec ${exe} "$@"
            '';
          };
        };
    }
    # Cleanup: ensure any old ~/.local/bin/raise (from previous config) is removed
    # No per-activation cleanup: keep activation quiet. If legacy ~/.local/bin/raise
    # exists, it can be removed manually.
  ])

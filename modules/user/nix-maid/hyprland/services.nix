{
  lib,
  pkgs,
  inputs ? null,
  ...
}:
let
  hyprscratchLuaPatch = pkgs.writeText "hyprscratch-lua.patch" ''
    --- a/src/dispatchers.rs
    +++ b/src/dispatchers.rs
    @@ -31,7 +31,12 @@
         pub fn exec(&self, cmd: &str) -> Result<()> {
             match self.lang {
                 ConfigLanguage::Hyprlang => call("exec", cmd),
    -            ConfigLanguage::Lua => call_lua(&format!("hl.dsp.exec_cmd({})", lua_str(cmd))),
    +            ConfigLanguage::Lua => {
    +                let clean = if let Some(rest) = cmd.strip_prefix('[') {
    +                    rest.find("] ").map(|i| &rest[i+2..]).unwrap_or(cmd)
    +                } else { cmd };
    +                call_lua(&format!("hl.dsp.exec_cmd({})", lua_str(clean)))
    +            }
             }
         }
     
    --- a/src/dispatchers.rs
    +++ b/src/dispatchers.rs
    @@ -20,6 +20,6 @@
     impl Dispatchers {
    -    fn init() -> Self {
    -        Self {
    -            lang: detect_config_language(),
    -        }
    -    }
    +    fn init() -> Self {
    +        Self {
    +            lang: ConfigLanguage::Lua,
    +        }
    +    }
    
    --- a/src/scratchpad.rs
    +++ b/src/scratchpad.rs
    @@ -153,6 +153,21 @@
             if state.clients_with_title.is_empty() {
                 self.spawn_special(state);
    +            // Poll for the window to appear, then show immediately (single-press)
    +            for _ in 0..15 {
    +                std::thread::sleep(std::time::Duration::from_millis(200));
    +                if let Ok(all_clients) = hyprland::data::Clients::get() {
    +                    if all_clients.iter().any(|c| self.matches_client(c)) {
    +                        let fresh = HyprlandState::new(&self.title, &state.special_workspace)?;
    +                        move_to_special(
    +                            &all_clients.iter().find(|c| self.matches_client(c)).unwrap(),
    +                            &state.special_workspace,
    +                        );
    +                        fresh.toggle_special()?;
    +                        return Ok(());
    +                    }
    +                }
    +            }
             } else if special_with_title.is_empty() {
                 self.capture_special(state)?;
             } else {
  '';
  hyprscratchPkg = inputs.hyprscratch.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
    patches = (old.patches or []) ++ [ hyprscratchLuaPatch ];
  });
in
{
  packages = [
      pkgs.hyprlock # Hyprland's GPU-accelerated screen locking utility
      pkgs.hyprpolkitagent # Polkit authentication agent for Hyprland
      pkgs.wayvnc # VNC server for wlroots-based Wayland compositors
      pkgs.wl-clipboard # Command-line copy/paste utilities for Wayland

      hyprscratchPkg # sashetophizika/hyprscratch with Lua exec fix

      # hyprmusic script
      (pkgs.writeScriptBin "hyprmusic" ''
        #!/bin/sh
        set -euo pipefail
        case "''${1:-}" in
          next) MEMBER=Next ;;
          previous) MEMBER=Previous ;;
          play) MEMBER=Play ;;
          pause) MEMBER=Pause ;;
          play-pause) MEMBER=PlayPause ;;
          *) echo "Usage: $0 next|previous|play|pause|play-pause"; exit 1 ;;
        esac
        exec dbus-send \
          --print-reply \
          --dest="org.mpris.MediaPlayer2.$(${lib.getExe pkgs.playerctl} -l | head -n 1)" \
          /org/mpris/MediaPlayer2 \
          "org.mpris.MediaPlayer2.Player.$MEMBER"
      '')
      # hypr-fix script (Reload Hyprland config)
      (pkgs.writeShellScriptBin "hypr-fix" ''
        set -euo pipefail
        ${lib.getExe pkgs.libnotify} "System Fix" "Reloading Hyprland config..."
        hyprctl reload
        sleep 1
        ${lib.getExe pkgs.libnotify} "System Fix" "Done."
      '')
      # hypr-reload script
      (pkgs.writeShellScriptBin "hypr-reload" ''
        set -euo pipefail
        # Reload Hyprland config (ignore failure to avoid spurious errors)
        hyprctl reload > /dev/null 2>&1 || true
        # Give Hypr a brief moment to settle before restarting quickshell
        sleep 0.3
        # Restart quickshell to reconnect Wayland protocols after hypr reload
        systemctl --user restart quickshell.service > /dev/null 2>&1 || true
      '')
      # hypr-start script (fixes race conditions)
      (pkgs.writeShellScriptBin "hypr-start" ''
        set -euo pipefail
        LOG="/tmp/hypr-start.log"
        echo "Starting hypr-start at $(date)" > "$LOG"

        # Wait a moment for Hyprland to fully initialize sockets
        sleep 1

        # Import environment
        echo "Importing environment..." >> "$LOG"
        dbus-update-activation-environment --systemd --all
        systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE QT_XDG_DESKTOP_PORTAL

        # Stop any stale portals or session targets to force clean state
        echo "Cleaning stale session state..." >> "$LOG"
        systemctl --user stop "xdg-desktop-portal*" hyprland-session.target || true
        systemctl --user reset-failed

        # Start session
        echo "Starting hyprland-session.target..." >> "$LOG"
        systemctl --user start hyprland-session.target
        echo "Done." >> "$LOG"
      '')
      (pkgs.writers.writePython3Bin "hypr-rearrange" {
        flakeIgnore = [
          "E203"
          "E501"
          "W503"
        ];
      } (builtins.readFile ../scripts/hypr/hypr-rearrange.py))
      (pkgs.writeShellScriptBin "hyde-selector" (
        builtins.readFile ../../../../files/scripts/hyde-selector.sh
      ))
    ];

  systemdTargets = {
    hyprland-session = {
      unitConfig = {
        Description = "Hyprland compositor session";
        Documentation = [ "man:systemd.special(7)" ];
        BindsTo = [ "graphical-session.target" ];
        Wants = [ "graphical-session-pre.target" ];
        After = [ "graphical-session-pre.target" ];
      };
    };
  };

  systemdServices = {
    # Hyprscratch daemon (scratchpad manager)
    hyprscratch = {
      description = "Hyprscratch - improved scratchpad functionality for Hyprland";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session-pre.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe hyprscratchPkg} init spotless";
        Restart = "always";
        RestartSec = "2";
      };
    };

    # Hyprland Polkit Agent
    hyprpolkitagent = {
      description = "Hyprland Polkit Agent";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session-pre.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent"; # Polkit authentication agent written in QT/QML
        Environment = [
          "QT_QPA_PLATFORM=wayland"
          "XDG_SESSION_TYPE=wayland"
        ];
        Restart = "on-failure";
        RestartSec = "2s";
      };
    };
  };
}

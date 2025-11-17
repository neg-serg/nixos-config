{
  lib,
  config,
  systemdUser,
  ...
}:
with lib;
  mkIf config.features.gui.enable (lib.mkMerge [
    {
      services.flameshot.enable = true;
      # Keep config minimal and avoid invalid empty shortcuts (Flameshot errors out on "").
      services.flameshot.settings = {
        General = {
          showStartupLaunchMessage = false;
          contrastUiColor = "#005fd7";
          disabledTrayIcon = true;
          drawColor = "#ff1ad4";
          drawThickness = 3;
          savePath = "${config.home.homeDirectory}/dw";
          savePathFixed = false;
          uiColor = "#005faf";
        };
        Shortcuts = {
          TYPE_ARROW = "A";
          TYPE_CIRCLE = "C";
          TYPE_COMMIT_CURRENT_TOOL = "Ctrl+Return";
          TYPE_COPY = "Ctrl+C";
          TYPE_DELETE_CURRENT_TOOL = "Del";
          TYPE_DRAWER = "D";
          TYPE_EXIT = "Ctrl+Q";
          TYPE_IMAGEUPLOADER = "Return";
          TYPE_MARKER = "M";
          TYPE_MOVESELECTION = "Ctrl+M";
          TYPE_MOVE_DOWN = "Down";
          TYPE_MOVE_LEFT = "Left";
          TYPE_MOVE_RIGHT = "Right";
          TYPE_MOVE_UP = "Up";
          TYPE_OPEN_APP = "Ctrl+O";
          TYPE_PENCIL = "P";
          TYPE_PIXELATE = "B";
          TYPE_RECTANGLE = "R";
          TYPE_REDO = "Ctrl+Shift+Z";
          TYPE_RESIZE_DOWN = "Shift+Down";
          TYPE_RESIZE_LEFT = "Shift+Left";
          TYPE_RESIZE_RIGHT = "Shift+Right";
          TYPE_RESIZE_UP = "Shift+Up";
          TYPE_SAVE = "Ctrl+S";
          TYPE_SELECTION = "S";
          TYPE_SELECT_ALL = "Ctrl+A";
          TYPE_TEXT = "T";
          TYPE_TOGGLE_PANEL = "Space";
          TYPE_UNDO = "Ctrl+Z";
          # Intentionally unbound keys are omitted.
        };
      };
    }
    # Force Qt to use Wayland to avoid xcb plugin crashes when racing the compositor.
    {
      systemd.user.services.flameshot = lib.mkMerge [
        {Service.Environment = ["QT_QPA_PLATFORM=wayland"];}
        (systemdUser.mkUnitFromPresets {presets = ["graphical"];})
      ];
    }
  ])

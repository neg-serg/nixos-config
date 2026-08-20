{
  lib,
  mkBool,
  ...
}:
with lib;
{
  options.features.wine = {
    enable = mkBool "enable Wine runtime (wineWow64Packages.stable + winetricks) and the declarative wine-app manager (wineapps CLI)" false;
    apps = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            installer = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Installer for the app: absolute path to an .exe/.msi on disk, or an http(s) URL. null = app was installed manually (wineapps only manages run/desktop).";
            };
            installArgs = mkOption {
              type = types.str;
              default = "/S";
              description = "Arguments passed to the installer (InnoSetup silent default: /S).";
            };
            executable = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Path to the app's main executable relative to the prefix root (e.g. \"drive_c/Program Files/App/app.exe\"). Used by 'wineapps run' and desktop launchers.";
            };
            prefix = mkOption {
              type = types.str;
              default = "";
              description = "Prefix name (directory under ~/.local/share/wineprefixes). Empty = use the app attribute name.";
            };
            arch = mkOption {
              type = types.enum [
                "win64"
                "win32"
              ];
              default = "win64";
              description = "Wine architecture for the prefix (WINEARCH). Use win32 only for legacy 32-bit apps.";
            };
            winetricks = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "winetricks verbs applied before running the installer, e.g. [ \"corefonts\" \"vcrun2022\" ].";
            };
            desktop = mkOption {
              type = types.bool;
              default = true;
              description = "Generate a .desktop launcher for the app (requires 'executable').";
            };
            comment = mkOption {
              type = types.str;
              default = "";
              description = "Short human-readable description (shown in 'wineapps list' and desktop entries).";
            };
          };
        }
      );
      default = { };
      description = "Declaratively managed Wine apps. Each attribute name is the app id; add an entry to install it, remove it to uninstall.";
    };
  };
}

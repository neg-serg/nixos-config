{
  lib,
  mkBool,
  ...
}:
{
  options.features.wine = {
    enable = mkBool "enable Wine runtime (wineWow64Packages.stable + winetricks) and the declarative wine-app manager (wineapps CLI)" false;
    apps = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            installer = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Installer for the app: absolute path to an .exe/.msi on disk, or an http(s) URL. null = app was installed manually (wineapps only manages run/desktop).";
            };
            installArgs = lib.mkOption {
              type = lib.types.str;
              default = "/S";
              description = "Arguments passed to the installer (InnoSetup silent default: /S).";
            };
            executable = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Path to the app's main executable relative to the prefix root (e.g. \"drive_c/Program Files/App/app.exe\"). Used by 'wineapps run' and desktop launchers.";
            };
            prefix = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Prefix name (directory under ~/.local/share/wineprefixes). Empty = use the app attribute name.";
            };
            arch = lib.mkOption {
              type = lib.types.enum [
                "win64"
                "win32"
              ];
              default = "win64";
              description = "Wine architecture for the prefix (WINEARCH). Use win32 only for legacy 32-bit apps.";
            };
            winetricks = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "winetricks verbs applied before running the installer, e.g. [ \"corefonts\" \"vcrun2022\" ].";
            };
            desktop = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Generate a .desktop launcher for the app (requires 'executable').";
            };
            comment = lib.mkOption {
              type = lib.types.str;
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

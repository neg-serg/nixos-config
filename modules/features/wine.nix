{
  lib,
  mkBool,
  mkOpt,
  ...
}:
{
  options.features.wine = {
    enable = mkBool "enable Wine runtime (wineWow64Packages.stable + winetricks) and the declarative wine-app manager (wineapps CLI)" false;
    apps =
      mkOpt
        (lib.types.attrsOf (
          lib.types.submodule {
            options = {
              installer =
                mkOpt (lib.types.nullOr lib.types.str) null
                  "Installer for the app: absolute path to an .exe/.msi on disk, or an http(s) URL. null = app was installed manually (wineapps only manages run/desktop).";
              installArgs =
                mkOpt lib.types.str "/S"
                  "Arguments passed to the installer (InnoSetup silent default: /S).";
              executable =
                mkOpt (lib.types.nullOr lib.types.str) null
                  "Path to the app's main executable relative to the prefix root (e.g. \"drive_c/Program Files/App/app.exe\"). Used by 'wineapps run' and desktop launchers.";
              prefix =
                mkOpt lib.types.str ""
                  "Prefix name (directory under ~/.local/share/wineprefixes). Empty = use the app attribute name.";
              arch = mkOpt (lib.types.enum [
                "win64"
                "win32"
              ]) "win64" "Wine architecture for the prefix (WINEARCH). Use win32 only for legacy 32-bit apps.";
              winetricks =
                mkOpt (lib.types.listOf lib.types.str) [ ]
                  "winetricks verbs applied before running the installer, e.g. [ \"corefonts\" \"vcrun2022\" ].";
              desktop =
                mkOpt lib.types.bool true
                  "Generate a .desktop launcher for the app (requires 'executable').";
              comment =
                mkOpt lib.types.str ""
                  "Short human-readable description (shown in 'wineapps list' and desktop entries).";
            };
          }
        ))
        { }
        "Declaratively managed Wine apps. Each attribute name is the app id; add an entry to install it, remove it to uninstall.";
  };
}

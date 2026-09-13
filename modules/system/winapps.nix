{
  lib,
  pkgs,
  config,
  ...
}:
let
  winappsCfg = config.features.apps.winapps or { };
  enabled = winappsCfg.enable or false;
  vmProfile = (config.profiles.vm or { enable = false; }).enable;

  # App configs from local files
  appDir = config.lib.neg.path "files/winapps/apps";

  parseAppInfo =
    name:
    let
      raw = builtins.readFile "${appDir}/${name}/info";
      getVar =
        var:
        let
          matches = builtins.match ".*${var}=\"([^\"]*)\".*" raw;
        in
        if matches == null then "" else builtins.elemAt matches 0;
    in
    {
      name = getVar "NAME";
      fullName = getVar "FULL_NAME";
      executable = getVar "WIN_EXECUTABLE";
      categories = getVar "CATEGORIES";
      mimeTypes = getVar "MIME_TYPES";
    };

  # Desktop entries for selected apps
  desktopApps = winappsCfg.desktopApps or [ ];
  desktopFiles = pkgs.runCommand "winapps-desktop" { } (
    ''
      mkdir -p $out/share/applications
    ''
    + lib.concatMapStrings (
      appName:
      let
        app = parseAppInfo appName;
      in
      builtins.replaceStrings
        [
          "@APPNAME@"
          "@NAME@"
          "@FULLNAME@"
          "@FULLNAME_V2@"
          "@APPDIR@"
          "@APPNAME_V2@"
          "@APPNAME_V3@"
          "@APPNAME_V4@"
          "@CATEGORIES@"
          "@MIMETYPES@"
        ]
        [
          "${appName}"
          "${app.name}"
          "${app.fullName}"
          "${app.fullName}"
          "${appDir}"
          "${appName}"
          "${pkgs.writeShellScriptBin "winapps-${appName}" ''
            exec winapps ${appName} "''${1:-}"
          ''}"
          "${appName}"
          "${builtins.replaceStrings [ "WinApps;" ] [ "" ] (
            if app.categories == "" then "Office" else app.categories
          )}"
          "${app.mimeTypes}"
        ]
        (builtins.readFile (config.lib.neg.path "files/winapps/desktop-entry.in"))
    ) desktopApps
  );

in
{
  config = lib.mkIf enabled {
    assertions = [
      {
        assertion = !vmProfile;
        message = "features.apps.winapps.enable is intended for bare-metal hosts; disable profiles.vm.enable when using WinApps.";
      }
      {
        assertion = config.virtualisation.libvirtd.enable or false;
        message = "features.apps.winapps.enable requires KVM/libvirt (virtualisation.libvirtd.enable = true).";
      }
    ];

    environment.systemPackages = lib.mkAfter (
      [
        (pkgs.writeShellScriptBin "winapps" (
          builtins.replaceStrings
            [ "@APPDIR@" "@COREUTILS@" "@COREUTILS_V2@" "@GNUSED@" "@FREERDP@" "@FREERDP_V2@" ]
            [
              "${appDir}"
              "${pkgs.coreutils}"
              "${pkgs.coreutils}"
              "${pkgs.gnused}"
              "${pkgs.freerdp}"
              "${pkgs.freerdp}"
            ]
            (builtins.readFile ./winapps.sh)
        ))
        pkgs.freerdp # RDP client for WinApps
        pkgs.qemu_kvm # KVM virtual machines for WinApps
        pkgs.virt-manager # VM management GUI
        pkgs.virt-viewer # SPICE/VNC client for VMs
      ]
      ++ lib.optional (desktopApps != [ ]) desktopFiles
    );
    environment.etc."winapps/winapps.conf".text = ''
      # WinApps configuration (default)
      # Override in ~/.config/winapps/winapps.conf
      RDP_USER="neg"
      RDP_PASS="neg"
      RDP_DOMAIN=""
      RDP_IP="127.0.0.1"
      RDP_SCALE=100
      MULTIMON="false"
      DEBUG="false"
      RDP_FLAGS="/network:auto /sound:auto /microphone:auto /gfx:avc444 /bpp:32"
    '';
  };
}

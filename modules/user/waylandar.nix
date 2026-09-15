# Waylandar — standalone Wayland calendar widget + dashboard (Quickshell + Python).
# Builds from the github flake input source, but with the python backend's
# caldav package having its test-suite disabled (doCheck=false): upstream
# pythonEnv defaults to doCheck=true and caldav's tests hang on this host
# (restricted network / no working binary cache).
# The derivation body below is kept verbatim from upstream flake.nix
# (v1.0.0, rev b46d5c3); only `src` is repointed at the flake input and
# `pkgs` is renamed to `raw` (the repo-overlay-free nixpkgs instance).
{
  pkgs,
  lib,
  config,
  inputs ? { },
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  quickshellEnabled = config.lib.neg.quickshellEnabled;

  # Same nixpkgs instance the flake input follows (raw, no repo overlays):
  # reuses the already-built python closure already present in the store.
  raw = inputs.nixpkgs.legacyPackages.${system};

  # Only caldav needs its tests off; all other packages keep nixpkgs defaults
  # so their existing store outputs are shared.
  python3 = raw.python3.override {
    packageOverrides = _self: super: {
      caldav = super.caldav.overridePythonAttrs (_: {
        doCheck = false;
      });
    };
  };

  pythonEnv = python3.withPackages (
    ps: with ps; [
      google-api-python-client
      google-auth-httplib2
      google-auth-oauthlib
      caldav
      icalendar
      recurring-ical-events
    ]
  );

  waylandarPkg = raw.stdenv.mkDerivation {
    pname = "waylandar";
    version = "1.0.0";
    src = inputs.waylandar;

    buildInputs = [ raw.makeWrapper ];

    installPhase =
      builtins.replaceStrings
        [ "@BASH@" "@PYTHONENV@" "@BASH_V2@" "@QUICKSHELL@" "@BASH_V3@" "@QUICKSHELL_V2@" ]
        [
          "${raw.bash}"
          "${pythonEnv}"
          "${raw.bash}"
          "${raw.quickshell}"
          "${raw.bash}"
          "${raw.quickshell}"
        ]
        (builtins.readFile ./waylandar-install.sh);
  };
in
{
  config = lib.mkIf quickshellEnabled {
    environment.systemPackages = lib.mkAfter [ waylandarPkg ];
  };
}

{ pkgs, inputs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  # Same nixpkgs instance the flake input follows (raw, no repo overlays): the
  # package reuses the already-built python closure in the store.
  raw = inputs.nixpkgs.legacyPackages.${system};

  # Only caldav needs its tests off; other packages keep nixpkgs defaults so
  # their existing store outputs are shared.
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
in
raw.stdenv.mkDerivation {
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
      (builtins.readFile ./install.sh);
}

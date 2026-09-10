# Waylandar — standalone Wayland calendar widget + dashboard (Quickshell + Python).
# Builds from the github flake input source, but with the python backend's
# caldav package having its test-suite disabled (doCheck=false): upstream
# pythonEnv defaults to doCheck=true and caldav's tests hang on this host
# (restricted network / no working binary cache).
# The derivation body below is kept verbatim from upstream flake.nix
# (v1.0.0, rev b46d5c3); only `src` is repointed at the flake input and
# `pkgs` is renamed to `raw` (the repo-overlay-free nixpkgs instance).
{ pkgs, lib, config, inputs ? { }, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  guiEnabled = config.lib.neg.enabled "gui";
  qtEnabled = config.lib.neg.enabled "gui.qt";
  quickshellEnabled =
    guiEnabled
    && qtEnabled
    && (config.lib.neg.enabled "gui.quickshell")
    && (!(config.lib.neg.enabled "devSpeed"));

  # Same nixpkgs instance the flake input follows (raw, no repo overlays):
  # reuses the already-built python closure already present in the store.
  raw = inputs.nixpkgs.legacyPackages.${system};

  # Only caldav needs its tests off; all other packages keep nixpkgs defaults
  # so their existing store outputs are shared.
  python3 = raw.python3.override {
    packageOverrides = _self: super: {
      caldav = super.caldav.overridePythonAttrs (_: { doCheck = false; });
    };
  };

  pythonEnv = python3.withPackages (ps: with ps; [
    google-api-python-client
    google-auth-httplib2
    google-auth-oauthlib
    caldav
    icalendar
    recurring-ical-events
  ]);

      waylandarPkg = raw.stdenv.mkDerivation {
        pname = "waylandar";
        version = "1.0.0";
        src = inputs.waylandar;

        buildInputs = [ raw.makeWrapper ];

        installPhase = ''
          mkdir -p $out/bin
          mkdir -p $out/share/waylandar

          cp -r frontend backend theme_template.qml $out/share/waylandar/

          # Wrap the python auth script
          cat > $out/bin/waylandar <<EOF
          #!${raw.bash}/bin/bash
          exec ${pythonEnv}/bin/python $out/share/waylandar/backend/sync.py "\$@"
          EOF
          chmod +x $out/bin/waylandar

          # Move Theme out of frontend so it isn't symlinked as read-only later
          mv $out/share/waylandar/frontend/Theme.qml $out/share/waylandar/fallback_Theme.qml

          # Create a common initialization script
          cat > $out/bin/waylandar-init-theme <<EOF
          if [ -f ~/.config/waylandar/frontend/Theme.qml ]; then cp ~/.config/waylandar/frontend/Theme.qml ~/.config/waylandar/Theme.qml.bak; fi
          rm -rf ~/.config/waylandar/frontend
          mkdir -p ~/.config/waylandar/frontend/components
          
          # Symlink all read-only frontend files to the writable config directory individually to preserve structure
          ln -sfn $out/share/waylandar/frontend/*.qml ~/.config/waylandar/frontend/ 2>/dev/null || true
          ln -sfn $out/share/waylandar/frontend/components/*.qml ~/.config/waylandar/frontend/components/ 2>/dev/null || true
          
          # Restore the Matugen theme backup AFTER the symlinks are generated, so it safely overwrites the default symlink
          if [ -f ~/.config/waylandar/Theme.qml.bak ]; then mv ~/.config/waylandar/Theme.qml.bak ~/.config/waylandar/frontend/Theme.qml; fi
          
          # Copy the template for Matugen to use
          cp $out/share/waylandar/theme_template.qml ~/.config/waylandar/theme_template.qml
          chmod 644 ~/.config/waylandar/theme_template.qml
          
          # Copy the fallback Theme.qml ONLY if Matugen hasn't generated one
          if [ ! -f ~/.config/waylandar/frontend/Theme.qml ]; then
            cp $out/share/waylandar/fallback_Theme.qml ~/.config/waylandar/frontend/Theme.qml
            chmod 644 ~/.config/waylandar/frontend/Theme.qml
          fi
          EOF
          chmod +x $out/bin/waylandar-init-theme

          # Wrap the quickshell widget launcher
          cat > $out/bin/waylandar-widget <<EOF
          #!${raw.bash}/bin/bash
          source $out/bin/waylandar-init-theme
          exec ${raw.quickshell}/bin/quickshell -p ~/.config/waylandar/frontend/widget.qml
          EOF
          chmod +x $out/bin/waylandar-widget

          # Wrap the quickshell dashboard launcher
          cat > $out/bin/waylandar-dashboard <<EOF
          #!${raw.bash}/bin/bash
          source $out/bin/waylandar-init-theme
          exec ${raw.quickshell}/bin/quickshell -p ~/.config/waylandar/frontend/dashboard.qml
          EOF
          chmod +x $out/bin/waylandar-dashboard
        '';
      };
in
{
  config = lib.mkIf quickshellEnabled {
    environment.systemPackages = lib.mkAfter [ waylandarPkg ];
  };
}

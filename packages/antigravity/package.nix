{
  stdenv,
  lib,
  unzip,
  opencode,
  writeShellScriptBin,
}:

let
  antigravity-launcher = writeShellScriptBin "antigravity" ''
    export PATH="${lib.makeBinPath [ opencode ]}:$PATH"
    if [ ! -d "$HOME/.local/share/antigravity" ]; then
      echo "Google Antigravity not found. Please download it from:"
      echo "https://antigravity.google/"
      echo ""
      echo "And extract it to: $HOME/.local/share/antigravity/"
      echo ""
      echo "Or run: antigravity-install"
      exit 1
    fi

    exec "$HOME/.local/share/antigravity/Antigravity" "$@"
  '';

  antigravity-installer = writeShellScriptBin "antigravity-install" ''
    set -e

    INSTALL_DIR="$HOME/.local/share/antigravity"
    TEMP_DIR=$(mktemp -d)

    echo "Downloading Google Antigravity..."

    # Since direct download URL may vary, this provides instructions
    echo "Please visit https://antigravity.google/ to download Antigravity"
    echo "Download the Linux version and save it to /tmp/antigravity.zip"
    echo "Then run this script again with: antigravity-install /tmp/antigravity.zip"

    if [ -n "$1" ] && [ -f "$1" ]; then
      echo "Installing from: $1"
      ${unzip}/bin/unzip -q "$1" -d "$TEMP_DIR"
      mkdir -p "$INSTALL_DIR"
      cp -r "$TEMP_DIR"/* "$INSTALL_DIR/"
      chmod +x "$INSTALL_DIR/Antigravity"
      echo "Google Antigravity installed successfully!"
      echo "Run with: antigravity"
      rm -rf "$TEMP_DIR"
    else
      echo "Usage: antigravity-install /path/to/antigravity.zip"
      rm -rf "$TEMP_DIR"
    fi
  '';
in
stdenv.mkDerivation {
  name = "antigravity-launcher";
  version = "latest";

  buildInputs = [
    antigravity-launcher
    antigravity-installer
  ];

  unpackPhase = "true";

  buildPhase = ''
    mkdir -p $out/bin
    ln -s ${antigravity-launcher}/bin/antigravity $out/bin/
    ln -s ${antigravity-installer}/bin/antigravity-install $out/bin/
  '';

  installPhase = "true";

  meta = with lib; {
    description = "Google's Antigravity AI IDE - Next-generation AI-powered development platform";
    homepage = "https://antigravity.google";
    license = licenses.unfree;
    maintainers = with maintainers; [ ];
    mainProgram = "antigravity";
    platforms = platforms.all;
  };
}

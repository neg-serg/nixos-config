{
  lib,
  stdenv,
  makeWrapper,
  rofi,
}:
stdenv.mkDerivation rec {
  pname = "rofi-config";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    # Install themes to share/rofi/themes
    mkdir -p $out/share/rofi/themes

    # Copy all rasi files from subdirectories to the themes root for easy access
    # or keep structure? Rofi recursive search depends on XDG_DATA_DIRS.
    # Let's keep structure but also ensure flat access if needed by scripts.
    # Actually, the scripts reference specific subdirs like `launchers/type-6`.
    # So we should preserve directory structure in $out/share/rofi.

    cp -r * $out/share/rofi/

    # We also need to install the scripts to bin
    mkdir -p $out/bin

    # Install launcher script
    install -m755 _rofi/launchers-type-6/launcher.sh $out/bin/rofi-launcher

    # Install powermenu script
    install -m755 _rofi/powermenu-type-6/powermenu.sh $out/bin/rofi-powermenu

    # Patch the scripts to point to the store path instead of ~/.config/rofi
    substituteInPlace $out/bin/rofi-launcher \
      --replace '$HOME/.config/rofi' "$out/share/rofi" \
      --replace 'launchers/type-6' '_rofi/launchers-type-6'
      
    substituteInPlace $out/bin/rofi-powermenu \
      --replace '$HOME/.config/rofi' "$out/share/rofi" \
      --replace 'powermenu/type-6' '_rofi/powermenu-type-6'

    wrapProgram $out/bin/rofi-launcher \
      --prefix PATH : ${lib.makeBinPath [ rofi ]}

    wrapProgram $out/bin/rofi-powermenu \
      --prefix PATH : ${lib.makeBinPath [ rofi ]}

    runHook postInstall
  '';
}

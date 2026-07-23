##
# Package: praxislive
# Purpose: PraxisLIVE — hybrid visual live programming IDE for creative coding (NetBeans RCP)
# Source: https://www.praxislive.org
# Version: 6.7.0 (2026-07-17)
{
  lib,
  stdenvNoCC,
  fetchzip,
  jdk21,
  makeWrapper,
  writeShellScript,
}:
let
  version = "6.7.0";

  # App launcher: calls the real bin/praxislive with the Nix JDK.
  # The launcher resolves basedir from its own location.
  launcher = writeShellScript "praxislive" ''
    exec "@out@/lib/praxislive/bin/praxislive" \
      --jdkhome "${jdk21.home}" \
      "$@"
  '';
in
stdenvNoCC.mkDerivation {
  pname = "praxislive";
  inherit version;

  src = fetchzip {
    url = "https://github.com/praxis-live/praxis-live/releases/download/v${version}/PraxisLIVE-${version}.zip";
    hash = "sha256-XVSXHyZuSqkbSk3ZGu78iUJw5zDyR82L8j/CaGtUgGo=";
    stripRoot = false;
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
        runHook preInstall

        basedir="$out/lib/praxislive"

        # Move the whole app bundle to the Nix store
        mkdir -p "$basedir"
        cp -r "PraxisLIVE-${version}/"* "$basedir/"

        # Install wrapper with fixed path to launcher
        mkdir -p "$out/bin"
        substitute "${launcher}" "$out/bin/.praxislive-raw" \
          --subst-var out
        chmod +x "$out/bin/.praxislive-raw"

        # wrapProgram adds PATH, makes it find jdk21
        wrapProgram "$out/bin/.praxislive-raw" \
          --prefix PATH : "${jdk21}/bin"

        mv "$out/bin/.praxislive-raw" "$out/bin/praxislive"

        # Desktop entry
        mkdir -p "$out/share/applications"
        cat > "$out/share/applications/praxislive.desktop" << EOF
    [Desktop Entry]
    Type=Application
    Name=PraxisLIVE
    Comment=Hybrid visual live programming IDE
    Exec=$out/bin/praxislive
    Icon=praxislive
    Categories=Development;IDE;
    Terminal=false
    StartupWMClass=praxislive
    EOF

        runHook postInstall
  '';

  meta = with lib; {
    description = "Hybrid visual live programming IDE for creative coding";
    longDescription = ''
      PraxisLIVE is a hybrid visual live programming IDE, rethinking general
      purpose and creative coding. Built around PraxisCORE, a modular JVM
      runtime for cyberphysical programming, supporting real-time coding of
      real-time systems. Features a distributed forest-of-actors architecture,
      runtime code changes and comprehensive introspection.
    '';
    homepage = "https://www.praxislive.org";
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    license = licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
    mainProgram = "praxislive";
  };
}

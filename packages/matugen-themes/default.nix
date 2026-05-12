{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation rec {
  pname = "matugen-themes";
  version = "unstable-2025-11-01";

  src = fetchFromGitHub {
    owner = "InioX";
    repo = "matugen-themes";
    rev = "ed9ce14dea1adba96a0eb4d4cc3d751a0b304863";
    hash = "sha256-loFuvBqNT1As9I2gSZ2FxaqaDYbMh9xPVUsKBPlxI7M=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    docDir="$out/share/doc/${pname}"
    templatesDir="$out/share/${pname}"
    install -Dm644 README.md "$docDir/README.md"
    install -Dm644 LICENSE "$docDir/LICENSE"
    mkdir -p "$templatesDir"
    cp -r templates "$templatesDir/"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Template collection for Matugen theme generator";
    homepage = "https://github.com/InioX/matugen-themes";
    license = licenses.mit;
    platforms = platforms.all;
  };
}

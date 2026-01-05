{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage {
  pname = "surfingkeys-pkg";
  version = "1.1.0";

  src = fetchFromGitHub {
    owner = "b0o";
    repo = "surfingkeys-conf";
    rev = "master"; # Using master as it's a config repo, often ahead of releases
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

  dontNpmBuild = true;

  buildPhase = ''
    runHook preBuild
    npm run gulp build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/surfingkeys
    cp build/surfingkeys.js $out/share/surfingkeys/
    runHook postInstall
  '';

  meta = with lib; {
    description = "Maddison's SurfingKeys Configuration";
    homepage = "https://github.com/b0o/surfingkeys-conf";
    license = licenses.mit;
    maintainers = [];
    platforms = platforms.all;
  };
}

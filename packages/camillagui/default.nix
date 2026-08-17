{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  unzip,
  python3,
  pycamilladsp,
  pycamilladsp-plot,
}:

let
  # Runtime Python environment: backend needs aiohttp + websocket + yaml/json
  # (numpy/matplotlib are optional in the deps — pure-Python fallbacks are used).
  pythonEnv = python3.withPackages (ps: [
    ps.aiohttp
    ps.jsonschema
    ps.pyyaml
    ps.websocket-client
    pycamilladsp
    pycamilladsp-plot
  ]);
in
stdenv.mkDerivation rec {
  pname = "camillagui";
  version = "4.1.0";

  # Official release bundle: backend source + prebuilt React frontend (build/).
  # BASEPATH in backend/settings.py resolves relative to this layout, so
  # backend/, build/ and config/ must stay siblings under $out/lib/camillagui.
  src = fetchurl {
    url = "https://github.com/HEnquist/camillagui-backend/releases/download/v${version}/camillagui.zip";
    hash = "sha256-of8dV3+sYOTI9huN00EAo6MODrj11+FD7V+pES+rKFk=";
  };

  nativeBuildInputs = [
    makeWrapper
    unzip # unpackPhase support for the .zip source
  ];

  # The zip has multiple top-level entries (backend/, build/, config/, main.py);
  # keep them unpacked in-place instead of letting unpackPhase guess a sourceRoot.
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/camillagui $out/bin
    cp -r backend build config main.py $out/lib/camillagui/
    makeWrapper ${pythonEnv}/bin/python $out/bin/camillagui \
      --chdir $out/lib/camillagui \
      --add-flags "$out/lib/camillagui/main.py"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Web GUI for CamillaDSP (aiohttp backend + prebuilt React frontend)";
    homepage = "https://github.com/HEnquist/camillagui-backend";
    license = licenses.gpl3;
    mainProgram = "camillagui";
    platforms = platforms.linux;
    maintainers = [ ];
  };
}

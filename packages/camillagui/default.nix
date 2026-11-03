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

  # The backend reads exactly one config file, the copy bundled in $out, and
  # upstream has no override switch: retarget it at this host's XDG layout
  # instead of the upstream ~/camilladsp tree (modules/hardware/audio/dsp.nix
  # keeps the daemon on the same paths). Tilde paths keep the package
  # user-agnostic; 127.0.0.1 keeps the unauthenticated UI off the LAN.
  postPatch = ''
    substituteInPlace config/camillagui.yml \
      --replace-fail 'bind_address: "0.0.0.0"' 'bind_address: "127.0.0.1"' \
      --replace-fail 'config_dir: "~/camilladsp/configs"' 'config_dir: "~/.config/camilladsp"' \
      --replace-fail 'coeff_dir: "~/camilladsp/coeffs"' 'coeff_dir: "~/.config/camilladsp/coeffs"' \
      --replace-fail 'default_config: "~/camilladsp/default_config.yml"' 'default_config: "~/.config/camilladsp/default.yml"' \
      --replace-fail 'statefile_path: "~/camilladsp/statefile.yml"' 'statefile_path: "~/.local/state/camilladsp/statefile.yml"' \
      --replace-fail 'log_file: "~/camilladsp/camilladsp.log"' 'log_file: null'
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/camillagui $out/bin
    cp -r backend build config main.py $out/lib/camillagui/
    makeWrapper ${pythonEnv}/bin/python $out/bin/camillagui \
      --chdir $out/lib/camillagui \
      --add-flags "$out/lib/camillagui/main.py"
    runHook postInstall
  '';

  meta = lib.mkMeta {
    description = "Web GUI for CamillaDSP (aiohttp backend + prebuilt React frontend)";
    homepage = "https://github.com/HEnquist/camillagui-backend";
    license = lib.licenses.gpl3;
    mainProgram = "camillagui";
  };
}

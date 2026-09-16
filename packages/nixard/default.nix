{
  lib,
  stdenv,
  python3,
  makeWrapper,
  fetchFromGitHub,
}:
let
  pythonEnv = python3.withPackages (ps: [
    ps.textual # Textual TUI framework (only runtime dep)
  ]);
in
stdenv.mkDerivation rec {
  pname = "nixard";
  version = "2.0.0-unstable-2026-06-12";

  src = fetchFromGitHub {
    owner = "manelinux";
    repo = "nixard";
    rev = "4d226c6c5899dee9623d5896c739803c1b141dc5"; # main HEAD (no tags upstream)
    hash = "sha256-nAu+OsNi1tQDbnVWSQid2T9J1AWxAp6WeqCBRtKb/8o=";
  };

  nativeBuildInputs = [ makeWrapper ];

  buildInputs = [ pythonEnv ];

  # Single-file app (nixard.py) — same layout as upstream default.nix
  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share/nixard
    cp nixard.py $out/share/nixard/nixard.py
    makeWrapper ${pythonEnv}/bin/python3 $out/bin/nixard \
      --add-flags "$out/share/nixard/nixard.py"
    runHook postInstall
  '';

  meta = lib.mkMeta {
    description = "Terminal UI to explore NixOS package closures and generate Nix declarations";
    homepage = "https://github.com/manelinux/nixard";
    license = lib.licenses.mit;
    mainProgram = "nixard";
  };
}

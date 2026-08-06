{
  stdenv,
  lib,
}:
stdenv.mkDerivation {
  pname = "vicinae-fd-search";
  version = "0.1.0";

  # Bundled extension (fd-search.js + package.json + assets). To rebuild
  # fd-search.js from src/fd-search.tsx after editing the source:
  #   cd files/gui/vicinae-extensions/fd-search
  #   vici build -o <outdir>   # requires vicinae dev CLI + npm deps
  #   cp <outdir>/fd-search.js fd-search.js
  src = ../../files/gui/vicinae-extensions/fd-search;

  installPhase = ''
    mkdir -p $out
    cp -r . $out/
  '';

  meta = with lib; {
    description = "Vicinae extension for fast filesystem search powered by fd";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}

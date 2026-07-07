{ lib, stdenv, fetchurl, p7zip }:

let
  version = "0.9.3";
  src = fetchurl {
    url = "https://github.com/optiscaler/OptiScaler/releases/download/v${version}/Optiscaler_${version}-final.20260618.7z";
    hash = "sha256-46xlXWDsEbRxrIzF9NN1jkvOkVHIbKoznY8HAMACguM=";
  };
in
stdenv.mkDerivation {
  pname = "optiscaler";
  inherit version src;

  nativeBuildInputs = [ p7zip ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/optiscaler"
    7z x "$src" -o"$out/share/optiscaler" -y > /dev/null 2>&1
    chmod -R u+w "$out/share/optiscaler"

    runHook postInstall
  '';

  meta = {
    description = "Universal upscaling/frame-gen replacement tool — DLSS, FSR, XeSS, FG for GPUs";
    homepage = "https://github.com/optiscaler/OptiScaler";
    license = lib.licenses.unfree;
    platforms = lib.platforms.all;
    maintainers = [ ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}

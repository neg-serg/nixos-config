{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

stdenv.mkDerivation {
  pname = "v2raya";
  version = "2.2.7.5";

  src = fetchurl {
    url = "https://github.com/v2rayA/v2rayA/releases/download/v2.2.7.5/v2raya_linux_x64_2.2.7.5";
    hash = "sha256-M7wfTu4PIbBqjhOTswZoO2ISM8MSPyup1/QFDOfVXTM="; # verified against the v2.2.7.5 GitHub release asset
  };

  dontUnpack = true;

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/v2raya"
    runHook postInstall
  '';

  meta = with lib; {
    description = "A web GUI client of Project V";
    homepage = "https://github.com/v2rayA/v2rayA";
    license = licenses.agpl3Only;
    mainProgram = "v2raya";
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}

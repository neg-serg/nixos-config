{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
  alsa-lib,
  avahi,
}:

stdenv.mkDerivation {
  pname = "rtpmidid";
  version = "0-unstable-2026-08-29";

  src = fetchFromGitHub {
    owner = "davidmoreno";
    repo = "rtpmidid";
    rev = "7f552d2e171465782fa10e6ad35116ff40bc9f66";
    hash = "sha256-BHMl0e6ptHh75rVvojtxBs54mU540CwGp4H1CSDwQH4=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
  ];
  buildInputs = [
    alsa-lib
    avahi
  ];

  cmakeFlags = [
    "-DENABLE_TESTS=OFF"
    "-DCPP_VERSION=20"
    "-DLOG_LEVEL=2"
  ];

  # The project has no install target; ship the daemon binary manually.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -Dm755 src/rtpmidid $out/bin/rtpmidid
    install -Dm755 cli/rtpmidicli $out/bin/rtpmidicli 2>/dev/null || true
    runHook postInstall
  '';

  meta = with lib; {
    description = "RTP MIDI (AppleMIDI) daemon: share ALSA sequencer devices over the network";
    longDescription = ''
      rtpmidid exposes ALSA sequencer ports over RTP-MIDI (AppleMIDI) and imports
      network RTP-MIDI devices (e.g. rtpMIDI on Windows) as ALSA ports. Used to
      send MIDI from Linux into the dockur Windows VM for Genelec GLM MIDI control.
    '';
    homepage = "https://github.com/davidmoreno/rtpmidid";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
    mainProgram = "rtpmidid";
    maintainers = [ ];
  };
}

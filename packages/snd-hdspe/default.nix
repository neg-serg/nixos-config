{ lib, stdenv, kernel, fetchFromGitHub, lld }:

stdenv.mkDerivation rec {
  pname = "snd-hdspe";
  version = "unstable-2022-03-30";

  src = fetchFromGitHub {
    owner = "PhilippeBekaert";
    repo = "snd-hdspe";
    rev = "e29f4dc7422f9d0bc9601f693972810c1634a76e";
    hash = "sha256-r51wkeOtosnfjbnGmyoBciKRXjDkhuYB5v9jAiENkNY=";
  };

  nativeBuildInputs = kernel.moduleBuildDependencies ++ [ lld ];

  hardeningDisable = [ "pic" "format" ];

  # Fix for kernel >= 6.8: pci_set_dma_mask / pci_set_consistent_dma_mask removed
  postPatch = ''
    substituteInPlace sound/pci/hdsp/hdspe/hdspe_core.c \
      --replace-fail 'pci_set_dma_mask(pci,' 'dma_set_mask(&pci->dev,' \
      --replace-fail 'pci_set_consistent_dma_mask(pci,' 'dma_set_coherent_mask(&pci->dev,'

    # Fix for kernel >= 6.7: from_timer macro removed, use container_of
    substituteInPlace sound/pci/hdsp/hdspe/hdspe_midi.c \
      --replace-fail 'from_timer(hmidi, t, timer)' 'container_of(t, struct hdspe_midi, timer)'
  '';

  buildPhase = ''
    runHook preBuild
    make W=1 \
      -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      M=$(pwd) \
      CC=${kernel.stdenv.cc}/bin/clang \
      LLVM=1 \
      KCFLAGS="-Wno-error=unused-command-line-argument -Wno-error=implicit-function-declaration" \
      modules
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/modules/${kernel.modDirVersion}/kernel/sound/pci/hdsp
    cp sound/pci/hdsp/hdspe/snd-hdspe.ko \
      $out/lib/modules/${kernel.modDirVersion}/kernel/sound/pci/hdsp/
    runHook postInstall
  '';

  meta = with lib; {
    description = "New Linux ALSA driver for RME HDSPe MADI/AES/RayDAT/AIO/AIO Pro";
    homepage = "https://github.com/PhilippeBekaert/snd-hdspe";
    license = licenses.gpl3;
    platforms = platforms.linux;
  };
}

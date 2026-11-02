{
  lib,
  stdenv,
  kernel,
  fetchFromGitHub,
  python3,
}:

stdenv.mkDerivation rec {
  pname = "snd-hdspe";
  version = "unstable-2022-03-30";

  src = fetchFromGitHub {
    owner = "PhilippeBekaert";
    repo = "snd-hdspe";
    rev = "e29f4dc7422f9d0bc9601f693972810c1634a76e";
    hash = "sha256-r51wkeOtosnfjbnGmyoBciKRXjDkhuYB5v9jAiENkNY=";
  };

  nativeBuildInputs = kernel.moduleBuildDependencies ++ [ python3 ];

  hardeningDisable = [
    "pic"
    "format"
  ];

  # Fix for kernel >= 6.8: pci_set_dma_mask / pci_set_consistent_dma_mask removed
  postPatch = ''
    substituteInPlace sound/pci/hdsp/hdspe/hdspe_core.c \
      --replace-fail 'pci_set_dma_mask(pci,' 'dma_set_mask(&pci->dev,' \
      --replace-fail 'pci_set_consistent_dma_mask(pci,' 'dma_set_coherent_mask(&pci->dev,'

    # Fix for kernel >= 6.7: from_timer macro removed, use container_of
    substituteInPlace sound/pci/hdsp/hdspe/hdspe_midi.c \
      --replace-fail 'from_timer(hmidi, t, timer)' 'container_of(t, struct hdspe_midi, timer)'

    # Fix for kernel >= 6.8: del_timer renamed to timer_delete, mod_timer still exists
    substituteInPlace sound/pci/hdsp/hdspe/hdspe_midi.c \
      --replace-fail 'del_timer (' 'timer_delete('

    # The driver header enables DEBUG for development ("TODO: undefine in
    # production version"). With CONFIG_DYNAMIC_DEBUG=y that compiles every
    # dev_dbg callsite in the module with the PRINT flag already set, so the
    # card's 2-second status poll floods the kernel log: "polling timeout
    # expired" plus a control get/put trace, ~200 lines per session. Undefine
    # it — the callsites stay in the module and can be re-enabled at runtime
    # via /proc/dynamic_debug/control (module=snd_hdspe +p).
    sed -i -E 's|^#define DEBUG$|/* #define DEBUG */|' \
      sound/pci/hdsp/hdspe/hdspe_core.h
  '';

  buildPhase = ''
    runHook preBuild
    make W=1 \
      -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      M=$(pwd) \
      CC=${kernel.stdenv.cc}/bin/gcc \
      KCFLAGS="-Wno-error=implicit-function-declaration" \
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

  meta = lib.mkMeta {
    description = "New Linux ALSA driver for RME HDSPe MADI/AES/RayDAT/AIO/AIO Pro";
    homepage = "https://github.com/PhilippeBekaert/snd-hdspe";
    license = lib.licenses.gpl3;
  };
}

{
  lib,
  stdenv,
  fetchurl,
  unzip,
  autoPatchelfHook,
  makeWrapper,
  versionCheckHook,
  cairo,
  libei,
  libxkbcommon,
  wayland,
  libx11,
  libxext,
  libxfixes,
  libxrandr,
  libxrender,
  libxtst,
  libxi,
  fontconfig,
  tesseract,
  pipewire,
}:

# Prebuilt release zip — upstream's own default Nix path (their flake builds
# this first; a buildGoModule source path also exists upstream). The binary is
# dynamically linked, so autoPatchelfHook + the runtime libraries below patch
# its RPATH; tesseract's language data is wired through the wrapper.
stdenv.mkDerivation (finalAttrs: {
  pname = "neru";
  version = "1.58.0";

  src = fetchurl {
    url = "https://github.com/y3owk1n/neru/releases/download/v${finalAttrs.version}/neru-linux-amd64.zip";
    hash = "sha256-Nk+NfACg3sOUyC9k8lga+h1o1Y6OEnSDLM18UKBtkZs=";
  };

  unpackPhase = "unzip $src";

  nativeBuildInputs = [
    unzip
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    cairo
    libei
    libxkbcommon
    wayland
    libx11
    libxext
    libxfixes
    libxrandr
    libxrender
    libxtst
    libxi
    fontconfig
    tesseract
    pipewire
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/man/man1
    install -m755 bin/neru $out/bin/neru
    install -m644 share/man/man1/*.1 $out/share/man/man1/

    runHook postInstall
  '';

  postInstall = ''
    # tesseract resolves its language data at runtime; --set-default keeps a
    # user-provided TESSDATA_PREFIX (e.g. tessdata_fast) intact.
    wrapProgram $out/bin/neru \
      --set-default TESSDATA_PREFIX ${tesseract}/share/tessdata
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  meta = lib.mkMeta {
    description = "Keyboard-driven desktop navigation: hints, grids and vim-style modes (Wayland/X11)";
    homepage = "https://github.com/y3owk1n/neru";
    license = lib.licenses.mit;
    mainProgram = "neru";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})

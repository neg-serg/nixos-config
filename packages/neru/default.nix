{
  lib,
  buildGoModule,
  fetchFromGitHub,
  installShellFiles,
  makeWrapper,
  pkg-config,
  writableTmpDirAsHomeHook,
  versionCheckHook,
  cairo,
  libei,
  libxkbcommon,
  wayland,
  wayland-protocols,
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

# Built from upstream main, not from the v1.58.0 release zip: 1.58.0 keeps a key
# down on its proxy keyboard when the device that held it disappears (a suspend,
# an unplug, a dropped Bluetooth keyboard), and the compositor then reads every
# later key as a chord — the keyboard "blocks" until neru is restarted. The fix
# (upstream #1835, "release keys a keyboard held when it disappears") landed
# after the tag and is unreleased; revert to the zip fetch (see git history)
# once 1.59.0 ships.
#
# The source build needs the cgo toolchain and pkg-config: the Linux evdev
# capture is C, and tesseract/pipewire are linked dynamically by the daemon.
buildGoModule (finalAttrs: {
  pname = "neru";
  version = "1.58.0-unstable-2026-10-15";

  src = fetchFromGitHub {
    owner = "y3owk1n";
    repo = "neru";
    rev = "9a0fbc758006ff5964204b0c5a1eb3d4d6eb8b83";
    hash = "sha256-UxXscxmVVSLWfE664b8A84O00bxa/Ba5uIkIpx/Ce8U=";
  };

  # scripts/update-nix-hashes.sh in the upstream tree writes this; the
  # nix-hashes workflow refreshes it after every push to main.
  vendorHash = "sha256-u6CkGrLEbB2QYXYuk7vxqeQS47xixygtTG5g1wu+wfY=";

  subPackages = [ "cmd/neru" ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/y3owk1n/neru/internal/buildinfo.Version=${finalAttrs.version}"
    "-X github.com/y3owk1n/neru/internal/buildinfo.GitCommit=9a0fbc758006ff5964204b0c5a1eb3d4d6eb8b83"
  ];

  nativeBuildInputs = [
    installShellFiles
    makeWrapper
    pkg-config
    writableTmpDirAsHomeHook
  ];

  buildInputs = [
    cairo
    libei
    libxkbcommon
    wayland
    wayland-protocols
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

  # pipewire's libspa-0.2.pc carries `-fno-strict-overflow` in its Cflags, and
  # cgo rejects any pkg-config flag outside its allowlist, so the Linux evdev
  # adapter fails to build until cgo is told that one is safe.
  env.CGO_CFLAGS_ALLOW = "-fno-strict-overflow";

  # go.mod names a Go patch release newer than the one nixpkgs ships; `local`
  # builds with nixpkgs' compiler instead of a download the sandbox cannot make.
  # The `go` directive is still satisfied.
  preBuild = ''
    export GOTOOLCHAIN=local
  '';

  postInstall = ''
    mkdir -p $out/share/man/man1
    go run -ldflags="-X github.com/y3owk1n/neru/internal/buildinfo.Version=${finalAttrs.version}" ./cmd/genman $out/share/man/man1

    installShellCompletion --cmd neru \
      --bash <($out/bin/neru completion bash) \
      --fish <($out/bin/neru completion fish) \
      --zsh <($out/bin/neru completion zsh)

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
  };
})

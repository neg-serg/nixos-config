{
  lib,
  buildGoModule,
  fetchFromGitHub,
  installShellFiles,
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
# capture is C. Upstream also links tesseract through cgo for its OCR hints;
# that engine was removed from this host on 2026-11-08, and the postPatch below
# decouples the two tags (see the comment there).
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

  # Upstream (as of the pinned rev) refuses a capture region that no single
  # output wholly contains: a file chooser taller than the work area, or one
  # moved to hang off the screen, fails every screen-capture strategy, so
  # hints never open over a picker. The patch clips the window region to the
  # screen the cursor is on, hinting the visible part instead of refusing.
  # Drop it once the fix lands upstream.
  patches = [ ./clip-hint-region-to-screen.patch ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/y3owk1n/neru/internal/buildinfo.Version=${finalAttrs.version}"
    "-X github.com/y3owk1n/neru/internal/buildinfo.GitCommit=9a0fbc758006ff5964204b0c5a1eb3d4d6eb8b83"
  ];

  # Tesseract was removed from the system, but upstream ties the OCR bridge to
  # the `cgo` tag and the Linux evdev adapter needs cgo, so no upstream build
  # exists without libtesseract. These two substitutions decouple the tags: the
  # C bridge compiles only with `-tags tesseract` (not passed here) and the
  # pure-Go stub — which reports that no engine is available — is used instead.
  # The OCR-based hinting is therefore unavailable; keyboard navigation, grids
  # and vim modes are unaffected.
  postPatch = ''
    substituteInPlace internal/adapter/platform/linux/ocr_cgo.go \
      --replace-fail '//go:build linux && cgo' '//go:build linux && cgo && tesseract'
    substituteInPlace internal/adapter/platform/linux/ocr_nocgo.go \
      --replace-fail '//go:build linux && !cgo' '//go:build linux && !tesseract'
    # cgo compiles every .c file in the package directory once any file imports
    # "C" (cgo.go does), and build tags cannot exclude a C file — so the bridge
    # has to leave the tree as well. Nothing references it once ocr_cgo.go is
    # excluded by the tag above.
    mv internal/adapter/platform/linux/ocr.c internal/adapter/platform/linux/ocr.c.disabled
  '';

  nativeBuildInputs = [
    installShellFiles
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

{
  lib,
  stdenv,
  fetchFromGitHub,
  rustPlatform,
  cargo,
  rustc,
  zsh,
  ncurses,
  gcc,
}:
let
  pname = "zsh-native-syntax";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "neg-serg";
    repo = "zsh-native-syntax";
    rev = "3ed903e9c66359d8b5457c25c7e76bb09aa6a565";
    hash = "sha256-E1ILLBwgixtV+PNT5+hgGkHEMD4xRMa7NgsNWfp4YU8=";
  };

  # Configured zsh source (provides module headers: zsh.h, zle.h, zsh.mdh, etc.)
  zshHeaders = stdenv.mkDerivation {
    name = "zsh-headers-${zsh.version}";
    src = zsh.src;
    nativeBuildInputs = zsh.nativeBuildInputs or [ ];
    buildInputs = [ ncurses ];

    configureFlags = [
      "--disable-gdbm"
      "--disable-pcre"
      "--disable-multibyte"
    ];

    buildPhase = "true";

    installPhase = ''
      mkdir -p "$out"
      cp -r Src "$out/"
      cp config.h stamp-h "$out/"
      cp zsh.mdh "$out/Src/" 2>/dev/null || true
    '';
  };
in
stdenv.mkDerivation {
  inherit pname version src;

  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit src;
    sourceRoot = "${src.name}/rust-engine";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  nativeBuildInputs = [
    rustPlatform.cargoSetupHook
    cargo
    rustc
    gcc
  ];

  ZSH_INC = "-I${zshHeaders} -I${zshHeaders}/Src -I${zshHeaders}/Src/Zle -I${zshHeaders}/Src/Modules";

  buildPhase = ''
    runHook preBuild

    echo "Building Rust static library..."
    (cd rust-engine && cargo build --release)

    echo "Linking shared module..."
    mkdir -p build
    gcc -O2 -Wall -Wextra -fPIC -std=c11 \
      $ZSH_INC -Ic-shim \
      -shared \
      -o build/zsh_native_syntax.so \
      c-shim/module.c c-shim/command_classify.c \
      rust-engine/target/release/libzsh_native_syntax.a \
      -lpthread -ldl -lm

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/zsh"
    install -m 755 build/zsh_native_syntax.so "$out/lib/zsh/"
    install -m 644 zsh-native-syntax.plugin.zsh "$out/lib/zsh/"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Native Rust-powered syntax highlighting engine for Zsh (zle module)";
    homepage = "https://github.com/neg-serg/zsh-native-syntax";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.linux;
  };
}

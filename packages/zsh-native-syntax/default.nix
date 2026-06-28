{
  lib,
  stdenv,
  fetchFromGitHub,
  cargo,
  rustc,
  rustPlatform,
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

    buildPhase = ''
      # Generate zsh module headers (zsh.mdh, etc.)
      make -C Src headers 2>/dev/null || make -C Src MODULE 2>/dev/null || true
      # Ensure zsh.mdh exists; create minimal version if not generated
      if [ ! -f Src/zsh.mdh ]; then
        cat > Src/zsh.mdh <<'MHD_EOF'
#ifndef have_zshQsmain_module
#define have_zshQsmain_module
# ifndef IMPORTING_MODULE_zshQsmain
#  define boot_ boot_zshQsmain
#  define cleanup_ cleanup_zshQsmain
#  define features_ features_zshQsmain
#  define enables_ enables_zshQsmain
#  define setup_ setup_zshQsmain
#  define finish_ finish_zshQsmain
# endif
#endif
MHD_EOF
      fi
    '';

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
    hash = "sha256-Nzforh46hZtsgCuWjKt2An3MdqpFItUcGNIXCe72bDE=";
  };

  nativeBuildInputs = [
    rustPlatform.cargoSetupHook
    cargo
    rustc
    gcc
  ];

  buildInputs = [ ncurses ];

  ZSH_INC = "-I${zshHeaders} -I${zshHeaders}/Src -I${zshHeaders}/Src/Zle -I${zshHeaders}/Src/Modules";

  cargoRoot = "rust-engine";

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

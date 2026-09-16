{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  unzip,
  python3,
  ncurses,
  libbsd,
}:

# Mojo 1.0 — official PyPI distribution (five wheels), repackaged for NixOS.
# The manylinux binaries need autoPatchelfHook (glibc interpreter + libstdc++).
# Layout mirrors the official pip/uv venv: site-packages/modular + python
# entry-point packages, so the upstream console scripts work unchanged.

let
  version = "1.0.0";

  # site-packages inside $out; python3.libPrefix is e.g. "python3.13"
  site = "$out/lib/${python3.libPrefix}/site-packages";

  wheel =
    {
      name,
      hash,
      url,
    }:
    fetchurl {
      inherit url hash;
      inherit name;
    };

  wheels = [
    (wheel {
      name = "mojo-${version}.whl";
      url = "https://files.pythonhosted.org/packages/c4/89/326637e71282288e7d3a8ef2990dbf9fbfb07c1b3d21b836ffe2ee3111a9/mojo-${version}-py3-none-manylinux_2_34_x86_64.whl";
      hash = "sha256-cl1rfymlozNOPCJfNfK3Cf1GFRoKMaLCJzixk338g9k=";
    })
    (wheel {
      name = "mojo-compiler-${version}.whl";
      url = "https://files.pythonhosted.org/packages/f0/5f/f38fefe327d1c81e28def69c4a52ae4f75e389cb6e613a2c04ca8d68d582/mojo_compiler-${version}-py3-none-manylinux_2_34_x86_64.whl";
      hash = "sha256-6eYPljjmnKD0vnKSRoUj/JihQ/WNv5Ak9g7Wi4dKhn4=";
    })
    (wheel {
      name = "mojo-lldb-libs-${version}.whl";
      url = "https://files.pythonhosted.org/packages/12/a0/8280a1869d017102d50e0dcf1962e0bc59834f8fe07b435e1a575bb5c923/mojo_lldb_libs-${version}-py3-none-manylinux_2_34_x86_64.whl";
      hash = "sha256-3hUch/P7TRhKhec16uBb9D+anetMuPKwfPa1nLdp2T8=";
    })
    (wheel {
      name = "mojo-compiler-mojo-libs-${version}.whl";
      url = "https://files.pythonhosted.org/packages/54/99/ea401ff1db56a4af8607283b95627e01b986fc67f510715b07f100118105/mojo_compiler_mojo_libs-${version}-py3-none-any.whl";
      hash = "sha256-IKkuN+y9GeLbsaUlYSqN5MnyZvVTbe9VxeKweGMg6LM=";
    })
    (wheel {
      name = "mblack-26.5.0.whl";
      url = "https://files.pythonhosted.org/packages/f0/36/8147d0627cde9043557f7906eabe64ff6295ec910dade5251e5703f0f6d9/mblack-26.5.0-py3-none-any.whl";
      hash = "sha256-ByswRkbCd5eeah0ZsIbvImu3OBgQkC6XXPHDiG0deIM=";
    })
  ];

  # mblack (the `mojo format` backend) is pure Python and needs these deps.
  pythonEnv = python3.withPackages (ps: [
    ps.click
    ps.pathspec
    ps.platformdirs
    ps.mypy-extensions
  ]);
in

stdenv.mkDerivation {
  pname = "mojo";
  inherit version;

  srcs = wheels;

  nativeBuildInputs = [
    autoPatchelfHook
    unzip
  ];
  buildInputs = [
    stdenv.cc.cc.lib # libstdc++ for the manylinux binaries
    ncurses # libncurses/libtinfo/libpanel for lldb
    libbsd # libbsd.so.0 for lldb
  ];

  dontStrip = true; # prebuilt LLVM toolchain, already stripped upstream

  unpackPhase = ''
    mkdir -p "$TMPDIR/unpacked"
    for src in $srcs; do
      unzip -q "$src" -d "$TMPDIR/unpacked"
    done
  '';

  installPhase =
    builtins.replaceStrings
      [ "@SITE_V2@" "@SITE_V3@" "@SITE_V4@" "@PYTHONENV@" "@SITE_V5@" ]
      [
        "${site}"
        "${site}"
        "${site}"
        "${pythonEnv}"
        "${site}"
      ]
      (builtins.readFile ./install.sh);

  meta = lib.mkMeta {
    description = "Mojo programming language (compiler, LSP, formatter, lldb tooling)";
    homepage = "https://mojolang.org/";
    license = lib.licenses.unfree; # LicenseRef-MAX-Platform-Software-License on PyPI
    mainProgram = "mojo";
    platforms = [ "x86_64-linux" ];
  };
}

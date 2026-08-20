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

  installPhase = ''
        runHook preInstall

        mkdir -p ${site}
        # platlib payloads: modular/{bin,lib} SDK from the four mojo wheels
        for d in "$TMPDIR"/unpacked/*.data/platlib/*; do
          [ -e "$d" ] || continue
          cp -r "$d" ${site}/
        done
        # top-level python packages: mojo, _mojo, mblack, mblib2to3, _mblack_version.py
        for d in "$TMPDIR"/unpacked/*; do
          case "$(basename "$d")" in
            *.data|*.dist-info) continue ;;
          esac
          [ -e "$d" ] || continue
          cp -r "$d" ${site}/
        done

        mkdir -p $out/bin

        # Console scripts exactly as pip would generate them from entry_points.txt.
        # Quoted heredoc + sed: store paths and module names are injected safely.
        mkScript() {
          local name="$1" module="$2" func="$3"
          cat > "$out/bin/$name" <<'PYEOF'
    #!@PYTHON@
    import os, sys
    sys.path.insert(0, "@SITE@")
    import re
    from @MODULE@ import @FUNC@
    if __name__ == "__main__":
        sys.argv[0] = re.sub(r"(-script.pyw|.exe)?$", "", sys.argv[0])
        sys.exit(@FUNC@())
    PYEOF
          sed -i         -e "s|@PYTHON@|${pythonEnv}/bin/python|"         -e "s|@SITE@|${site}|"         -e "s|@MODULE@|$module|"         -e "s|@FUNC@|$func|"         "$out/bin/$name"
          chmod +x "$out/bin/$name"
        }

        # mojo-compiler wheel: compiler driver + lld + crashpad handler
        mkScript mojo mojo._entrypoints exec_mojo
        mkScript lld mojo._entrypoints exec_lld
        mkScript modular-crashpad-handler mojo._entrypoints exec_modular_crashpad_handler
        # mojo wrapper wheel: lldb tooling + LSP server
        mkScript gpu-query _mojo._entrypoints exec_gpu_query
        mkScript lldb-argdumper _mojo._entrypoints exec_lldb_argdumper
        mkScript lldb-dap _mojo._entrypoints exec_lldb_dap
        mkScript lldb-server _mojo._entrypoints exec_lldb_server
        mkScript llvm-symbolizer _mojo._entrypoints exec_llvm_symbolizer
        mkScript mojo-lldb _mojo._entrypoints exec_mojo_lldb
        mkScript mojo-lsp-server _mojo._entrypoints exec_mojo_lsp_server
        # mblack: `mojo format` backend
        mkScript mblack mblack patched_main

        runHook postInstall
  '';

  meta = with lib; {
    description = "Mojo programming language (compiler, LSP, formatter, lldb tooling)";
    homepage = "https://mojolang.org/";
    license = licenses.unfree; # LicenseRef-MAX-Platform-Software-License on PyPI
    mainProgram = "mojo";
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}

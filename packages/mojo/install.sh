runHook preInstall

mkdir -p @SITE_V2@
# platlib payloads: modular/{bin,lib} SDK from the four mojo wheels
for d in "$TMPDIR"/unpacked/*.data/platlib/*; do
  [ -e "$d" ] || continue
  cp -r "$d" @SITE_V3@/
done
# top-level python packages: mojo, _mojo, mblack, mblib2to3, _mblack_version.py
for d in "$TMPDIR"/unpacked/*; do
  case "$(basename "$d")" in
    *.data | *.dist-info) continue ;;
  esac
  [ -e "$d" ] || continue
  cp -r "$d" @SITE_V4@/
done

mkdir -p $out/bin

# Console scripts exactly as pip would generate them from entry_points.txt.
# Quoted heredoc + sed: store paths and module names are injected safely.
mkScript() {
  local name="$1" module="$2" func="$3"
  cat > "$out/bin/$name" << 'PYEOF'
#!@PYTHON@
import os, sys
sys.path.insert(0, "@SITE@")
import re
from @MODULE@ import @FUNC@
if __name__ == "__main__":
    sys.argv[0] = re.sub(r"(-script.pyw|.exe)?$", "", sys.argv[0])
    sys.exit(@FUNC@())
PYEOF
  sed -i -e "s|@PYTHON@|@PYTHONENV@/bin/python|" -e "s|@SITE@|@SITE_V5@|" -e "s|@MODULE@|$module|" -e "s|@FUNC@|$func|" "$out/bin/$name"
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

##
# Package: natshell
# Purpose: natural-language shell — a ReAct-style agent TUI that turns a
#   request into shell commands, runs them and iterates until the task is done
#   (every moderate/dangerous command goes through a confirmation gate unless
#   danger-fast is on). Upstream is local-first with a bundled llama.cpp;
#   on trantor it talks to the existing llama-swap endpoint (:9292) instead.
# Notes:
#   - llama-cpp-python (upstream's `local` extra) is deliberately NOT a
#     dependency: it would build a second llama.cpp inside Python and fight
#     llama-swap for the 16 GB card. Every `llama_cpp` import upstream is lazy
#     (inside functions/try blocks), so remote-only mode runs without it;
#     `--local` / `--download` then fail with upstream's own
#     "llama-cpp-python is not installed" message.
#   - Remote mode needs `[engine] preferred = "remote"` in config.toml, not just
#     a `[remote]` URL: with the default "auto" preference the startup path
#     still calls `_ensure_model()` and starts a Hugging Face model download.
#     The deployed config lives in modules/user/nix-maid/apps/natshell.nix.
#   - `mcp` extra (upstream `--mcp` server) is not installed; the TUI and
#     `--headless` are the supported entry points here.
{
  lib,
  git,
  python3,
  fetchPypi,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "natshell";
  version = "1.0.51"; # PyPI release; upstream does not tag every version
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-6WMUm1cQNTLy8boMpPOTbYIccP1rlJ0MFdpjGyalZZU=";
  };

  build-system = [ python3.pkgs.setuptools ];

  # Runtime requirements from pyproject.toml. Textual is unpinned upstream
  # (`>=1.0.0`) and 1.0.51 is from 2026-10, so it is expected to track the
  # nixpkgs Textual (8.x) it was developed against.
  dependencies = with python3.pkgs; [
    textual
    rich
    httpx
    huggingface-hub
  ];

  # Upstream keeps a real unittest/pytest suite (pytest-asyncio, asyncio_mode
  # auto). Keep it running: it is the only check that the Textual widgets still
  # match the nixpkgs Textual version we build against.
  nativeCheckInputs = [
    python3.pkgs.pytest
    python3.pkgs.pytest-asyncio
    python3.pkgs.pytestCheckHook # turns installCheckPhase into a pytest run
    git # the git_tool tests shell out to real git
  ];

  # The suite assumes a writable $HOME — natshell's file tools confine writes to
  # the home directory, and the nix builder's HOME is the unwritable
  # /homeless-shelter, so tempfile-based edit/write tests fail with EACCES. The
  # git_tool tests also expect a git work tree as cwd (they assert that
  # write-capable flags are rejected before git runs). Give it both.
  preCheck = ''
    export HOME=$TMPDIR
    git init -q .
  '';

  pythonImportsCheck = [ "natshell" ];

  meta = lib.mkMeta {
    description = "Natural language shell interface — local-first agentic TUI powered by a bundled LLM";
    homepage = "https://github.com/Barent/natshell";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
    mainProgram = "natshell";
  };
}

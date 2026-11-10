{
  pkgs,
  ...
}:

{
  # NatShell (https://github.com/Barent/natshell) — natural-language shell: the
  # TUI takes a request in plain language, the model plans shell commands,
  # natshell runs them (confirm gate for moderate/dangerous patterns) and
  # iterates until the task is done. Package: packages/natshell.
  #
  # Inference is the local llama-swap endpoint (:9292), which already owns the
  # 16 GB card and swaps one model at a time. natshell's bundled llama.cpp
  # (`llama-cpp-python`) is deliberately not installed — see the package header
  # for the lazy-import argument. Config is declarative; a runtime config write
  # (/config) replaces the store symlink with a real file, and the next
  # activation links it again.
  environment.systemPackages = [
    pkgs.neg.natshell # natural-language shell agent TUI (remote inference via llama-swap)
  ];

  users.users.neg.maid.file.home.".config/natshell/config.toml".text = ''
    # NatShell config — see modules/user/nix-maid/apps/natshell.nix.
    #
    # Remote-only: llama-swap (:9292) is the single OpenAI-compatible endpoint
    # for the local fleet. `[engine] preferred = "remote"` is what actually
    # skips natshell's startup model download — a `[remote]` URL alone still
    # lets the "auto" preference call _ensure_model() and pull a GGUF.
    [engine]
    preferred = "remote"

    [remote]
    url = "http://127.0.0.1:9292/v1"
    # Quality tier of the local fleet (dense 27B IQ3_S, see modules/llm/default.nix).
    # /model lists the other llama-swap slots and switches at runtime.
    model = "qwen3.8-27b-abliterated"
    # llama-swap is a llama.cpp proxy, not Ollama: it has no /api/ps or
    # /api/show, so natshell's n_ctx auto-detection returns 0 and the agent
    # would drop to the 4k step/output ladder. This slot runs 32k.
    n_ctx = 32768

    [safety]
    # "confirm" (default): ask before moderate/dangerous commands. Do not set
    # "danger"/danger_fast here — this agent runs commands as the main user.
    mode = "confirm"
  '';
}

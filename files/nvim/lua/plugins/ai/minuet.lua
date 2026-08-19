-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ milanglacier/minuet-ai.nvim                                                   │
-- │   Code completion from local LLMs (Ollama backend, FIM).                           │
-- │   (Continue's official nvim client is still a WIP PR, so minuet is the reliable    │
-- │   path for FIM autocomplete over ollama coder models.)                             │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  "milanglacier/minuet-ai.nvim",
  event = "InsertEnter",
  opts = {
    provider = "openai_fim_compatible",
    n_completions = 1, -- local model: save resources
    context_window = 1024, -- fits 16GB VRAM; raise if fast
    debounce_ms = 800,
    virtualtext_suppression_handle = nil,
    provider_options = {
      openai_fim_compatible = {
        api_key = "TERM", -- unused by ollama, but required by the schema
        name = "Ollama",
        end_point = "http://127.0.0.1:11434/v1/completions",
        -- qwen3-coder:30b is the best coder in the local store; if FIM
        -- output looks off, switch to qwen2.5-coder:7b-instruct-q6_K
        -- (`:Minuet change_model`) which has a battle-tested FIM template.
        model = "qwen3-coder:30b",
        optional = {
          max_tokens = 64,
          top_p = 0.9,
        },
      },
    },
  },
}

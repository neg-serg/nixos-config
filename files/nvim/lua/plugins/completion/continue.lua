-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ continuedev/continue — AI coding assistant (chat + autocomplete, ollama)     │
-- └───────────────────────────────────────────────────────────────────────────────────┘
-- Local models only: qwen3-coder:30b for chat/edit, qwen2.5-coder for FIM autocomplete.
-- Backend: ollama at 127.0.0.1:11434 (system service). No cloud keys involved.
return {
  "continuedev/continue",
  ft = {
    "rust", "python", "typescript", "javascript", "lua", "haskell",
    "tidal", "nix", "sh", "c", "cpp", "go", "java",
  },
  keys = {
    { "<leader>cc", "<cmd>ContinueChatNew<CR>", desc = "Continue: new chat" },
    { "<leader>ct", "<cmd>ContinueChatToggle<CR>", desc = "Continue: toggle chat" },
    { "<leader>ce", "<cmd>ContinueEdit<CR>", desc = "Continue: edit selection", mode = "v" },
  },
  opts = {
    apiBase = "http://127.0.0.1:11434", -- ollama system service
    models = {
      {
        title = "Qwen3 Coder 30B (chat)",
        provider = "ollama",
        model = "qwen3-coder:30b",
        roles = { "chat", "edit", "apply" },
      },
      {
        title = "Qwen2.5 Coder 7B (autocomplete)",
        provider = "ollama",
        model = "qwen2.5-coder:7b-instruct-q6_K",
        roles = { "autocomplete" },
      },
    },
    autocomplete = {
      enabled = true,
    },
  },
}

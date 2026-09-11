-- ┌───────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ olimorris/codecompanion.nvim — AI chat / agent client (ACP + MCP)         │
-- └───────────────────────────────────────────────────────────────────────────────┘
--
-- The `dsh` adapter speaks Agent Client Protocol v1 to the local DeepSeek
-- Harness: `dsh --profile acp` serves newline-delimited JSON-RPC on stdio and
-- requires no authentication. The profile lives in ~/.dsh/profiles/acp and
-- mounts the bundles @deepseek-ai/dsh-base + @deepseek-ai/dsh-acp-app.
--
-- Sessions are owned by the harness (listable and resumable), so this chat
-- buffer is a thin client: the agent supplies the workspace, the tools, and its
-- own model route. The profile pins deepseek-official/deepseek-flash (V4.1),
-- the deployment's only cloud model, so the picker offers nothing else.
--
-- The ACP surface is deliberately automation-only: no DSH-specific plans,
-- terminal panes or elicitation cards, unlike the web and TUI profiles.
return {
  'olimorris/codecompanion.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-treesitter/nvim-treesitter',
  },
  cmd = { 'CodeCompanion', 'CodeCompanionChat', 'CodeCompanionActions', 'CodeCompanionCmd' },
  keys = {
    { '<leader>ic', '<cmd>CodeCompanionChat<cr>', desc = '[CodeCompanion] Chat' },
    { '<leader>iC', '<cmd>CodeCompanionChat Add<cr>', mode = { 'n', 'v' }, desc = '[CodeCompanion] Add to chat' },
    { '<leader>it', '<cmd>CodeCompanionChat Toggle<cr>', desc = '[CodeCompanion] Toggle chat' },
    { '<leader>ia', '<cmd>CodeCompanionActions<cr>', mode = { 'n', 'v' }, desc = '[CodeCompanion] Actions' },
  },
  opts = {
    adapters = {
      acp = {
        -- `dsh` is a local adapter rather than a shipped preset, so it mirrors
        -- the preset shape (codex/gemini_cli) for the generic ACP client.
        dsh = function()
          local helpers = require('codecompanion.adapters.acp.helpers')
          return {
            name = 'dsh',
            formatted_name = 'DeepSeek Harness',
            type = 'acp',
            roles = { llm = 'assistant', user = 'user' },
            opts = { vision = false },
            commands = {
              default = { 'dsh', '--profile', 'acp' },
            },
            defaults = {
              -- The harness advertises authMethods: [], so no auth_method here.
              mcpServers = {},
              timeout = 20000,
            },
            parameters = {
              protocolVersion = 1,
              clientCapabilities = {
                fs = { readTextFile = true, writeTextFile = true },
              },
              clientInfo = { name = 'CodeCompanion.nvim', version = '1.0.0' },
            },
            handlers = {
              setup = function(self)
                return true
              end,
              form_messages = function(self, messages, capabilities)
                return helpers.form_messages(self, messages, capabilities)
              end,
              on_exit = function(self, code) end,
            },
          }
        end,
      },
    },
    interactions = {
      chat = {
        adapter = 'dsh',
      },
    },
  },
}

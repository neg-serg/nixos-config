-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ neovim/nvim-lspconfig                                                        │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'neovim/nvim-lspconfig',
  event = { "BufReadPre", "BufNewFile" },
  dependencies = { 'saghen/blink.cmp' },
  config = function()
    vim.diagnostic.config({
      virtual_text = false,
      virtual_lines = { current_line = true },
      signs = {
        text = {
          [vim.diagnostic.severity.ERROR] = '',
          [vim.diagnostic.severity.WARN]  = '',
          [vim.diagnostic.severity.HINT]  = '',
          [vim.diagnostic.severity.INFO]  = '',
        },
      },
      underline = true,
      update_in_insert = false,
      severity_sort = true,
      float = { border = 'rounded', source = 'if_many' },
    })

    do
      local group = vim.api.nvim_create_augroup('NegLspAttach', { clear = true })
      vim.api.nvim_create_autocmd('LspAttach', {
        group = group,
        callback = function(event)
          local buf = event.buf
          local function bmap(mode, lhs, rhs, desc)
            vim.keymap.set(mode, lhs, rhs, { buffer = buf, silent = true, desc = desc })
          end
          bmap('n', '<leader>D', vim.lsp.buf.type_definition, 'LSP: type definition')
          bmap('n', '<leader>ws', vim.lsp.buf.workspace_symbol, 'LSP: workspace symbol')
          bmap('n', '<leader>uh', function()
            local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = buf })
            vim.lsp.inlay_hint.enable(not enabled, { bufnr = buf })
          end, 'Inlay Hints: toggle')
        end,
      })
    end

    local base_config = {}

    -- configure: set custom config; optionally enable (for non-Mason servers)
    local function configure(server, extra, enable)
      local capabilities = require('blink.cmp').get_lsp_capabilities(
        vim.lsp.protocol.make_client_capabilities()
      )
      local resolved = vim.tbl_deep_extend('force', { capabilities = capabilities }, extra or {})
      local config = vim.tbl_extend('force', resolved, { autostart = enable or false })
      require('lspconfig')[server].setup(config)
    end

    -- System-installed servers (pacman/AUR — not managed by Mason, must enable manually)
    configure('cmake', nil, true)
    configure('systemd_ls', nil, true)

    -- lua_ls: configured here, lazydev.nvim injects workspace libraries at runtime
    configure('lua_ls', {
      settings = {
        Lua = {
          runtime = { version = 'LuaJIT' },
          diagnostics = { disable = { 'incomplete-signature-doc', 'lowercase-global' } },
          workspace = { checkThirdParty = false },
          completion = { callSnippet = 'Replace', keywordSnippet = 'Replace' },
          hint = { enable = true },
          telemetry = { enable = false },
          doc = { privateName = { '^_' } },
        },
      },
    })

    -- Mason-managed servers: config only, mason-lspconfig handles enable via automatic_enable
    configure('clangd', {
      cmd = { 'clangd', '--background-index', '--clang-tidy', '--completion-style=detailed', '--header-insertion=never' },
      init_options = { clangdFileStatus = true },
    })
    configure('jsonls', {
      filetypes = { 'json', 'jsonc', 'json5' },
    })
    configure('pyright', {
      settings = {
        python = {
          analysis = {
            typeCheckingMode = 'basic',
            autoImportCompletions = true,
          },
        },
      },
    })
  end,
}

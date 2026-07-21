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

    local capabilities = require('blink.cmp').get_lsp_capabilities(
      vim.lsp.protocol.make_client_capabilities()
    )

    vim.api.nvim_create_autocmd('LspAttach', {
      group = vim.api.nvim_create_augroup('NegLspAttach', { clear = true }),
      callback = function(event)
        local buf = event.buf
        vim.keymap.set('n', '<leader>D', vim.lsp.buf.type_definition, { buffer = buf, silent = true, desc = 'LSP: type definition' })
        vim.keymap.set('n', '<leader>ws', vim.lsp.buf.workspace_symbol, { buffer = buf, silent = true, desc = 'LSP: workspace symbol' })
        vim.keymap.set('n', '<leader>uh', function()
          local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = buf })
          vim.lsp.inlay_hint.enable(not enabled, { bufnr = buf })
        end, { buffer = buf, silent = true, desc = 'Inlay Hints: toggle' })
      end,
    })

    -- Neovim 0.11 API: vim.lsp.config + vim.lsp.enable
    local function configure(server, opts)
      vim.lsp.config[server] = vim.tbl_deep_extend('force', { capabilities = capabilities }, opts or {})
      vim.lsp.enable(server)
    end
    configure('cmake', {})
    configure('systemd_ls', {})

    configure('marksman', {})

    configure('bashls', {})
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
    configure('ts_ls', {})

    -- vscode-langservers-extracted: cssls, html, jsonls
    configure('cssls', {})
    configure('html', {})
    configure('jsonls', {
      filetypes = { 'json', 'jsonc', 'json5' },
    })

    configure('yamlls', {
      settings = {
        yaml = {
          keyOrdering = false,
        },
      },
    })
    configure('taplo', {})
    configure('just_ls', {})
    configure('autotools_ls', {})
    configure('dotls', {})
    configure('lemminx', {})
    configure('nil', {})
    configure('dockerls', {})
    configure('hls', {})


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

    configure('clangd', {
      cmd = { 'clangd', '--background-index', '--clang-tidy', '--completion-style=detailed', '--header-insertion=never' },
      init_options = { clangdFileStatus = true },
    })
  end,
}

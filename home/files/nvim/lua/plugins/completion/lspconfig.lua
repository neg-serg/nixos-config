-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ neovim/nvim-lspconfig                                                        │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'neovim/nvim-lspconfig',
  dependencies = {
    'SmiteshP/nvim-navbuddy',
    dependencies = { 'SmiteshP/nvim-navic', 'MunifTanjim/nui.nvim' },
    opts = { lsp = { auto_attach = true } },
  },
  config = function()
    if not (vim.lsp and vim.lsp.config and vim.lsp.enable) then
      vim.notify('vim.lsp.config requires Neovim 0.11+', vim.log.levels.WARN)
      return
    end

    vim.diagnostic.config({
      virtual_text = true,
      signs = true,
      underline = true,
      update_in_insert = false,
      severity_sort = true,
      float = { border = 'rounded', source = 'if_many' },
    })

    local handlers = {
      ['textDocument/hover'] = vim.lsp.with(vim.lsp.handlers.hover, { border = 'rounded' }),
      ['textDocument/signatureHelp'] = vim.lsp.with(vim.lsp.handlers.signature_help, { border = 'rounded' }),
    }

    if vim.lsp.inlay_hint then
      local group = vim.api.nvim_create_augroup('NegLspInlayHints', { clear = true })
      vim.api.nvim_create_autocmd('LspAttach', {
        group = group,
        callback = function(event)
          vim.keymap.set('n', '<leader>uh', function()
            local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = event.buf })
            vim.lsp.inlay_hint.enable(not enabled, { bufnr = event.buf })
          end, { buffer = event.buf, desc = 'Inlay Hints: toggle' })
        end,
      })
    end

    local base_config = {
      handlers = handlers,
    }

    local function configure(server, extra)
      local resolved = vim.tbl_deep_extend('force', {}, base_config, extra or {})
      vim.lsp.config(server, resolved)
      vim.lsp.enable(server)
    end

    local signs = { Error = '', Warn = '', Hint = '', Info = '' }
    for type, icon in pairs(signs) do
      local hl = 'DiagnosticSign' .. type
      vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
    end

    configure('bashls')
    configure('clangd', {
      cmd = { 'clangd', '--background-index', '--clang-tidy', '--completion-style=detailed', '--header-insertion=never' },
      init_options = { clangdFileStatus = true },
    })
    configure('cmake')
    configure('nil_ls') -- Nix
    configure('qmlls') -- QML via qt6
    configure('ts_ls') -- TypeScript/JavaScript
    configure('cssls')
    configure('jsonls', {
      filetypes = { 'json', 'jsonc', 'json5' },
    })
    configure('html')
    configure('yamlls')
    configure('taplo')
    configure('lemminx')
    configure('dhall_lsp_server')
    configure('asm_lsp')
    configure('autotools_ls')
    configure('dotls')
    configure('gopls')
    configure('sqls')
    configure('dockerls')
    configure('docker_compose_language_service')
    configure('systemd_language_server')
    configure('nginx_language_server')
    configure('svls')
    configure('vhdl_ls')
    configure('zls')
    configure('awk_ls')
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
    configure('just')
    configure('marksman')

    -- Global LSP/Help keymaps (replace vim-ref behavior)
    Map('n', 'K', function()
      local clients = {}
      if vim.lsp and vim.lsp.get_clients then
        clients = vim.lsp.get_clients({ bufnr = 0 })
      end
      if clients and #clients > 0 then
        return vim.lsp.buf.hover()
      end
      vim.cmd('help ' .. vim.fn.expand('<cword>'))
    end, { desc = 'Hover or :help cword' })

    Map('n', 'gd', function()
      local clients = {}
      if vim.lsp and vim.lsp.get_clients then
        clients = vim.lsp.get_clients({ bufnr = 0 })
      end
      if clients and #clients > 0 then
        return vim.lsp.buf.definition()
      end
      local ok_tb, tb = pcall(require, 'telescope.builtin')
      if ok_tb and tb.lsp_definitions then return tb.lsp_definitions({}) end
    end, { desc = 'Go to definition (LSP/Telescope)' })
  end,
}

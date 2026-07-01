-- Filetype plugins: kdl, qmk, rustaceanvim, tidal
return {
  -- │ █▓▒░ imsnif/kdl.vim                                                           │
  {'imsnif/kdl.vim', ft='kdl'},

  -- │ █▓▒░ codethread/qmk.nvim                                                     │
  {'codethread/qmk.nvim',
    config=function()
      require('qmk').setup {
        name='LAYOUT_preonic_grid',
        layout = {
          "x x x x x x _ _ x x x x x x",
          "x x x x x x _ _ x x x x x x",
          "x x x x x x x^x x x x x x x",
          "_ _ _ x x x x x x x x _ _ _",
        },
        comment_preview = {
          keymap_overrides = {
            ["&trans"] = "", ["&sys_reset"] = "\u{1f504}", ["&bootloader"] = "\u{1f4be}",
            SEMI = ";", FSLH = "/", BSLH = "\\", LBKT = "[", RBKT = "]",
            LBRC = "{", RBRC = "}", SQT = "'", EXCL = "!",
            PRCNT = "%", CARET = "^",
            C_NEXT = "\u{23ed}\u{fe0f}", C_PREV = "\u{23ee}\u{fe0f}", C_PP = "\u{23ef}\u{fe0f}",
            BT_NXT = "\u{1f6dc}\u{1f53c}", BT_PRV = "\u{1f6dc}\u{1f53d}", BT_CLR = "\u{1f6dc}\u{274c}",
            C_MUTE = "\u{1f507}", C_VOL_DN = "\u{1f509}", C_VOL_UP = "\u{1f50a}",
            C_BRI_UP = "\u{1f506}", C_BRI_DN = "\u{1f505}", EP_TOG = "\u{1f50c}",
            AMPS = "&", STAR = "*", LPAR = "(", RPAR = ")",
            MEH = "MEH", K_UNDO = "\u{21a9}\u{fe0f}",
            ["COPY"] = "\u{1f4c4}", ["PASTE"] = "\u{1f4cb}", ["CUT"] = "\u{2702}\u{fe0f}",
            ["LG(Q)"] = "\u{2318}Q", ["LC(W)"] = "\u{2303}W", ["LC(T)"] = "\u{2303}T",
            ["LC(TAB)"] = "\u{2303}\u{21e5}", ["LS(LC(TAB))"] = "\u{21e7}\u{2303}\u{21e5}",
            SPACE = "SPACE", KP_MULTIPLY = "*",
            K_CMENU = "\u{1f30d}", K_MENU = "\u{1f30d}", COMPOSE = "\u{1f30d}",
            LEFT = "\u{2190}", RIGHT = "\u{2192}", UP = "\u{2191}", DOWN = "\u{2193}",
            KP_PLUS = "+", DQT = '"',
            PG_UP = "\u{21de}", PG_DN = "\u{21df}", HOME = "\u{21f1}", END = "\u{21f2}",
            _LTX = "", _LMX = "", _LBX = "", _LHX = "",
            _RTX = "", _RMX = "", _RBX = "", _RHX = "",
            _MTX = "", _MMX = "", _MBX = "", _MHX = "",
          },
          symbols = { tl = "\u{256d}", tr = "\u{256e}", bl = "\u{2570}", br = "\u{256f}" },
        },
      }
    end, ft='dts', lazy=true},

  -- │ █▓▒░ mrcjkb/rustaceanvim                                                     │
  {
    'mrcjkb/rustaceanvim',
    version = '^6',
    ft = { 'rust' },
    init = function()
      local function on_attach(_, bufnr)
        local function map(lhs, rhs, desc)
          vim.keymap.set('n', lhs, rhs, { buffer = bufnr, silent = true, desc = desc })
        end
        map('<leader>rr', function() vim.cmd.RustLsp('runnables') end, 'Rust runnables')
        map('<leader>rR', function() vim.cmd.RustLsp({ 'runnables', bang = true }) end, 'Rust rerun last runnable')
        map('<leader>rd', function() vim.cmd.RustLsp('debuggables') end, 'Rust debuggables')
        map('<leader>rt', function() vim.cmd.RustLsp('testables') end, 'Rust testables')
        map('<leader>re', function() vim.cmd.RustLsp('explainError') end, 'Rust explain error')
        map('<leader>rD', function() vim.cmd.RustLsp('renderDiagnostic') end, 'Rust render diagnostic')
        map('<leader>ra', function() vim.cmd.RustLsp('codeAction') end, 'Rust code actions')
        map('<leader>rl', function() vim.cmd.RustLsp('relatedDiagnostics') end, 'Rust related diagnostics')
        map('<leader>rk', function() vim.cmd.RustLsp({ 'flyCheck', 'run' }) end, 'Rust fly check run')
        map('<leader>rK', function() vim.cmd.RustLsp({ 'flyCheck', 'clear' }) end, 'Rust fly check clear')
        map('<leader>ro', function() vim.cmd.RustLsp('openDocs') end, 'Rust open docs.rs')
        map('<leader>rC', function() vim.cmd.RustLsp('openCargo') end, 'Rust open Cargo.toml')
        map('<leader>rS', function()
          local query = vim.fn.input('workspace symbol: ')
          if query == nil then return end
          vim.cmd.RustLsp({ 'workspaceSymbol', 'allSymbols', query, bang = true })
        end, 'Rust workspace symbol (with deps)')
        map('<leader>rg', function() vim.cmd.RustLsp('crateGraph') end, 'Rust crate graph')
        map('<leader>rv', function()
          local view = vim.fn.input('view hir/mir: ')
          if view == nil or view == '' then return end
          vim.cmd.RustLsp({ 'view', view })
        end, 'Rust view HIR/MIR')
        map('<leader>ru', function()
          local kind = vim.fn.input('rustc unpretty (hir/mir/...): ')
          if kind == nil or kind == '' then return end
          vim.cmd.Rustc({ 'unpretty', kind })
        end, 'Rustc unpretty')
        map('<leader>rp', function() vim.cmd.RustLsp('rebuildProcMacros') end, 'Rust rebuild proc macros')
        map('<leader>rM', function() vim.cmd.RustLsp('parentModule') end, 'Rust parent module')
        map('<leader>rH', function() vim.cmd.RustLsp({ 'hover', 'range' }) end, 'Rust hover range')
        map('<leader>rA', function()
          local cfg = vim.fn.input('rust-analyzer config (Lua table): ')
          if cfg == nil or cfg == '' then return end
          vim.cmd.RustAnalyzer({ 'config', cfg })
        end, 'RustAnalyzer config')
        map('<leader>rT', function()
          local tgt = vim.fn.input('rust-analyzer target (empty = default): ')
          if tgt == nil then return end
          if tgt == '' then
            vim.cmd.RustAnalyzer('target')
          else
            vim.cmd.RustAnalyzer({ 'target', tgt })
          end
        end, 'RustAnalyzer target')
        map('K', function() vim.cmd.RustLsp({ 'hover', 'actions' }) end, 'Rust hover actions')
      end
      vim.g.rustaceanvim = {
        tools = { test_executor = 'neotest', code_actions = { ui_select_fallback = true } },
        server = {
          on_attach = on_attach,
          default_settings = {
            ['rust-analyzer'] = {
              cargo = { buildScripts = { enable = true } },
              procMacro = { enable = true },
            },
          },
        },
        dap = { autoload_configurations = true },
      }
    end,
  },

  -- │ █▓▒░ grddavies/tidal.nvim                                                    │
  {
    'grddavies/tidal.nvim',
    event = { 'BufRead *.tidal', 'BufNewFile *.tidal' },
    keys = {
      { '<C-CR>', '<Cmd>TidalLaunch<CR>', ft = 'haskell', desc = 'Launch Tidal + SuperDirt' },
      { '<C-S-CR>', '<Cmd>TidalQuit<CR>', ft = 'haskell', desc = 'Quit Tidal' },
    },
    opts = {
      boot = {
        tidal = { file = '/usr/share/haskell-tidal/BootTidal.hs' },
        sclang = { enabled = true, file = '~/.config/SuperCollider/boot_noop.scd' },
      },
    },
  },
}

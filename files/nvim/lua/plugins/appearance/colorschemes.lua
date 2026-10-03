-- Appearance plugins (excluding neg.nvim colorscheme which has its own spec)
return {
  -- │ █▓▒░ aileot/ex-colors.nvim                                                   │
  -- Extract current highlight definitions and generate a fast ex-<scheme>.
  {
    'aileot/ex-colors.nvim',
    cmd = { 'ExColors' },
    opts = {},
  },
  -- │ █▓░ nvim-treesitter/nvim-treesitter                                           │
  -- Branch `main`: setup() takes install_dir only, while ensure_installed /
  -- auto_install / highlight / incremental_selection belong to the master API and
  -- are silently ignored here. Parsers are installed via install(); highlighting
  -- turns on by itself once a parser is available.
  {
    'nvim-treesitter/nvim-treesitter',
    event = { 'BufReadPost', 'BufNewFile' },
    config = function()
      local langs = {
        'bash', 'c', 'cpp', 'cmake', 'css', 'dockerfile', 'dot',
        -- no jsonc: main has no such language, the json parser covers the filetype
        'go', 'haskell', 'html', 'json', 'lua', 'luadoc', 'make',
        'markdown', 'markdown_inline', 'nix', 'python', 'regex', 'rust', 'toml',
        'typescript', 'vim', 'vimdoc', 'yaml',
      }

      -- main builds parsers through tree-sitter-cli (>= 0.26.1). Without it
      -- install() only spams the log, so check the binary first.
      if vim.fn.executable('tree-sitter') ~= 1 then
        vim.notify(
          'treesitter: tree-sitter-cli is missing - parsers are not installed (nix: add tree-sitter-cli)',
          vim.log.levels.WARN
        )
        return
      end

      require('nvim-treesitter').install(langs)

      -- Stand-in for master's auto_install: fetch the parser for a new filetype
      -- when nvim-treesitter.parsers knows that language.
      local parsers = require('nvim-treesitter.parsers')
      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('NegTreesitterAutoInstall', { clear = true }),
        callback = function(args)
          local ft = vim.bo[args.buf].filetype
          if ft ~= '' and parsers[ft] then
            require('nvim-treesitter').install({ ft })
          end
        end,
      })
    end,
  },
}

{
  lib,
  config,
  ...
}: let
  xdg = import ../../../lib/xdg-helpers.nix {inherit lib;};
in
  # Live-editable config and tiny init for kitty-scrollback.nvim kitten
  lib.mkMerge [
    (xdg.mkXdgSource "nvim" {
      source = config.lib.file.mkOutOfStoreSymlink "${config.neg.dotfilesRoot}/nvim/.config/nvim";
      recursive = true;
    })
    (xdg.mkXdgText "ksb-nvim/init.lua" ''
      -- Minimal init for kitty-scrollback.nvim kitten: fast and isolated
      vim.g.loaded_node_provider = 0
      vim.g.loaded_python3_provider = 0
      vim.g.loaded_ruby_provider = 0
      vim.g.loaded_perl_provider = 0
      vim.opt.swapfile = false
      vim.opt.shadafile = "NONE"

      -- Provide a lightweight user config namespace for kitty-scrollback.nvim
      -- Add a 'screen' config that limits extent to the visible screen only
      pcall(function()
        local ksb = require('kitty-scrollback')
        if type(ksb.setup) == 'function' then
          ksb.setup({
            screen = { kitty_get_text = { extent = 'screen' } },
          })
        end
      end)

      -- Optional: open file under terminal cursor when requested
      -- Triggered only when called with `--env KSB_OPEN_GF=1`
      if vim.env.KSB_OPEN_GF == '1' then
        vim.api.nvim_create_autocmd({ 'FileType' }, {
          group = vim.api.nvim_create_augroup('KittyScrollbackOpenFileUnderCursor', { clear = true }),
          pattern = { 'kitty-scrollback' },
          once = true,
          callback = function()
            -- Open file under cursor (gf) once the scrollback buffer is ready
            vim.schedule(function()
              pcall(vim.cmd.normal, { 'gf', bang = true })
            end)
            return true
          end,
        })
      end
    '')
  ]

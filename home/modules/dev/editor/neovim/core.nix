{
  lib,
  pkgs,
  ...
}: {
  programs.neovim = {
    plugins =
      [
        pkgs.vimPlugins.clangd_extensions-nvim # extra clangd LSP features (inlay hints, etc.)
        pkgs.vimPlugins.nvim-treesitter # incremental parsing/highlighting
      ]
      ++ lib.optional (pkgs.vimPlugins ? kitty-scrollback-nvim) pkgs.vimPlugins.kitty-scrollback-nvim;
    extraLuaConfig = ''
      -- put parsers in a writable dir and ensure it is early on rtp
      local parser_dir = vim.fn.stdpath("data") .. "/treesitter"
      vim.fn.mkdir(parser_dir, "p")
      require("nvim-treesitter.install").prefer_git = true
      require("nvim-treesitter.install").compilers = { "cc", "clang", "gcc" }
      require("nvim-treesitter.parsers").get_parser_configs().vim = require("nvim-treesitter.parsers").get_parser_configs().vim
      -- make sure Neovim sees user-built parsers first
      vim.opt.runtimepath:prepend(parser_dir)
      vim.g.ts_install_dir = parser_dir

      -- Telescope: ls-like grid picker with dynamic columns
      -- Shows files in N columns based on window width and max filename length.
      -- Open item in column 1..N via numeric keys (1..9). Enter opens column 1.
      local function telescope_files_lsgrid(opts)
        opts = opts or {}
        local entry_display = require('telescope.pickers.entry_display')
        local finders       = require('telescope.finders')
        local pickers       = require('telescope.pickers')
        local conf          = require('telescope.config').values
        local actions       = require('telescope.actions')
        local action_state  = require('telescope.actions.state')
        local Job_ok, Job   = pcall(require, 'plenary.job')
        if not Job_ok then
          vim.notify('plenary.nvim is required for ls-grid picker', vim.log.levels.WARN)
          return
        end

        -- Collect files via fd (fast). You can switch to plenary.scandir if desired.
        local cmd = { 'fd', '--type', 'f', '--hidden', '--follow', '--exclude', '.git' }
        local sep = '  '  -- separator between columns
        local left_margin = 6  -- extra space for borders/icons

        local function compute_layout(names)
          -- find longest tail (basename), clamp width 12..40 chars
          local maxlen = 0
          for _, n in ipairs(names) do
            local tail = n:match('([^/]+)$') or n
            if #tail > maxlen then maxlen = #tail end
          end
          local col_width = math.min(math.max(maxlen, 12), 40)
          local wincols = vim.o.columns
          local cell = col_width + #sep
          local cols = math.max(1, math.floor((wincols - left_margin + #sep) / cell))
          return cols, col_width
        end

        local function make_entries(paths, cols, col_width)
          local function pad(s, w)
            if #s > w then return s:sub(1, w - 1) .. '…' end
            return s .. string.rep(' ', w - #s)
          end

          local entries = {}
          for i = 1, #paths, cols do
            local group = {}
            for j = 0, cols - 1 do
              local p = paths[i + j]
              if p then table.insert(group, p) end
            end

            local items = {}
            for k = 1, cols do
              local p = group[k]
              local name = p and (p:match('([^/]+)$') or p) or ""
              items[k] = pad(name, col_width)
            end

            table.insert(entries, {
              value   = group,
              ordinal = table.concat(group, ' '),
              display = function()
                -- build displayer for current number of columns
                local cols_spec = {}
                for k = 1, cols do
                  cols_spec[k] = { width = col_width }
                end
                local displayer = entry_display.create({ separator = sep, items = cols_spec })
                return displayer(items)
              end,
              paths = group,
            })
          end
          return entries
        end

        Job:new({
          command = cmd[1],
          args = vim.list_slice(cmd, 2),
          on_exit = function(j, code)
            local lines = j:result()
            if code ~= 0 then
              vim.schedule(function() vim.notify('fd exited ' .. code, vim.log.levels.WARN) end)
            end
            -- layout like ls: compute columns/width and chunk results
            local cols, col_width = compute_layout(lines)
            local results = make_entries(lines, cols, col_width)

            vim.schedule(function()
              pickers.new(opts, {
                prompt_title = string.format('Files (ls grid: %d cols, %d ch)', cols, col_width),
                finder = finders.new_table({
                  results = results,
                  entry_maker = function(x) return x end,
                }),
                sorter    = conf.generic_sorter(opts),
                previewer = conf.file_previewer(opts),
                attach_mappings = function(prompt_bufnr, map)
                  local function open_idx(idx, cmd)
                    local entry = action_state.get_selected_entry()
                    local path = entry and entry.paths and entry.paths[idx]
                    if path then
                      actions.close(prompt_bufnr)
                      if cmd == 'vsplit' then
                        vim.cmd.vsplit(vim.fn.fnameescape(path))
                      elseif cmd == 'split' then
                        vim.cmd.split(vim.fn.fnameescape(path))
                      elseif cmd == 'tab' then
                        vim.cmd.tabedit(vim.fn.fnameescape(path))
                      else
                        vim.cmd.edit(vim.fn.fnameescape(path))
                      end
                    else
                      vim.notify('No item #' .. idx, vim.log.levels.WARN)
                    end
                  end

                  -- digits 1..min(cols,9) open corresponding column
                  local max_key = math.min(cols, 9)
                  for i = 1, max_key do
                    map('i', tostring(i), function() open_idx(i) end)
                    map('n', tostring(i), function() open_idx(i) end)
                  end

                  -- Enter opens first column
                  actions.select_default:replace(function() open_idx(1) end)

                  -- Additional: Ctrl-v / Ctrl-x / Ctrl-t like Telescope defaults
                  map('i', '<C-v>', function() open_idx(1, 'vsplit') end)
                  map('i', '<C-x>', function() open_idx(1, 'split') end)
                  map('i', '<C-t>', function() open_idx(1, 'tab') end)
                  map('n', '<C-v>', function() open_idx(1, 'vsplit') end)
                  map('n', '<C-x>', function() open_idx(1, 'split') end)
                  map('n', '<C-t>', function() open_idx(1, 'tab') end)

                  return true
                end,
              }):find()
            end)
          end
        }):start()
      end

      -- Keymap: Files (ls-like grid)
      vim.keymap.set('n', '<leader>t', telescope_files_lsgrid, { desc = 'Files (ls-like grid)' })
    '';
    extraLuaPackages = [pkgs.luajitPackages.magick]; # LuaJIT bindings for ImageMagick
    extraPackages = [pkgs.imagemagick]; # external tool used by some plugins
  };
}

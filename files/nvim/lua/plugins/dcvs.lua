-- DCVS plugins: diffview, flog, gitsigns, neogit
return {
  -- │ █▓▒░ sindrets/diffview.nvim                                                   │
  {'sindrets/diffview.nvim',
    config=function()
      local map = vim.keymap.set
      local actions = require("diffview.actions")
      require('diffview').setup {
        diff_binaries=false,
        enhanced_diff_hl=true,
        use_icons=true,
        icons={folder_closed="", folder_open=""},
        signs={fold_closed="", fold_open=""},
        file_panel={
          listing_style="tree",
          tree_options={flatten_dirs=true, folder_statuses="only_folded"},
          win_config={position="left", width=35},
        },
        file_history_panel={win_config={position="bottom", height=16}},
        default_args={DiffviewOpen={}, DiffviewFileHistory={}},
        hooks={},
        view={
          default={layout="diff2_horizontal"},
          merge_tool={layout="diff3_horizontal", disable_diagnostics=true},
          file_history={layout="diff2_horizontal"},
        },
        keymaps={
          view={
            ["g<C-x>"]=actions.cycle_layout,
            ["[x"]=actions.prev_conflict, ["]x"]=actions.next_conflict,
            ["<leader>co"]=actions.conflict_choose("ours"),
            ["<leader>ct"]=actions.conflict_choose("theirs"),
            ["<leader>cb"]=actions.conflict_choose("base"),
            ["<leader>ca"]=actions.conflict_choose("all"),
            ["dx"]=actions.conflict_choose("none"),
          },
          diff1={}, diff2={},
          diff3={
            {{"n","x"},"2do",actions.diffget("ours")},
            {{"n","x"},"3do",actions.diffget("theirs")},
          },
          diff4={
            {{"n","x"},"1do",actions.diffget("base")},
            {{"n","x"},"2do",actions.diffget("ours")},
            {{"n","x"},"3do",actions.diffget("theirs")},
          },
          file_panel={
            ["g<C-x>"]=actions.cycle_layout,
            ["[x"]=actions.prev_conflict, ["]x"]=actions.next_conflict,
          },
          file_history_panel={["g<C-x>"]=actions.cycle_layout},
        },
      }
      map('n', '<C-S-g>', '<Cmd>DiffviewFileHistory<CR>', {desc='Diffview file history'})
      map('n', '\\a', '<Cmd>DiffviewOpen<CR>', {desc='Diffview open'})
      map('n', '\\c', '<Cmd>DiffviewClose<CR>', {desc='Diffview close'})
      map('n', '\\r', '<Cmd>DiffviewRefresh<CR>', {desc='Diffview refresh'})
      map('n', '\\f', '<Cmd>DiffviewToggleFiles<CR>', {desc='Diffview toggle files'})
      map('n', '\\0', '<Cmd>DiffviewOpen HEAD<CR>', {desc='Diffview HEAD'})
      map('n', '\\1', '<Cmd>DiffviewOpen HEAD^<CR>', {desc='Diffview HEAD^'})
      map('n', '\\2', '<Cmd>DiffviewOpen HEAD^^<CR>', {desc='Diffview HEAD^^'})
      map('n', '\\3', '<Cmd>DiffviewOpen HEAD^^^<CR>', {desc='Diffview HEAD^^^'})
      map('n', '\\4', '<Cmd>DiffviewOpen HEAD^^^^<CR>', {desc='Diffview HEAD^^^^'})
    end,
    cmd={'DiffviewOpen','DiffviewFileHistory'},
    dependencies={'nvim-tree/nvim-web-devicons','nvim-lua/plenary.nvim'},
    keys={'<C-S-G>','\\a','\\c','\\r','\\f','\\0','\\1','\\2','\\3','\\4'}, lazy=true},

  -- │ █▓▒░ rbong/vim-flog                                                           │
  {
    "rbong/vim-flog",
    dependencies = { "tpope/vim-fugitive" },
    cmd = { "Flog", "G", "GBrowse", "GDelete", "GMove", "GRemove",
      "GRename", "GUnlink", "Gcd", "Gclog", "Gdiffsplit", "Gdrop",
      "Gedit", "Ggrep", "Ghdiffsplit", "Git", "Glcd", "Glgrep", "Gllog",
      "Gpedit", "Gread", "Gsplit", "Gtabedit", "Gvdiffsplit", "Gvsplit",
      "Gwq", "Gwrite",
    },
  },

  -- │ █▓▒░ lewis6991/gitsigns.nvim                                                  │
  {'lewis6991/gitsigns.nvim',
    config=function()
      require('gitsigns').setup {
        on_attach = function(bufnr)
          local gs = require('gitsigns')
          local function bmap(mode, lhs, rhs, desc)
            vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, silent = true, desc = desc })
          end
          bmap('n', '<leader>b', gs.preview_hunk, 'Git: preview hunk')
          bmap('n', '<leader>q', function() gs.blame_line({full=true}) end, 'Git: blame line (full)')
          bmap('n', '<leader>gB', gs.blame_line, 'Git: blame line')
          bmap('n', '<leader>g]', gs.next_hunk, 'Git: next hunk')
          bmap('n', '<leader>g[', gs.prev_hunk, 'Git: prev hunk')
          bmap('n', '<leader>g?', gs.preview_hunk, 'Git: preview hunk')
          bmap('n', '<leader>gs', gs.stage_hunk, 'Git: stage hunk')
          bmap('v', '<leader>gs', function() gs.stage_hunk({vim.fn.line('.'), vim.fn.line('v')}) end, 'Git: stage hunk (visual)')
          bmap('n', '<leader>gr', gs.reset_hunk, 'Git: reset hunk')
          bmap('v', '<leader>gr', function() gs.reset_hunk({vim.fn.line('.'), vim.fn.line('v')}) end, 'Git: reset hunk (visual)')
          bmap('n', '<leader>gS', gs.stage_buffer, 'Git: stage buffer')
          bmap('n', '<leader>gR', gs.reset_buffer, 'Git: reset buffer')
          bmap('n', '<leader>gu', gs.undo_stage_hunk, 'Git: undo stage hunk')
        end,
        signs={
          add={text='▎', show_count=false},
          change={text='▎', show_count=false},
          delete={text='_', show_count=false},
          topdelete={text='‾', show_count=false},
          changedelete={text='~', show_count=false},
        },
        count_chars={
          [1]="", [2]="₂", [3]="₃",
          [4]="₄", [5]="₅", [6]="₆",
          [7]="₇", [8]="₈", [9]="₉",
          ["+"]="₊",
        },
        linehl=false, numhl=false, signcolumn=true, word_diff=false,
        watch_gitdir={interval=500, follow_files=true},
        sign_priority=6, update_debounce=100, max_file_length=40000,
        diff_opts={ algorithm="patience", internal=true, indent_heuristic=true },
        attach_to_untracked=true, current_line_blame=false,
        current_line_blame_opts={
          virt_text=true, virt_text_pos='eol', delay=1000, ignore_whitespace=false,
        },
      }
    end,
    event={'BufReadPost','BufNewFile'}},

  -- │ █▓▒░ NeogitOrg/neogit                                                         │
  {'NeogitOrg/neogit',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'sindrets/diffview.nvim',
      'ibhagwan/fzf-lua',
    },
    cmd = "Neogit",
    config = true},
}

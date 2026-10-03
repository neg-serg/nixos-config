return {
  'nvim-treesitter/nvim-treesitter-textobjects',
  event = { 'BufReadPost', 'BufNewFile' },
  dependencies = { 'nvim-treesitter/nvim-treesitter' },
  -- The main branch ships no default mappings: without setup() and own maps the
  -- plugin just stays installed and silent.
  config = function()
    require('nvim-treesitter-textobjects').setup({
      select = {
        lookahead = true, -- like targets.vim: jump forward to the object
        selection_modes = {
          ['@parameter.outer'] = 'v',
          ['@function.outer'] = 'V',
          ['@class.outer'] = 'V',
        },
        include_surrounding_whitespace = false,
      },
      move = { set_jumps = true },
    })

    local ts_select = require('nvim-treesitter-textobjects.select')
    local ts_move = require('nvim-treesitter-textobjects.move')
    local map = vim.keymap.set

    -- Selecting objects: am/im for functions, ac/ic for classes.
    -- af/if, aa/ia and ab/ib stay untouched: mini.ai already owns those letters.
    map({ 'x', 'o' }, 'am', function() ts_select.select_textobject('@function.outer', 'textobjects') end, { desc = 'TS: функция (вокруг)' })
    map({ 'x', 'o' }, 'im', function() ts_select.select_textobject('@function.inner', 'textobjects') end, { desc = 'TS: функция (внутри)' })
    map({ 'x', 'o' }, 'ac', function() ts_select.select_textobject('@class.outer', 'textobjects') end, { desc = 'TS: класс (вокруг)' })
    map({ 'x', 'o' }, 'ic', function() ts_select.select_textobject('@class.inner', 'textobjects') end, { desc = 'TS: класс (внутри)' })

    -- Motion: ]m/[m for a function start, ]M/[M for its end, ]a/[a for an argument.
    local modes = { 'n', 'x', 'o' }
    map(modes, ']m', function() ts_move.goto_next_start('@function.outer', 'textobjects') end, { desc = 'TS: след. функция' })
    map(modes, '[m', function() ts_move.goto_previous_start('@function.outer', 'textobjects') end, { desc = 'TS: пред. функция' })
    map(modes, ']M', function() ts_move.goto_next_end('@function.outer', 'textobjects') end, { desc = 'TS: конец след. функции' })
    map(modes, '[M', function() ts_move.goto_previous_end('@function.outer', 'textobjects') end, { desc = 'TS: конец пред. функции' })
    map(modes, ']a', function() ts_move.goto_next_start('@parameter.outer', 'textobjects') end, { desc = 'TS: след. аргумент' })
    map(modes, '[a', function() ts_move.goto_previous_start('@parameter.outer', 'textobjects') end, { desc = 'TS: пред. аргумент' })
  end,
}

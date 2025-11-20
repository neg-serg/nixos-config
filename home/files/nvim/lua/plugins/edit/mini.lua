-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ echasnovski/mini.nvim                                                       │
-- └───────────────────────────────────────────────────────────────────────────────────┘
-- Configure selected mini.nvim modules. Start with mini.align to replace
-- vim-easy-align and reuse the familiar `ga` mappings.
return {
  'echasnovski/mini.nvim',
  config = function()
    local ok_align, align = pcall(require, 'mini.align')
    if ok_align then
      align.setup()
      -- Use function mappings to mimic EasyAlign UX
      Map('x', 'ga', function() align.operator(align.gen_spec.input()) end, { desc = 'Align (visual)' })
      Map('n', 'ga', function() align.operator(align.gen_spec.input()) end, { desc = 'Align (operator)' })
    end
    -- Trailing whitespace helper (replaces trim.nvim). No auto-trim on write.
    local ok_ts, trail = pcall(require, 'mini.trailspace')
    if ok_ts then
      trail.setup()
      -- Optional manual trim command example (kept commented to match previous behavior):
      -- Map('n', '<leader>tw', function() trail.trim() end, { desc = 'Trim trailing whitespace' })
    end

    -- Split/Join (replaces treesj): simple toggle on <leader>a
    local ok_sj, sj = pcall(require, 'mini.splitjoin')
    if ok_sj then
      sj.setup()
      Map('n', '<leader>a', function() sj.toggle() end, { desc = 'Split/Join toggle' })
    end

    -- Surround (replaces kylechui/nvim-surround) with your preferred keymaps.
    local ok_sur, surround = pcall(require, 'mini.surround')
    if ok_sur then
      surround.setup({
        mappings = {
          add = 'cs',       -- add surrounding (Normal/Visual)
          delete = 'ds',    -- delete surrounding
          replace = 'ys',   -- replace surrounding
          find = '',        -- disable extras unless needed
          find_left = '',
          highlight = '',
          suffix_last = 'l',
          suffix_next = 'n',
        },
        respect_selection_type = true,
      })
      -- Visual add: keep 'S' (like previous plugin)
      Map('x', 'S', function() require('mini.surround').add('visual') end, { desc = 'Surround (visual)' })
      -- Visual line add: 'gS' – promote selection to linewise, then add
      Map('x', 'gS', function()
        vim.cmd('normal! gvV')
        require('mini.surround').add('visual')
      end, { desc = 'Surround (visual line)' })
      -- Current line add (cSS equivalent): map to linewise add on current line
      vim.keymap.set('n', 'cSS', 'cs_', { remap = true, desc = 'Surround current line' })
      -- Convenience: keep your csw -> csiw shortcut
      vim.keymap.set('n', 'csw', 'csiw', { remap = true })
      vim.keymap.set('n', 'csW', 'csiW', { remap = true })
    end
  end,
}

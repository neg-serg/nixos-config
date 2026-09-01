-- SuperCollider live coding: edit .scd files and evaluate into a sclang
-- session (scnvim). The engine runs INSIDE this session: sclang is launched
-- via the sclang-pwj wrapper (pw-jack), so s.boot starts scsynth as a
-- PipeWire-JACK client — no separate engine service, no TidalCycles.
-- Live scene:  sc-live  (opens ~/notes/music/supercollider/live.scd)
return {
  {
    'davidgranstrom/scnvim',
    ft = 'supercollider', -- nvim maps .scd to this filetype natively
    config = function()
      local scnvim = require 'scnvim'
      local map = scnvim.map
      scnvim.setup({
        -- Launch sclang through the pw-jack wrapper so scsynth can boot with
        -- a working audio backend (JACK ports linked by supercollider-link).
        sclang = {
          cmd = vim.fn.expand '~/.local/bin/sclang-pwj',
        },
        keymaps = {
          ['<M-CR>'] = map('editor.send_line', { 'n', 'i' }),
          ['<leader>ss'] = map('editor.send_selection', 'x'),
          ['<leader>sb'] = map('editor.send_block', { 'n', 'x' }),
          ['<leader>sc'] = map('sclang.start'),
          ['<leader>sx'] = map('sclang.stop'),
        },
      })
    end,
  },
}

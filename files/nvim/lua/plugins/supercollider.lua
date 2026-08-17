-- SuperCollider live coding: edit .scd files and evaluate into a sclang
-- session (scnvim). The audio engine (SuperDirt) runs separately via
-- `tidalctl start`; this REPL is for iterating on SynthDefs/UGens before
-- putting them into ~/notes/music/supercollider/synths.scd.
return {
  {
    'davidgranstrom/scnvim',
    ft = 'supercollider', -- nvim maps .scd to this filetype natively
    config = function()
      local scnvim = require 'scnvim'
      local map = scnvim.map
      scnvim.setup({
        -- sclang is found via PATH (system supercollider); no server boot —
        -- the engine's scsynth (tidalctl) owns 57110, so we stay language-only.
        -- Keymaps are applied buffer-locally on FileType supercollider, so
        -- Tidal's <M-CR> semantics for .tidal files stay untouched.
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

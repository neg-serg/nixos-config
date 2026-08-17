-- SuperCollider live coding: edit .scd files and evaluate into a sclang
-- session (scnvim). The audio engine (SuperDirt) runs separately via
-- `tidalctl start`; this REPL is for iterating on SynthDefs/UGens before
-- putting them into ~/notes/music/supercollider/synths.scd.
return {
  {
    'davidgranstrom/scnvim',
    build = 'cargo build --release',
    ft = 'scd',
    keys = {
      { '<M-CR>', '<cmd>SCNvimSendLine<cr>', desc = 'Send line to sclang', buffer = true },
      { '<leader>ss', '<cmd>SCNvimSendSelection<cr>', desc = 'Send selection to sclang', buffer = true },
      { '<leader>sb', '<cmd>SCNvimSendBlock<cr>', desc = 'Send block to sclang', buffer = true },
      { '<leader>sc', '<cmd>SCNvimStart<cr>', desc = 'Start sclang session', buffer = true },
      { '<leader>sx', '<cmd>SCNvimStop<cr>', desc = 'Stop sclang session', buffer = true },
    },
    config = function()
      vim.filetype.add({ extension = { scd = 'scd' } })
      require('scnvim').setup({
        -- sclang is found via PATH (system supercollider); no server boot —
        -- the engine's scsynth (tidalctl) owns 57110, so we stay language-only.
        sclang = {
          pipename = vim.fn.stdpath('run') .. '/scnvim',
        },
        editor = {
          -- keep Tidal's <M-CR> semantics for .tidal files untouched
          send_selection_key = nil,
          send_line_key = nil,
          send_block_key = nil,
        },
      })
    end,
  },
}

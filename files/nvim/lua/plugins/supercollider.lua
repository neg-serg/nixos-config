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
      local send = function(expr)
        return function()
          require('scnvim.sclang').send(expr)
        end
      end
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
          -- transport: silence / volume / reboot
          ['<leader>sh'] = send 's.freeAll; Ndef.clear; Pdef.all.do(_.stop); "hush".postln;',
          ['<leader>s+'] = send 's.volume = (s.volume + 0.1).min(1.5); "vol: ".post; s.volume.postln;',
          ['<leader>s-'] = send 's.volume = (s.volume - 0.1).max(0); "vol: ".post; s.volume.postln;',
          ['<leader>s0'] = send 's.volume = 1; "vol reset to 1".postln;',
          ['<leader>sr'] = map('sclang.recompile'),
        },
      })
    end,
  },
}

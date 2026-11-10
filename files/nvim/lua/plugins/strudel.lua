-- Strudel live coding: the browser engine (strudel.cc) plays the audio while
-- Neovim stays the editor. strudel.nvim keeps one *.str buffer in two-way sync
-- with Strudel's own code editor and exposes :StrudelToggle / :StrudelUpdate.
-- It is the JavaScript sibling of the TidalCycles setup (plugins/filetypes.lua)
-- and sits next to supercollider.lua, the other live-coding engine.
--
-- Deliberately not lazy: setup() registers the *.str/*.std filetype autocmd,
-- and lazy loading that setup is the known upstream breakage (gruvw/strudel.nvim#5).
--
-- The build installs puppeteer into the plugin dir. Its bundled Chromium
-- download is skipped — the Nix store browser cannot be patched by npm — and
-- puppeteer drives the system Vivaldi instead (Chromium-based, on demand in the
-- profile). node/npm come from hosts/trantor/default.nix.
return {
  'gruvw/strudel.nvim',
  lazy = false,
  build = 'PUPPETEER_SKIP_DOWNLOAD=1 npm ci',
  config = function()
    local strudel = require('strudel')
    local vivaldi = vim.fn.exepath('vivaldi')
    strudel.setup({
      -- Omitted when Vivaldi is not on PATH: the option defaults to nil and
      -- puppeteer would then look for its own (never downloaded) browser.
      browser_exec_path = vivaldi ~= '' and vivaldi or nil,
    })

    -- Buffer-local maps mirroring the Tidal ones: <leader>s* stays the
    -- live-coding engine prefix, <M-CR> evaluates the current buffer.
    vim.api.nvim_create_autocmd({ 'BufRead', 'BufNewFile' }, {
      pattern = { '*.str', '*.std' },
      callback = function(ev)
        local set = function(lhs, rhs, desc)
          vim.keymap.set('n', lhs, rhs, { buffer = ev.buf, desc = desc })
        end
        set('<M-CR>', strudel.update, 'Strudel: update (evaluate)')
        set('<leader>sl', strudel.launch, 'Strudel: launch')
        set('<leader>sq', strudel.quit, 'Strudel: quit')
        set('<leader>st', strudel.toggle, 'Strudel: toggle play/stop')
        set('<leader>su', strudel.update, 'Strudel: update (evaluate)')
        set('<leader>sS', strudel.stop, 'Strudel: stop playback')
      end,
    })
  end,
}

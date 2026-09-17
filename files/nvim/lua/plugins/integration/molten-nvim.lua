-- ┌───────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ benlubas/molten-nvim — Jupyter kernel REPL + inline cell output          │
-- └───────────────────────────────────────────────────────────────────────────────┘
--
-- Molten is a remote (Python) plugin: every Molten* command is served by a Python
-- host that imports `pynvim` (RPC) and `jupyter_client` (kernel protocol). Neovim's
-- own provider env (`programs.neovim` withPython3) ships pynvim only, so
-- NVIM_PYTHON3_HOST_PROG — exported by modules/dev/python/pkgs.nix — points the
-- provider at the system python env that carries the Jupyter packages (see
-- lib/python-packages.nix). Without that, `:checkhealth molten` reports a missing
-- jupyter_client and `:UpdateRemotePlugins` registers no commands at all.
--
-- `:UpdateRemotePlugins` (the `build` step) regenerates the rplugin manifest that
-- defines the commands in a fresh session. It runs inside lazy's task runner, which
-- does not read this config, so the provider is pinned there a second time.
--
-- Plots/images are rendered through image.nvim, which lazy-loads on
-- `User MoltenInitPost` (see plugins/viz/image-nvim.lua). Molten itself has to be on
-- the rtp before the first kernel starts, because the Python host pulls molten's Lua
-- modules (output_window etc.) back into Neovim — hence the early `VeryLazy` load.
local function pin_python_host()
  -- Unset variable => keep the provider env baked into the neovim wrapper.
  local host = vim.env.NVIM_PYTHON3_HOST_PROG
  if host and host ~= '' then
    vim.g.python3_host_prog = host
  end
end

return {
  'benlubas/molten-nvim',
  version = '^1.0.0', -- 2.x is a breaking rewrite, stay on the 1.x line
  event = 'VeryLazy',
  build = function(plugin)
    pin_python_host()
    vim.opt.rtp:append(plugin.dir) -- the task runner may not have the plugin loaded
    vim.cmd('UpdateRemotePlugins')
  end,
  init = function()
    pin_python_host() -- runs at startup: the provider must be pinned before any Molten command
    vim.g.molten_image_provider = 'image.nvim' -- inline plots in the output window
  end,
  keys = {
    { '<leader>Ji', '<cmd>MoltenInit<cr>', desc = '[Molten] Init kernel' },
    { '<leader>Jl', '<cmd>MoltenEvaluateLine<cr>', desc = '[Molten] Evaluate line' },
    { '<leader>Jr', '<cmd>MoltenReevaluateCell<cr>', desc = '[Molten] Re-evaluate cell' },
    { '<leader>Jv', '<cmd>MoltenEvaluateVisual<cr>', mode = 'x', desc = '[Molten] Evaluate selection' },
    { '<leader>Je', '<cmd>MoltenEvaluateOperator<cr>', desc = '[Molten] Evaluate operator' },
    { '<leader>Jo', '<cmd>MoltenEnterOutput<cr>', desc = '[Molten] Enter output window' },
    { '<leader>Jh', '<cmd>MoltenHideOutput<cr>', desc = '[Molten] Hide output' },
    { '<leader>Jd', '<cmd>MoltenDelete<cr>', desc = '[Molten] Delete cell' },
    { '<leader>Jc', '<cmd>MoltenInterrupt<cr>', desc = '[Molten] Interrupt kernel' },
  },
}

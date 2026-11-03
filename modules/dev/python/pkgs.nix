{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.features.dev.python;

  # The full interpreter env (lib/python-packages.nix: numpy/scipy/jupyter/…)
  # left the system closure — it is ~1.3 GiB of exclusive paths, and the
  # `python` devshell already builds exactly that list. Neovim still needs a
  # small host interpreter for molten-nvim, so keep only that here.
  nvimHostEnv = pkgs.python3.withPackages (ps: [
    ps.pynvim # Neovim's Python client
    ps.jupyter-client # molten-nvim hosts its Jupyter kernel through it
    ps.ipykernel # default python3 kernel (`:MoltenInit python3`)
    ps.nbformat # MoltenImport/ExportOutput .ipynb handling
    ps.debugpy # nvim-dap python adapter (`python3 -m debugpy.adapter`)
  ]);
in
{
  config = lib.mkIf (cfg.core or true) {
    environment.systemPackages = [
      nvimHostEnv
    ]
    ++ lib.optionals (cfg.tools or false) [ pkgs.python3Packages.python-lsp-server ];
    # Neovim's Python provider (programs.neovim.withPython3) ships pynvim only, so
    # remote plugins needing more (molten-nvim → jupyter_client) point Neovim at
    # this env instead: lua/plugins/integration/molten-nvim.lua reads the variable.
    environment.sessionVariables.NVIM_PYTHON3_HOST_PROG = "${nvimHostEnv}/bin/python3";
    # Molten (like any Jupyter client) writes the kernel connection file into
    # $XDG_DATA_HOME/jupyter/runtime and aborts when that directory is missing.
    systemd.user.tmpfiles.rules = [ "d %h/.local/share/jupyter/runtime 0700 - - -" ];
  };
}

{
  lib,
  config,
  pkgs,
  xdg,
  ...
}:
lib.mkIf (config.features.gui.enable or false) (lib.mkMerge [
  (let mkLocalBin = import ../../../../packages/lib/local-bin.nix {inherit lib;}; in mkLocalBin "kitty-panel" (builtins.readFile ./kitty/panel))
  # Robust kitty-scrollback-nvim kitten wrapper (local-bin) and env hint
  (let
    mkLocalBin = import ../../../../packages/lib/local-bin.nix {inherit lib;};
    nixKsbPath =
      if pkgs.vimPlugins ? kitty-scrollback-nvim
      then "${pkgs.vimPlugins.kitty-scrollback-nvim}/python/kitty_scrollback_nvim.py"
      else "";
  in
    mkLocalBin "kitty-scrollback-nvim" ''      #!/usr/bin/env python3
      import os
      import sys
      import importlib.util

      LAZY_KSB = os.path.expanduser("~/.local/share/nvim/lazy/kitty-scrollback.nvim/python/kitty_scrollback_nvim.py")
      NIX_KSB = """${nixKsbPath}"""

      def _resolve_path():
          for p in [NIX_KSB, LAZY_KSB]:
              if p and os.path.exists(p):
                  return p
          return None

      _path = _resolve_path()
      if not _path:
          print("kitty-scrollback-nvim: kitten not found (lazy or nix)", file=sys.stderr)
          sys.exit(1)

      spec = importlib.util.spec_from_file_location("kitty_scrollback_nvim_impl", _path)
      if spec is None or spec.loader is None:
          print(f"failed to load spec for {_path}", file=sys.stderr)
          sys.exit(1)
      mod = importlib.util.module_from_spec(spec)
      spec.loader.exec_module(mod)

      # Expose kitten API by delegating to the real module
      def main(args):
          return mod.main(args)

      def handle_result(args, data, target_window_id, boss):
          return mod.handle_result(args, data, target_window_id, boss)

      def is_main_thread():
          f = getattr(mod, "is_main_thread", None)
          return f() if callable(f) else False
    '')
  (lib.mkIf (pkgs.vimPlugins ? kitty-scrollback-nvim) {
    # Hint the dynamic kitten in conf/kittens/ to the Nix path when present
    home.sessionVariables.KITTY_KSB_NIX_PATH = "${pkgs.vimPlugins.kitty-scrollback-nvim}/python/kitty_scrollback_nvim.py";
  })
  # Live-editable config via helper (guards parent dir and target)
  (xdg.mkXdgSource "kitty" {
    source = config.lib.file.mkOutOfStoreSymlink "${config.neg.hmConfigRoot}/modules/user/gui/kitty/conf";
    recursive = true;
  })
])

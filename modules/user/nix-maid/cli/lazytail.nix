##
# Module: nix-maid/cli/lazytail
# Purpose: LazyTail terminal log viewer — global source list, rendering presets
# for those sources, and the neg.nvim theme (files/lazytail/themes/neg.yaml).
# The package itself is installed by modules/cli/tools.nix; the `lt`/`ltc` shell
# aliases live in files/shell/zsh/02-cmds.zsh. Captured sources (`cmd | lazytail -n NAME`) are
# written to ~/.config/lazytail/data/ at runtime and are deliberately not
# managed here.
{ config, neg, ... }:

{
  config = neg.mkHomeFiles {
    ".config/lazytail/config.yaml".source = config.lib.neg.live "files/lazytail/config.yaml";
    ".config/lazytail/themes/neg.yaml".source = config.lib.neg.live "files/lazytail/themes/neg.yaml";
  };
}

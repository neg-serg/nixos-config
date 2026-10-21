##
# Module: nix-maid/cli/tint
# Purpose: the tint config for the colouriser that wraps plain-text CLI tools.
#
# The package is installed by modules/cli/tools.nix and the generated wrappers
# are sourced from files/shell/zsh/02-cmds.zsh (`eval "$(tint --shell zsh)"`).
# Only the user config is managed here: it is the place for extra rules
# (`keyword.`/`prefix.`/`suffix.`/`literal.`), extra or skipped wrappers, the
# theme (`neg` = the neg.nvim palette as truecolor, `dark` = follow the
# terminal's own ANSI palette), and per-slot restyling
# (`theme.style.<slot>`). Nothing in it is required — an empty file means
# "builtin behaviour only" — so it is deployed as a live link and can be
# edited without a rebuild.
{ config, neg, ... }:

{
  config = neg.mkHomeFiles {
    ".config/tint/config.toml".source = config.lib.neg.live "files/tint/config.toml";
  };
}

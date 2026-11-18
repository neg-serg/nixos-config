# variant 2 prompt palette — neg.nvim roles as truecolor, so the prompt does
# not depend on the terminal's 16-colour table (variant 2 replaces it with the
# same roles). `shell-theme use v2` selects this file; the values are the hexes
# of files/shell/zsh-native-syntax/neg.ini, not new colours.

typeset -g NEG_PROMPT_BLUE='#367cb0'    # ops1 — main path, separators
typeset -g NEG_PROMPT_GREEN='#127a57'   # lit3 — tilde / home, %r in SPROMPT
typeset -g NEG_PROMPT_ACCENT='#005faf'  # ops3 — prompt end, PS2
typeset -g NEG_PROMPT_ACCENT2='#4779b3' # dlim — the '>' after the prompt end
typeset -g NEG_PROMPT_DIM='#a5c1e6'     # high — dim text in SPROMPT / separators
typeset -g NEG_PROMPT_META='#506a7d'    # dbng — PS4 lead-in
typeset -g NEG_PROMPT_BLACK='#000000'   # user token

# variant 1 prompt palette — what the prompt has always used: 256-colour
# indexes resolved through the terminal's table (kitty's extended palette, see
# files/kitty/theme.conf). Byte-identical output to the pre-variant prompt.

typeset -g NEG_PROMPT_BLUE=4       # main path, separators
typeset -g NEG_PROMPT_GREEN=2      # tilde / home, %r in SPROMPT
typeset -g NEG_PROMPT_ACCENT=25    # prompt end, PS2
typeset -g NEG_PROMPT_ACCENT2=26   # the '>' after the prompt end
typeset -g NEG_PROMPT_DIM=249      # dim text in SPROMPT / separators
typeset -g NEG_PROMPT_META=23      # PS4 lead-in
typeset -g NEG_PROMPT_BLACK=0      # user token

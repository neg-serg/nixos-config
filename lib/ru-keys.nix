# ru-keys.nix — single source of truth for the Russian-layout (ЙЦУКЕН) hotkey
# problem.
#
# Physical letter keys of the US (qwerty) layout produce Cyrillic chars under
# the ru layout. Apps that match hotkeys by the produced char break under ru;
# the fix is to bind the Cyrillic counterpart of every latin key. All per-app
# duplicate blocks MUST be generated from this table — hand-written duplicates
# are a bug, because they silently desync from the latin binds.
#
# Mechanics and the per-app coverage matrix:
# docs/howto/hotkeys-ru-layout.ru.md
#
# Pure file: no config/flake dependencies. Exposed to modules via specialArgs.neg
# (lib/neg-helpers.nix) and unit-tested by flake/checks.nix ("ru-keys" check).
let
  # Latin key → char the ru layout produces for the same physical key.
  # Lowercase letters + the punctuation keys that move in ЙЦУКЕН.
  latinToRu = {
    q = "й";
    w = "ц";
    e = "у";
    r = "к";
    t = "е";
    y = "н";
    u = "г";
    i = "ш";
    o = "щ";
    p = "з";
    "[" = "х";
    "]" = "ъ";
    a = "ф";
    s = "ы";
    d = "в";
    f = "а";
    g = "п";
    h = "р";
    j = "о";
    k = "л";
    l = "д";
    ";" = "ж";
    "'" = "э";
    z = "я";
    x = "ч";
    c = "с";
    v = "м";
    b = "и";
    n = "т";
    m = "ь";
    "," = "б";
    "." = "ю";
    "/" = ".";
    "`" = "ё";
  };

  # Shifted latin key → shifted Cyrillic char.
  latinToRuUpper = {
    Q = "Й";
    W = "Ц";
    E = "У";
    R = "К";
    T = "Е";
    Y = "Н";
    U = "Г";
    I = "Ш";
    O = "Щ";
    P = "З";
    "{" = "Х";
    "}" = "Ъ";
    A = "Ф";
    S = "Ы";
    D = "В";
    F = "А";
    G = "П";
    H = "Р";
    J = "О";
    K = "Л";
    L = "Д";
    ":" = "Ж";
    "\"" = "Э";
    Z = "Я";
    X = "Ч";
    C = "С";
    V = "М";
    B = "И";
    N = "Т";
    M = "Ь";
    "<" = "Б";
    ">" = "Ю";
    "?" = ",";
    "~" = "Ë";
  };

  # ru counterpart of a latin key, or null when the key has none (digits,
  # space, keys outside the table).
  toRu = k: latinToRu.${k} or latinToRuUpper.${k} or null;

  # Map a list of single-char keys (yazi on=[...], zellij Char, rmpc key lists)
  # to their ru counterparts. Keys without a counterpart are dropped — for
  # sequences that keep digits, see kittySeq.
  mkRuKeys = keys: builtins.filter (k: k != null) (map toRu keys);

  # kitty key-sequence: every latin key becomes its LITERAL Cyrillic char —
  # kitty matches by character (all its latin binds are literal chars too, e.g.
  # `map kitty_mod+v`), so under ru the physical key produces the Cyrillic char
  # and the dup binds match. Keys without a counterpart (digits) stay literal.
  # Multi-key sequences join with ">".
  # NB: keysym NAMES (Cyrillic_em) are NOT used: kitty resolves them via
  # xkb_keysym_from_name, which on this system can't load libxkbcommon (no
  # ld.so.cache) and the names are silently dropped as "unknown key".
  kittySeq =
    keys:
    builtins.concatStringsSep ">" (
      map (
        k:
        let
          r = toRu k;
        in
        if r == null then k else r
      ) keys
    );

  # kitty map lines for the Russian-layout duplicates of existing binds.
  # Each spec: { mod = "ctrl+shift"; keys = [ "s" "f" ]; action = "…"; }
  mkKittyLines =
    specs: map (s: "map ${s.mod}+${kittySeq s.keys} ${s.action}  # ${kittyComment s.keys}") specs;

  kittyComment =
    keys: builtins.concatStringsSep ", " (map (k: if toRu k != null then "${k}→${toRu k}" else k) keys);

  # vim/neovim langmap: "ru;latin" pairs, ru side first (typing ru chars acts
  # as latin keys). Order and escaping match files/nvim/lua/00-settings.lua,
  # which langmapper.nvim generates — the generator must reproduce it exactly.
  langmapEn = [
    "`"
    "q"
    "w"
    "e"
    "r"
    "t"
    "y"
    "u"
    "i"
    "o"
    "p"
    "["
    "]"
    "a"
    "s"
    "d"
    "f"
    "g"
    "h"
    "j"
    "k"
    "l"
    ";"
    "'"
    "z"
    "x"
    "c"
    "v"
    "b"
    "n"
    "m"
  ];
  langmapEnShift = [
    "~"
    "Q"
    "W"
    "E"
    "R"
    "T"
    "Y"
    "U"
    "I"
    "O"
    "P"
    "{"
    "}"
    "A"
    "S"
    "D"
    "F"
    "G"
    "H"
    "J"
    "K"
    "L"
    ":"
    "\""
    "Z"
    "X"
    "C"
    "V"
    "B"
    "N"
    "M"
    "<"
    ">"
  ];

  # vim escape for langmap values: backslash before each of ;,. "|\
  vimEscape =
    s:
    builtins.replaceStrings [ ";" "," "." "\"" "|" "\\" ] [ "\\;" "\\," "\\." "\\\"" "\\|" "\\\\" ] s;

  mkLangmap = builtins.concatStringsSep "," [
    "${vimEscape (builtins.concatStringsSep "" (map toRu langmapEnShift))};${vimEscape (builtins.concatStringsSep "" langmapEnShift)}"
    "${vimEscape (builtins.concatStringsSep "" (map toRu langmapEn))};${vimEscape (builtins.concatStringsSep "" langmapEn)}"
  ];
in
{
  inherit
    latinToRu
    latinToRuUpper
    toRu
    mkRuKeys
    kittySeq
    mkKittyLines
    mkLangmap
    ;
}

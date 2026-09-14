-- RU (йцукен) to EN characters for the keymaps: under the Russian layout the
-- physical keys produce Cyrillic, so mapping them back to the EN character
-- keeps typing layout-free ('.' -> 'ю', 'b' -> 'и', '/' -> '.', ...).
--
-- Single source of truth for the Lua side; `lusty --ru-map` prints the Rust
-- table (tui.rs::ru_to_en) and `tests/ru2en_parity_smoke.lua` asserts the two
-- stay identical.
return {
  ['й'] = 'q',
  ['ц'] = 'w',
  ['у'] = 'e',
  ['к'] = 'r',
  ['е'] = 't',
  ['н'] = 'y',
  ['г'] = 'u',
  ['ш'] = 'i',
  ['щ'] = 'o',
  ['з'] = 'p',
  ['х'] = '[',
  ['ъ'] = ']',
  ['ф'] = 'a',
  ['ы'] = 's',
  ['в'] = 'd',
  ['а'] = 'f',
  ['п'] = 'g',
  ['р'] = 'h',
  ['о'] = 'j',
  ['л'] = 'k',
  ['д'] = 'l',
  ['ж'] = ';',
  ['э'] = "'",
  ['я'] = 'z',
  ['ч'] = 'x',
  ['с'] = 'c',
  ['м'] = 'v',
  ['и'] = 'b',
  ['т'] = 'n',
  ['ь'] = 'm',
  ['б'] = ',',
  ['ю'] = '.',
}

-- Nerd-font icon table for the pickers (single source of truth on the Lua
-- side). `lusty --icon-map` prints the Rust table (tui.rs) and
-- tests/tables_parity_smoke.lua asserts the two stay identical.
return {
  dir = '\u{f115}',
  link = '\u{f481}',
  file = '\u{f15b}',
  -- Ordered: the first matching suffix wins, same order as the Rust table.
  ext = {
    { '.md', '\u{f48a}' },
    { '.rs', '\u{e7a8}' },
    { '.lua', '\u{e620}' },
    { '.scd', '\u{e620}' },
    { '.sc', '\u{e620}' },
    { '.jpg', '\u{f1c5}' },
    { '.jpeg', '\u{f1c5}' },
    { '.png', '\u{f1c5}' },
    { '.webp', '\u{f1c5}' },
    { '.gif', '\u{f1c5}' },
    { '.mp3', '\u{f001}' },
    { '.flac', '\u{f001}' },
    { '.wav', '\u{f001}' },
    { '.mp4', '\u{f03d}' },
    { '.mkv', '\u{f03d}' },
    { '.webm', '\u{f03d}' },
    { '.zip', '\u{f410}' },
    { '.tar', '\u{f410}' },
    { '.gz', '\u{f410}' },
    { '.7z', '\u{f410}' },
  },
}

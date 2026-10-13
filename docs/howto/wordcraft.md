# WordCraft — the word processor on trantor

[WordCraft](https://github.com/storytold/wordcraft) is a Word-style word processor written in Rust:
the ribbon, styles, tables, track changes, references and mail merge, reading and writing `.docx`
(plus `.odt`/`.rtf`/`html`/`md`/`tex`/`txt`) and rendering to PDF/PNG. It replaces LibreOffice on
this host — LibreOffice was never installed here — and owns the Word/ODF/RTF MIME types.

## Where it lives

| Piece         | Location                                                                                        |
| ------------- | ----------------------------------------------------------------------------------------------- |
| package       | `packages/wordcraft/default.nix` — built from the upstream release tag                          |
| module + flag | `modules/text/wordcraft.nix`, `features.text.wordcraft.enable` (off by default, on for trantor) |
| flake output  | `pkgs.wordcraft`, `nix build .#wordcraft`, `nix run .#wordcraft`                                |
| MIME defaults | `modules/user/nix-maid/gui/xdg.nix` → `ai.storyteller.wordcraft.desktop`                        |

Plain text, markdown, TeX and HTML keep opening in nvim; the office formats go to WordCraft.

## Command line

`wordcraft-cli` ships in the same package:

```sh
wordcraft-cli convert report.docx report.pdf   # docx, doc, pdf, odt, rtf, html, md, tex, txt, png
wordcraft-cli text report.docx                 # plain text
wordcraft-cli inspect report.docx              # document structure as JSON
wordcraft-cli render report.docx page.png --page 2 --scale 2
wordcraft-cli run --template sample --cmd 'select.text={"text":"Membership"}' --cmd format.bold --save out.docx
wordcraft-cli mcp                              # MCP server, for agent-driven documents
```

## Fonts

WordCraft scans `/usr/share/fonts` and `~/.local/share/fonts` itself (`crates/fonts/src/fontdb.rs`)
and never asks fontconfig, so NixOS font packages are invisible to it. The module therefore links
the families its own substitution table expects into `~/.local/share/fonts`:

| Link            | Package                            | Why                                                                  |
| --------------- | ---------------------------------- | -------------------------------------------------------------------- |
| `carlito`       | `pkgs.carlito`                     | Calibri metrics                                                      |
| `caladea`       | `pkgs.caladea`                     | Cambria metrics                                                      |
| `liberation`    | `pkgs.liberation_ttf`              | Arial / Times New Roman / Courier metrics                            |
| `dejavu`        | `pkgs.dejavu_fonts`                | Unicode and symbol fallback                                          |
| `noto-cjk-sans` | `pkgs.noto-fonts-cjk-sans`         | CJK fallback                                                         |
| `noto-emoji`    | `pkgs.noto-fonts-monochrome-emoji` | emoji (outline; colour fonts have no guaranteed rasteriser/PDF path) |

More fonts: drop files into `~/.local/share/fonts` by hand, or extend the list in the module. Which
family a document actually embedded can be checked without opening the GUI:

```sh
wordcraft-cli convert letter.docx /tmp/letter.pdf
strings /tmp/letter.pdf | grep -oE '/BaseFont/[A-Z]+\+[A-Za-z0-9-]+' | sort -u
```

## Notes

- The app goes through XWayland by default because winit's file drag-and-drop only works on X11;
  `WORDCRAFT_WAYLAND=1` keeps the native Wayland backend.
- Logs and window geometry live in `~/.config/wordcraft/`; `WORDCRAFT_NO_PREFS=1` skips the saved
  preferences.
- The Nix package sets `doCheck = false`: upstream's ~800-test suite is its `cargo xtask ci` job,
  while this build only ships the two binaries (smoke-tested via the CLI and a GUI start).
- Version bump: update `version`, `buildSha` and `buildDate` in `packages/wordcraft/default.nix`,
  refresh the source and vendor hashes (`nix build .#wordcraft` prints the expected `got:` values),
  then `just fmt`, `just check` and rebuild the system.

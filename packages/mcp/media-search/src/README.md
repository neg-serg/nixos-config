# media-search-mcp

Model Context Protocol server that indexes local notes, PDFs, and screenshots so assistants can pull
relevant excerpts. Features:

- Walks a configurable set of directories and ingests Markdown/plain text, Obsidian vaults, PDFs,
  and common image formats.
- Runs lightweight OCR via Tesseract for screenshots or scanned PDFs.
- Provides fuzzy search and document extraction tools so an MCP client can fetch citations/snippets
  without opening the files manually.

Environment variables / CLI flags:

- `MCP_MEDIA_SEARCH_PATHS` or `--paths`: colon-separated directories to scan.
- `MCP_MEDIA_SEARCH_CACHE` or `--cache-dir`: optional cache root for extracted text (speeds up
  repeat runs).
- `MCP_MEDIA_OCR_LANG` or `--ocr-lang`: language list passed to Tesseract.
- `TESSERACT_BIN` or `--tesseract`: override the tesseract binary (defaults to the packaged
  `${pkgs.tesseract}/bin/tesseract`).

The Home Manager module wires sane defaults for documents, Obsidian, and screenshots directories so
it works out of the box.

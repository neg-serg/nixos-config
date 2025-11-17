# knowledge-mcp

Vector knowledge-base MCP server that embeds local documents and surfaces the most relevant
snippets.

- Scans Markdown/code/plain-text directories (plus PDFs) and chunks documents into ~400-character
  passages.
- Uses sentence-transformers (default model `all-MiniLM-L6-v2`) to generate embeddings and answers
  k-nearest neighbor queries.
- Stores metadata (path, title, chunk offsets) so MCP clients can cite the original file or append
  manual snippets on the fly.

Environment variables / CLI flags:

- `MCP_KNOWLEDGE_PATHS` / `--paths`: colon-separated roots to ingest.
- `MCP_KNOWLEDGE_CACHE` / `--cache-dir`: optional embedding cache (stores metadata.json +
  vectors.npy).
- `MCP_KNOWLEDGE_MODEL` / `--model`: Hugging Face sentence-transformers model name (default
  `sentence-transformers/all-MiniLM-L6-v2`).
- `MCP_KNOWLEDGE_EXTRA_PATTERNS` / `--include-globs`: comma-separated glob patterns for additional
  files.

The Home Manager integration points the server at Documents/notes/Obsidian/code paths and caches
embeddings under `$XDG_CACHE_HOME/mcp/knowledge`.

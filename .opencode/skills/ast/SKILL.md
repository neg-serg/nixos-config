______________________________________________________________________

---
name: ast
description: "AST-based code search and structural code analysis"
---

# AST Code Search

Use CLI tools for AST-based code search instead of MCP ast-grep server.

## ast-grep CLI

### Pattern search

```bash
# Search for function calls
ast-grep --pattern 'os.system($ARG)' --lang python .

# Search for pattern
ast-grep --pattern 'console.log($MSG)' --lang typescript src/

# Interactive
ast-grep --lang python .
```

### Using rule files

```yaml
# rule.yaml
id: insecure-deserialization
language: python
rule:
  pattern: pickle.loads($DATA)
message: "Potentially unsafe deserialization"
severity: WARNING
```

```bash
ast-grep --rule rule.yaml .
```

### Replace/rewrite

```bash
# Find and rewrite
ast-grep --pattern 'var x = $VAL' --rewrite 'let x = $VAL' --lang javascript src/
```

## ripgrep (rg) — for simpler text searches

```bash
# Search with context
rg -n "function\s+handle" --type-add 'js:*.{js,jsx,ts,tsx}' -t js

# Regex with file filtering
rg "TODO|FIXME" -g '*.py'

# Exclude directories
rg "pattern" --glob '!node_modules/' --glob '!vendor/'
```

## tree-sitter (for deeper AST queries)

```bash
# Parse and query AST
tree-sitter parse file.py
tree-sitter query query.scm file.py

# Example query.scm for Python:
# (function_definition name: (identifier) @func-name)
```

## When to use each tool

| Task | Tool | |------|------| | Simple text/regex search | `rg` / opencode `<Grep>` | | Structural
pattern matching | `ast-grep` | | Complex AST queries | `tree-sitter` | | Multi-language refactors |
`ast-grep --rewrite` |

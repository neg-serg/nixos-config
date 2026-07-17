---
name: formats
description: "Convert between JSON, YAML, TOML, XML and other config formats using CLI tools"
---

# Format Conversion

Use CLI tools for format conversion instead of MCP json-yaml-toml server.

## JSON ↔ YAML ↔ TOML

### yq (universal converter)

```bash
# JSON to YAML
yq -Poy eval '.' data.json > data.yaml

# YAML to JSON
yq -Poj eval '.' data.yaml > data.json

# TOML to YAML
yq -Poy eval '.' data.toml > data.yaml

# TOML to JSON
yq -Poj eval '.' data.toml > data.json
```

### dasel (alternative)

```bash
# JSON to YAML
dasel -r json -w yaml < data.json
# YAML to TOML
dasel -r yaml -w toml < data.yaml
```

### jq + yq combination

```bash
# Extract and transform
cat data.json | jq '.items[] | {name, value}' | yq -Poy eval '.'
```

## JSON Operations (jq)

```bash
# Pretty print
jq '.' file.json
# Select fields
jq '{name, version}' file.json
# Filter
jq '.[] | select(.status == "active")' file.json
# Merge files
jq -s 'add' a.json b.json
```

## YAML Operations (yq)

```bash
# Set a value
yq -i '.key = "value"' file.yaml
# Delete a key
yq -i 'del(.key)' file.yaml
```

## INI/HCL/XML

```bash
# INI to JSON
dasel -r ini -w json < config.ini

# XML to JSON
yq -Poj eval '.' - < file.xml
```

## Nix-specific

For Nix expressions, use `nix eval --json`:

```bash
nix eval --json -f default.nix
```

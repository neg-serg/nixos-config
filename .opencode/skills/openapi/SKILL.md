---
name: openapi
description: OpenAPI/Swagger spec validation, generation, and tooling
---

# OpenAPI Tools

Use CLI tools for OpenAPI spec work instead of MCP openapi server.

## Validation

```bash
# Validate spec
npx @apidevtools/swagger-cli validate spec.yaml
npx spectral lint spec.yaml

# Check for breaking changes
npx openapi-diff old-spec.yaml new-spec.yaml
```

## Generation

### From code (server stubs)
```bash
npx @openapitools/openapi-generator-cli generate -i spec.yaml -g python-flask -o ./server
npx @openapitools/openapi-generator-cli generate -i spec.yaml -g typescript-axios -o ./client
```

### From API traffic
Use `mitmproxy2swagger` or `openapi-to-graphql` for reverse engineering.

## Format & Bundle

### Split/merge multi-file specs
```bash
npx @redocly/cli split spec.yaml --outDir ./spec-parts
npx @redocly/cli bundle spec-parts/openapi.yaml -o bundled.yaml
```

### YAML to JSON
```bash
yq -Poj eval '.' spec.yaml > spec.json
```

## Documentation

```bash
# Generate HTML docs
npx @redocly/cli build-docs spec.yaml -o docs.html
npx @apidevtools/swagger-cli validate spec.yaml

# Serve interactive docs
npx @redocly/cli preview-docs spec.yaml
```

## Querying
```bash
# Extract paths
yq '.paths | keys' spec.yaml

# List schemas
yq '.components.schemas | keys' spec.yaml

# Find all GET endpoints
yq '.paths | to_entries | map(select(.value.get)) | .[].key' spec.yaml
```

## Mock Server
```bash
npx @stoplight/prism-cli mock spec.yaml
```

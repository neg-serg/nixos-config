---
name: github
description: GitHub operations — issues, PRs, repos, releases, search via gh CLI and API
---

# GitHub Operations

Use the `gh` CLI and `WebFetch` for GitHub operations instead of the MCP GitHub server.

## Authentication

```bash
gh auth status
```

## Common Operations

### Issues
```bash
gh issue list --repo owner/repo
gh issue view 42 --repo owner/repo
gh issue create --repo owner/repo --title "..." --body "..."
gh issue comment 42 --repo owner/repo --body "..."
```

### Pull Requests
```bash
gh pr list --repo owner/repo
gh pr view 42 --repo owner/repo
gh pr create --repo owner/repo --title "..." --body "..."
gh pr review 42 --approve
gh pr merge 42 --repo owner/repo
```

### Repositories
```bash
gh repo view owner/repo
gh repo clone owner/repo
gh repo fork owner/repo
gh repo create my-repo --public
```

### Releases
```bash
gh release list --repo owner/repo
gh release create v1.0.0 --repo owner/repo --title "v1.0.0" --notes "..."
```

### Search
```bash
gh search repos "topic:nixos" --limit 20
gh search issues "bug" --repo owner/repo
gh search prs "fix" --repo owner/repo
```

### API Access
For operations not covered by `gh` CLI, use `gh api`:
```bash
gh api /repos/owner/repo/contents/path
gh api /repos/owner/repo/actions/runs
```

Or use `WebFetch` with GitHub API endpoints (requires token from env).

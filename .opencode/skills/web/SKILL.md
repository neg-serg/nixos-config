---
name: web
description: "Browser automation, web scraping, and page fetching via WebFetch and headless browser CLI"
---

# Web Operations

Use built-in `WebFetch` tool and headless browser CLIs instead of MCP Puppeteer server.

## Fetch Web Pages

Use the built-in `WebFetch` tool for reading page content (supports markdown, text, html formats).

## Browser Automation

For JavaScript-heavy pages or interactive tasks, use command-line browsers:

### Headless Chromium

```bash
chromium --headless --dump-dom --no-sandbox --disable-gpu https://example.com
chromium --headless --screenshot=page.png --no-sandbox https://example.com
chromium --headless --print-to-pdf=page.pdf --no-sandbox https://example.com
```

### Playwright (if available)

```bash
npx playwright screenshot https://example.com page.png
npx playwright pdf https://example.com page.pdf
npx playwright open https://example.com
```

### cURL for API endpoints

```bash
curl -sL https://example.com
curl -sL -H "Accept: application/json" https://api.example.com/data
```

## Tips

- Prefer `WebFetch` for simple page content extraction
- Use headless Chromium for pages that need JavaScript rendering
- Use cURL for REST API calls

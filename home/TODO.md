# TODO

- [ ] Teach `nix flake check` (or a dedicated `hm-extras` job) to build `pkgs.neg.cantata` so the
  patched package stays tested automatically.
- [ ] Document the Firefox multi-profile stack (profiles, desktop entries, and addon requirements)
  in the READMEs once the layout stabilizes.
- [ ] Populate secrets/env vars for the new MCP stack so `seh` can finish without placeholders: -
  Gmail: `GMAIL_CLIENT_ID`, `GMAIL_CLIENT_SECRET`, `GMAIL_REFRESH_TOKEN`, `OPENAI_API_KEY`. - Google
  Calendar: `GCAL_CLIENT_ID`, `GCAL_CLIENT_SECRET`, `GCAL_REFRESH_TOKEN`, optional
  `GCAL_ACCESS_TOKEN`, `GCAL_CALENDAR_ID`. - IMAP: `IMAP_HOST`, `IMAP_PORT`, `IMAP_USERNAME`,
  `IMAP_PASSWORD`, `IMAP_USE_SSL`. - SMTP: `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`,
  `SMTP_PASSWORD`, `SMTP_FROM_ADDRESS`, `SMTP_USE_TLS`, `SMTP_USE_SSL`, optional
  `SMTP_BEARER_TOKEN`. - GitHub: `GITHUB_TOKEN` (PAT/fine-grained), optional `GITHUB_HOST`,
  `GITHUB_TOOLSETS`, `GITHUB_DYNAMIC_TOOLSETS`, `GITHUB_READ_ONLY`, `GITHUB_LOCKDOWN_MODE`. -
  GitLab: `GITLAB_TOKEN`, `GITLAB_API_URL`, optional `GITLAB_PROJECT_ID`,
  `GITLAB_ALLOWED_PROJECT_IDS`, `GITLAB_READ_ONLY_MODE`, `USE_GITLAB_WIKI`, `USE_MILESTONE`,
  `USE_PIPELINE`. - Discord: `DISCORD_BOT_TOKEN`, optional `DISCORD_CHANNEL_IDS`.

# Список MCP-клиентов

`modules/dev/mcp.nix` записывает аттрибут `programs.mcp.servers`, когда `config.features.dev.enable = true`. Полученный набор MCP-клиентов служит источником правды для локальных эндпоинтов (`programs.opencode`, Claude Desktop и других) и помогает ориентироваться при отладке.

## Всегда включенные серверы
- `filesystem-local` — файловый сервер MCP с корнем в `/etc/nixos/home`, используемый для большинства локальных поисковых задач.
- `rg-index` — `mcp-ripgrep`, привязанный к `config.neg.hmConfigRoot`, чтобы выполнять запросы ripgrep по репозиторию через MCP.
- `memory-local` — временное хранилище `mcp-server-memory` для краткосрочной памяти и истории.
- `fetch-http` — вспомогательный сервер `mcp-server-fetch`, который позволяет MCP-клиентам совершать HTTP-запросы через доверенный стек.
- `sequential-thinking` — сервер последовательного мышления для построенных задач и анализа.
- `time-local` — возвращает текущее системное время и связанные параметры через `mcp-server-time`.
- `sqlite` — держит общую базу SQLite в `$XDG_CONFIG_HOME/mcp/sqlite/mcp.db`.
- `media-control` — мост `media_mcp` для управления MPD/PIPEWIRE и вспомогательных модулей из `modules/media`.
- `media-search` — `media_search_mcp`, индексирует указанные медиа-директории и по необходимости запускает Tesseract.
- `agenda` — сборщик ICS/заметок, который отвечает на вопросы о календарях, напоминаниях и заметках.
- `knowledge-vector` — векторная база знаний по документам из конфигурации (`packages/mcp/knowledge`).
- `playwright` — запускает Playwright с сохранённым профилем, чтобы MCP мог управлять браузерами.
- `chromium` — автоматизация, основанная на Chromium (`chromium_mcp`).
- `meeting-notes` — хранит заметки встречи Claude в `~/.claude/session-notes` для последующего использования.

## Интеграции по переменным окружения
Нижеуказанные серверы появляются только при наличии соответствующих переменных окружения.
- `context7` — проксирует запросы на `https://mcp.context7.com/mcp`; требуется `CONTEXT7_API_KEY`.
- `gmail` — Gmail-интеграция, которая требует всех секретов `GMAIL_*` и `OPENAI_API_KEY`.
- `google-calendar` — импорт Google Calendar через `GCAL_CLIENT_ID`, `GCAL_CLIENT_SECRET`, `GCAL_REFRESH_TOKEN` и прочие опции.
- `imap-mail` — доступ к IMAP-почте при помощи `IMAP_HOST`, `IMAP_PORT`, `IMAP_USERNAME`, `IMAP_PASSWORD` и флага `IMAP_USE_SSL`.
- `smtp-mail` — исходящая SMTP-служба, настраиваемая через набор `SMTP_*`, включая токены и TLS/SSL-флаги.
- `firecrawl` — внешний API Firecrawl (`FIRECRAWL_API_KEY` и `FIRECRAWL_API_URL`).
- `elasticsearch` — прокси Elasticsearch с `ES_URL`, учётными данными и `ES_SSL_SKIP_VERIFY` при необходимости.
- `sentry` — доступ к логам Sentry, требует `SENTRY_TOKEN`.
- `slack` — Slack-помощник с `SLACK_BOT_TOKEN`, `SLACK_TEAM_ID` и `SLACK_CHANNEL_IDS`.
- `github` — MCP-клиент GitHub с токеном `GITHUB_TOKEN` и опциональными настройками хоста/наборов инструментов.
- `gitlab` — MCP-клиент GitLab с `GITLAB_TOKEN`, `GITLAB_API_URL` и вспомогательными флагами проект/режим.
- `discord` — сборщик из Discord на основе `DISCORD_BOT_TOKEN` и идентификаторов каналов.
- `telegram` — Telegram-клиент, сохраняющий сессию в `$XDG_DATA_HOME/mcp/telegram/session.json` при наличии `TG_APP_ID`/`TG_API_HASH`.
- `brave-search` — интеграция Brave Search (`BRAVE_API_KEY`, опционально `BRAVE_MCP_ENABLED_TOOLS` / `BRAVE_MCP_DISABLED_TOOLS`).
- `exa` — поиск Exa Labs (`EXA_API_KEY`).
- `postgres` — read-only доступ к PostgreSQL при наличии `MCP_POSTGRES_URL`.
- `telegram-bot` — минимальный Telegram bot MCP с токеном `TELEGRAM_BOT_TOKEN`.
- `tsgram` — мост TSGram между Claude Code и Telegram (`TELEGRAM_BOT_TOKEN` + `TSGRAM_AUTHORIZED_CHAT_ID`).

## Удалённые клиенты
Следующие MCP-клиенты исключены из системной и Codex-конфигурации, чтобы не получать постоянные ошибки запуска, пока не появятся рабочие пакеты:
- `browserbase`
- `exa-search`
- `git-local`
- `redis-local`
- `docsearch-local`
- `postgres-local`

Остальные перечисленные выше MCP-клиенты запускаются с конфигурацией по умолчанию (`modules/dev/mcp.nix`) и не требуют дополнительной ручной настройки при включённой `config.features.dev.enable`.

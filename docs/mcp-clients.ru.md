# Список MCP-клиентов

`modules/dev/mcp.nix` записывает аттрибут `programs.mcp.servers`, когда `config.features.dev.enable = true`. Полученный набор MCP-клиентов служит источником правды для локальных эндпоинтов (`programs.opencode`, Claude Desktop и других) и помогает ориентироваться при отладке.

## Всегда включенные серверы
- `filesystem-local` — файловый сервер MCP с корнем в директории home-manager dotfiles, используемый для большинства локальных поисковых задач.
- `rg-index` — `mcp-ripgrep`, привязанный к `config.neg.dotfilesRoot`, чтобы выполнять запросы ripgrep по репозиторию через MCP.
- `git-local` — предоставляет метаданные Git из того же репозитория (сейчас не стартует; см. раздел ниже).
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
- `brave-search` — Brave Search по ключу `BRAVE_API_KEY`.
- `browserbase` — поиск BrowserBase (`BROWSERBASE_API_KEY`, `STAGEHAND_API_KEY`).
- `exa-search` — EXA Search, нуждающийся в `EXA_API_KEY`.
- `github` — MCP-клиент GitHub с токеном `GITHUB_TOKEN` и опциональными настройками хоста/наборов инструментов.
- `gitlab` — MCP-клиент GitLab с `GITLAB_TOKEN`, `GITLAB_API_URL` и вспомогательными флагами проект/режим.
- `redis-local` — подключение к `REDIS_URL` для кэшей и служебных данных.
- `discord` — сборщик из Discord на основе `DISCORD_BOT_TOKEN` и идентификаторов каналов.
- `telegram` — Telegram-клиент, сохраняющий сессию в `$XDG_DATA_HOME/mcp/telegram/session.json` при наличии `TG_APP_ID`/`TG_API_HASH`.
- `telegram-bot` — бот Telegram на `TELEGRAM_BOT_TOKEN`.
- `docsearch-local` — локальный поиск документов: нужен `OPENAI_API_KEY` _или_ `EMBEDDINGS_PROVIDER=tei` и `TEI_ENDPOINT`, а также прочие настройки загрузки документов.
- `postgres-local` — PostgreSQL-клиент, ожидающий `POSTGRES_DSN` (и `POSTGRES_READ_ONLY`, если нужно).

## Клиенты, требующие дополнительной настройки
Следующие MCP-клиенты не стартуют сейчас и нуждаются в дополнительной конфигурации.
- `exa-search` — `MCP client for exa failed to start: No such file or directory (os error 2)`
- `redis-local` — `MCP client for redis-local failed to start: No such file or directory (os error 2)`
- `git-local` — `MCP client for git-local failed to start: handshaking with MCP server failed: connection closed: initialize response`
- `docsearch-local` — `MCP client for docsearch-local failed to start: No such file or directory (os error 2)`
- `browserbase` — `MCP client for browserbase failed to start: No such file or directory (os error 2)`
- `postgres-local` — `MCP client for postgres-local failed to start: handshaking with MCP server failed: connection closed: initialize response`
- `brave-search` — `MCP client for brave-search failed to start: No such file or directory (os error 2)`

Остальные перечисленные выше MCP-клиенты запускаются с конфигурацией по умолчанию (`modules/dev/mcp.nix`) и не требуют дополнительной ручной настройки при включённой `config.features.dev.enable`.

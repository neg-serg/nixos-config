# Порт omp / oh-my-opencode → DSH: итоговая сводка

Что получилось в результате всей работы: 15 server-плагинов DSH, доки, воркфлоу, промпты, плюс
проверка на живом хосте после `nixos-rebuild switch`.

## 1. Плагины (все в `modules/user/nix-maid/apps/`, все в live-профиле)

| Плагин                        | Что делает                                                                                                              | Тест                                                                   | Коммит                       |
| ----------------------------- | ----------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- | ---------------------------- |
| dsh-debug                     | DAP-отладка: gdb/lldb-dap/dlv/debugpy/js-debug, launch/attach, breakpoints, stepping, inspect, evaluate, custom_request | ✅ gdb launch→bp→continue→stack→vars→terminate; attach; custom_request | 50213471, 968ab65a, 8f08714b |
| dsh-hashline                  | read_hashline + hashline_edit (теги LINE#ID, отказ при расхождении хэша)                                                | ✅ gdb-тест-файл, read/edit/mismatch                                   | ba3105b4                     |
| dsh-read-tags                 | LINE#ID-якоря в выводе встроенного read (phase 2; хэш как dsh-hashline)                                                | ✅ теги совпадают с read_hashline 4/4                                 | 04472acb                     |
| dsh-boulder                   | todo-continuation: idle + незакрытые todo → steer с CONTINUATION_PROMPT (+ toast-клиент)                                | ✅ живой (срабатывал в сессиях)                                        | 3995f5f1, 027a80ee           |
| dsh-rules-injector            | инжект rules/\*.md + AGENTS.md при touch файлов (alwaysApply/glob, дедуп)                                               | ✅                                                                     | dcbe0df7                     |
| dsh-agent-usage-reminder      | подсказка делегировать при сериях ручных поисков                                                                        | ✅ живой                                                               | 4c56685f                     |
| dsh-category-skill-reminder   | напоминание делегировать + скиллы (агент-плоскость)                                                                     | ✅ живой                                                               | 6170dcf7, 376a1c7f           |
| dsh-compaction-todo-preserver | todo переживает компакцию (compaction/start→end)                                                                        | ✅                                                                     | b1eca24a                     |
| dsh-memory-extractor          | session-end draft-extract в memento (LLM-шаг = TODO)                                                                    | ✅                                                                     | 9145ff98, a20260e9           |
| dsh-secrets-masker            | маскировка ключей в результатах тулов (43-char, sk-, ghp\_, ...)                                                        | ✅ unit                                                                | 1861761a                     |
| dsh-lsp                       | LSP: hover/definition/references/rename/code_actions (rust-analyzer, clangd, pyright, tsserver)                         | ✅ pyright: hover/def/refs/rename; clangd (с compile_commands.json): def+hover | c1a70484                     |
| dsh-eval                      | персистентные ядра Python/Bun (состояние между вызовами, reset)                                                         | ✅ py: x=41→42; bun: z=5→10                                            | a9828f46                     |
| dsh-ttsr                      | правила-коррекции на выводе + mental-models (агент-плоскость)                                                           | ✅ TODO-правило; mental 1×/сессию                                      | e55c340e, 8f08714b           |
| dsh-hub                       | супервизируемые процессы: start/send/wait/stop/list                                                                     | ✅ cat/sleep                                                           | 5b5a0b85                     |
| dsh-ast-grep                  | структурный search/rewrite через ast-grep (1-based позиции)                                                             | ✅ реальный бинарь: search/rewrite                                     | 715c6e5e, 51a37f10           |
| dsh-checkpoint                | checkpoint/rewind (soft): замена разведки на отчёт                                                                      | ✅                                                                     | 163735c6                     |

## 2. Доки и воркфлоу

- `AGENTS.md`: evidence-first, ask, todos, goal-audit, web-search этикет, secrets hygiene, tan.
- `docs/howto/`: agent-guards (9 гардов), agent-advisor, agent-memory-pipeline, subagent-contract,
  agent-categories, agent-port-research, agent-harness-features, agent-harness-implementation,
  agent-misc-ports, agent-deferred (план + закрытые дыры + честные остатки), designs/ (5 дизайнов).
- `.agent/workflows/`: plan-before-code, delegate-task, security-scan, notepads, vibe-director,
  codebase-cleanse, autolearn; `.agent/prompts/`: memory-extract, memory-consolidate;
  `.agent/scripts/export-session.mjs` (JSONL.zstd → HTML).

## 3. Проверено на живом хосте (после rebuild)

- `dsh.service` active, **0 ошибок** в журнале текущего процесса.
- **bun** и **ast-grep** теперь в системном PATH (`/run/current-system/sw/bin/`).
- Реальные тесты после rebuild: `ast_grep` search/rewrite на rust-фикстуре ✅; `eval` python
  (val=6.283) и bun (z=5→10, let/const/class персистят между вызовами: a=42) ✅; `lsp` pyright (hover/def/refs/rename) ✅ и clangd
  (с compile_commands.json: definition+hover ✅); **js-debug** (socket-транспорт:
  launch+terminate ✅; breakpoint/step — даже с bp до launch на живом скрипте не даёт
  stopped/threads в этой настройке — задокументированное ограничение); логика rules-injector
  (инжект+дедуп ✅), compaction-todo-preserver (re-append ✅), memory-extractor (draft ✅).
- Вживую срабатывали: boulder (продолжения по todo), category-skill-reminder, TTSR-инъекции.

## 4. Что осталось (честно)

- `systemctl --user restart dsh` — подхват последних правок (js-debug резолв, mental-models).
- js-debug (JS/TS отладка): launch/terminate проверены (socket-транспорт); breakpoint/step
  не дают stopped/threads даже с брейкпоинтом до launch на живом скрипте (setTimeout 6s) —
  задокументированное ограничение nixpkgs-сборки адаптера (ожидает полной VS Code-конфигурации:
  runtimeArgs/sourceMapPause/...; из коробки отдаёт только launch/terminate).
- Не проверено живьём (нужны реальная сессия/тулчейн): lsp rust-analyzer (в песочнице rustup
  без default-тулчейна; на хосте бинарь в PATH — нужен проект с Cargo.toml + тулчейном);
  boulder toast (GUI-элемент, headless не проверить). Логика остальных — см. §3.
- Не закрыто (в agent-deferred): advisor-рантайм, mid-stream TTSR, LLM-шаг memory-extractor,
  collab/autoresearch/vibe-рантайм/computer/browser.

## 5. Уроки

- cordis требует `inject` для доступа к сервисам (ctx.tools/ctx.memory) — без него кидает при
  доступе.
- Имя бинаря в nixpkgs ≠ имя в VS Code (js-debug vs js-debug-adapter); `sg` занят shadow-utils.
- gdb DAP отвечает на launch только после configurationDone; threads после attach пустые (gdb 17.2).
- node:vm не персистит let/const между вызовами — для ядра использовать var/присваивание.
- pyright требует workspaceFolders в initialize, иначе «/<default workspace root>».
- clangd без compile_commands.json почти нем (standalone-файл); с compile db работает (def+hover ✅).
- js-debug из nixpkgs — headless-адаптер: без полной VS Code-конфигурации не отдаёт
  threads/stopped; launch/terminate работают.

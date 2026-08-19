# DSH hooks: rules-injector / compaction-todo-preserver / category-skill-reminder / agent-usage-reminder

Проектирование под DSH web 0.1.0-rc.6 (store `@deepseek-ai`). Проверено чтением
собранного кода в `/nix/store/zvfrqpjr7x0w0ns3m53l9sx05wf24scw-dsh-web-en-0.1.0-rc.6`,
исходников `omo-opencode/src/hooks`, форка `dsh-web-ui` и модулей `/etc/nixos`
(`dsh-mode`, `dsh-liangshen-fork`, `dsh-gui-tweaks`).

## Ключевые факты о DSH (на чём основана оценка)

- DSH — cordis-платформа. Плагин экспортирует `{ name, inject?, apply(ctx, config) }`
  и монтируется строкой в `cordis.patch.yml`:
  ```yaml
  - insert:
      - id: rules-injector
        name: dsh-rules-injector
        config: { rulesDir: "rules" }
  ```
  Хост-плоскость: `~/.dsh/profiles/web/cordis.patch.yml` + пакет в
  `~/.dsh/profiles/web/node_modules/<name>`. Агент-плоскость (то, что нам нужно для
  пер-сессионных хуков): `~/.dsh/.agent-presets/neg/agent.cordis.yml` (пресет `neg`).
- Подтверждённые события (`ctx.on`): `tools/pre-execute`, `tools/execute`,
  `tools/post-execute`, `tools/result`, `session/event`, `session/created`,
  `agent/pre-step`, `agent/created`, `fs/observed`, `fs/write-intent`,
  `fs/edit-intent`, `system-prompt/assemble`, `subagent/start`, `subagent/end`.
- `tools/post-execute(exec, result, next)`: `next()` возвращает
  `{ kind, value, additionalContexts?, feedback? }`; контекст можно препепдить —
  прецедент `dsh-repeat-tool-reminder` (guard, монтируется в `dsh-base`).
- `agent/pre-step({ agent, messages, signal }, next)`: `next()` даёт
  `decision.messages` — сюда дописываются синтетические сообщения перед шагом.
  Прецедент — `dsh-tool-skill` (впрыск текста скилла).
- `session/event(session, event)`: event.type из
  `KNOWN_SESSION_EVENT_TYPES`; есть `todo/write`, `compaction/start`,
  `compaction/end`, `compaction/summary`, `compaction/prune`.
- `todo_write` (`dsh-tool-todo`) при каждом вызове делает
  `session.append("todo/write", { todos })` — состояние задач живёт в session-логе;
  компакция его схлопывает. Восстановление = повторный `append`.
- Скиллы: сервис `ctx.skills` (`ctx.skills.snapshot/get`) — для категорий/списка.
- Делегация: `dsh-tool-subagent` регистрирует `subagent` и `subagent_fork`.

Вывод: все четыре фичи — **server plugin (cordis) в агент-пресете**, а не client plugin
(в браузере нет tool lifecycle / session log) и не fork patch (нужных хуков не хватать не
придётся — они уже есть). docs-only — только как дешёвый v0 для напоминаний.

---

## 1. rules-injector (rules/*.md + alwaysApply, инжект при read)

- **Feasibility:** server plugin. Хуки `tools/post-execute`, `fs/observed`,
  `session/event` уже существуют; портируется логика omo (finder/parser/matcher/dedup).
- **Integration point:** агент-пресет `neg` (`agent.cordis.yml`). Триггер —
  `tools/post-execute` для `read`/`write`/`edit`/`str_replace_editor`; путь файла
  берём из `result.value.path` (или `exec.arguments.file_path`). Опционально
  `fs/observed(target, observation, actor)` для факта «файл прочитан». Кэш
  «уже инжектировано в этой сессии» чистим по `session/event` (`compaction/start`,
  `session/end-seed`).
- **Sketch:**
```js
import { readdirSync, readFileSync } from "node:fs";
import { join, relative, dirname } from "node:path";

export const name = "rules-injector";
export function apply(ctx, config = {}) {
  const root = () => ctx.workspace ?? process.cwd();      // или agent.session.header.cwd
  const cache = new Map();                                 // sessionID -> Set(realPath)

  function scanRules(dir) {                                // упрощённо: rules/*.md + AGENTS.md
    const out = [];
    for (const f of readdirSync(dir, { withFileTypes: true })) {
      if (f.name === "AGENTS.md") out.push(join(dir, f.name));
      if (f.name === "rules" && f.isDirectory())
        for (const r of readdirSync(join(dir, f.name)))
          if (r.endsWith(".md")) out.push(join(dir, "rules", r));
    }
    return out;
  }
  function match(rulePath, filePath) {                     // alwaysApply либо glob из frontmatter
    const text = readFileSync(rulePath, "utf8");
    const m = text.match(/^---\n([\s\S]*?)\n---/);
    if (!m) return true;                                   // без frontmatter = always
    const fm = m[1];
    if (/alwaysApply:\s*true/.test(fm)) return true;
    const g = fm.match(/glob:\s*(\S+)/)?.[1];
    return g ? new RegExp("^" + g.replace(/\*\*/g, ".*").replace(/\*/g, "[^/]*") + "$")
                   .test(filePath) : false;
  }

  ctx.on("tools/post-execute", async (exec, result, next) => {
    const downstream = await next();
    if (!["read","write","edit","str_replace_editor"].includes(exec.name)) return downstream;
    const filePath = result.value?.path ?? exec.arguments?.file_path;
    if (!filePath) return downstream;
    const rel = relative(root(), filePath);
    const sessionID = exec.agent?.session?.id;
    if (!sessionID) return downstream;
    let seen = cache.get(sessionID);
    if (!seen) { seen = new Set(); cache.set(sessionID, seen); }
    const additions = scanRules(root())
      .filter(rp => !seen.has(rp) && match(rp, rel))
      .map(rp => { seen.add(rp); return readFileSync(rp, "utf8"); });
    if (additions.length === 0) return downstream;
    return { ...downstream,
      additionalContexts: [...(downstream.additionalContexts ?? []), ...additions] };
  });

  ctx.on("session/event", (session, event) => {
    if (event.type === "compaction/start" || event.type === "session/end-seed")
      cache.delete(session.id);
  });
}
```
- **Effort:** M. Логика простая, но нужно: полноценный frontmatter-парсер, честный
  glob (без picomatch — писать мини-матчер или добавить зависимость), тесты
  finder/matcher/dedup, очистка кэша. Если ограничиться только `alwaysApply` и
  именами `rules/*.md` + `AGENTS.md` без произвольного glob — S.
- **Риск:** порядок сканирования и дедуп должны быть детерминированы; не инжектить
  правила для самого `read` файла правила (иначе рекурсия/мусор).

---

## 2. compaction-todo-preserver (todo-список переживает компакцию)

- **Feasibility:** server plugin. Всё нужное уже есть: `session/event` c
  `todo/write`, `compaction/start`, `compaction/end`; восстановление — это
  повторный `session.append("todo/write", { todos })`. omo-обвес про Atlas-bootstrap
  в DSH не нужен (Atlas нет).
- **Integration point:** агент-пресет; один обработчик `session/event`.
- **Sketch:**
```js
export const name = "compaction-todo-preserver";
export function apply(ctx) {
  const latest = new Map();   // sessionID -> todos[]
  const snapshot = new Map(); // sessionID -> todos[] на момент compaction/start

  ctx.on("session/event", (session, event) => {
    if (event.type === "todo/write") {
      latest.set(session.id, event.data.todos);
    } else if (event.type === "compaction/start") {
      const todos = latest.get(session.id);
      if (todos && todos.length) snapshot.set(session.id, todos);
    } else if (event.type === "compaction/end") {
      const todos = snapshot.get(session.id);
      snapshot.delete(session.id);
      if (todos && todos.length) session.append("todo/write", { todos });
    } else if (event.type === "session/end-seed") {
      latest.delete(session.id); snapshot.delete(session.id);
    }
  });
}
```
- **Effort:** S (~50 строк + тест). Главный вопрос — идемпотентность: если компакция
  сохранила `todo/write` в summary, повторный append добавит дубль. Безопасный
  вариант: на `compaction/end` всегда пере-аппендить (модель видит актуальный
  список; дубль в логе безвреден, т.к. проекция берёт последний `todo/write`).
- **Проверка:** «пустая» компакция не должна создавать todo-список из ничего;
  рестарт/сброс сессии чистит Map (`session/end-seed`).

---

## 3. category-skill-reminder (напомнить скиллы под категорию делегирования)

- **Feasibility:** server plugin; **docs-only v0 возможен** (одна строка в
  system-prompt/agent-guards). Полноценный runtime-вариант использует
  `tools/post-execute` (счётчик «рабочих» вызовов) + `agent/pre-step` (впрыск
  напоминания) + `ctx.skills.snapshot()`.
- **Integration point:** агент-пресет. Триггер — 3+ прямых вызова
  `read`/`write`/`edit`/`str_replace_editor`/`bash`/`rg`/`glob` без
  делегации (`subagent`/`subagent_fork`).
- **Sketch:**
```js
export const name = "category-skill-reminder";
export function apply(ctx, config = {}) {
  const WORK = new Set(["read","write","edit","str_replace_editor","bash","rg","glob"]);
  const DELEGATE = new Set(["subagent","subagent_fork"]);
  const state = new Map(); // agent.id -> {delegated, work, pending, shown}

  ctx.on("tools/post-execute", async (exec, _result, next) => {
    const downstream = await next();
    const id = exec.agent?.id; if (!id) return downstream;
    const s = state.get(id) ?? { delegated:false, work:0, pending:false, shown:false };
    state.set(id, s);
    if (DELEGATE.has(exec.name)) { s.delegated = true; s.pending = false; return downstream; }
    if (WORK.has(exec.name)) s.work += 1;
    if (s.work >= 3 && !s.delegated && !s.pending && !s.shown) s.pending = true;
    return downstream;
  });

  ctx.on("agent/pre-step", async ({ agent, messages, signal }, next) => {
    const decision = await next();
    if (decision.kind === "reject") return decision;
    const s = state.get(agent.id);
    if (!s?.pending) return decision;
    s.pending = false; s.shown = true;
    const snap = await ctx.skills.snapshot({ cwd: agent.session.header.cwd, signal });
    const text = "[Category+Skill Reminder] Делегируй через subagent с load_skills под "
      + "категорию. Доступны: " + snap.skills.map(x => x.name).join(", ");
    return { ...decision, messages: [...decision.messages, createUserMessage({ content: text, source: { kind: "plugin" } })] };
  });
}
```
- **Effort:** S-M. S если делать docs-only (строка в пресете); M для runtime-хука
  + тест счётчика. Категории/маппинг скиллов задаются конфигом.
- **Нюанс:** в DSH у делегации нет поля `category` как в omo; маппинг
  «категория → скиллы» придётся заводить в конфиге плагина (или парсить
  `config/agent-presets`).

---

## 4. agent-usage-reminder (напоминание использовать субагентов)

- **Feasibility:** server plugin — это точная копия паттерна
  `dsh-repeat-tool-reminder` (`tools/post-execute` + `additionalContexts`).
  docs-only v0 возможен.
- **Integration point:** агент-пресет; `tools/post-execute`.
- **Sketch:**
```js
export const name = "agent-usage-reminder";
export function apply(ctx, config = {}) {
  const SEARCH = new Set(["rg","glob","web_search","bash"]); // прямые «ручные» поиски
  const AGENTS = new Set(["subagent","subagent_fork"]);
  const MAX = config.maxReminders ?? 3;
  const state = new Map(); // sessionID -> {agentUsed, reminded}

  ctx.on("tools/post-execute", async (exec, _result, next) => {
    const downstream = await next();
    const id = exec.agent?.session?.id; if (!id) return downstream;
    const s = state.get(id) ?? { agentUsed:false, reminded:0 };
    state.set(id, s);
    if (AGENTS.has(exec.name)) { s.agentUsed = true; return downstream; }
    if (!SEARCH.has(exec.name) || s.agentUsed || s.reminded >= MAX) return downstream;
    s.reminded += 1;
    return { ...downstream, additionalContexts:
      [...(downstream.additionalContexts ?? []), REMINDER] };
  });

  ctx.on("agent/pre-step", ({ agent, messages }, next) => {   // новый пользовательский ход = сброс
    if (messages.some(m => m.source?.kind === "user")) state.delete(agent.id);
    return next();
  });
}
```
- **Effort:** S (~70 строк + тест). Максимум переиспользования — скопировать каркас
  `repeat-tool-reminder` (Config-схема, `additionalContexts`, `agent/pre-step`).
- **Нюанс:** список SEARCH надо калибровать под DSH (`rg`/`glob`/read-only
  `bash`), чтобы не задолбать напоминанием обычные правки.

---

## Рекомендуемый порядок

1. **agent-usage-reminder** — S, готовый шаблон `repeat-tool-reminder`, сразу заметная
   польза.
2. **compaction-todo-preserver** — S, один `session/event`, закрывает боль потери
   todo при компакции.
3. **rules-injector** — M (или S без произвольного glob), самая ценная, но требует
   парсер/матчер/тесты; делать после того, как паттерн server-плагина обкатан на 1–2.
4. **category-skill-reminder** — M; сразу можно выкатить docs-only v0 (строка в
   system-prompt), runtime-хук потом.

Общий шаг развёртывания на odin для каждого плагина: пакет в
`modules/user/nix-maid/apps/<name>/` (`package.json` + `lib/index.js`), ensure-скрипт
по образцу `dsh-mode.nix` копирует его в `~/.dsh/profiles/web/node_modules/<name>`,
строку добавляем **не** в профильный `cordis.patch.yml`, а в
`~/.dsh/.agent-presets/neg/agent.cordis.yml` (или в `dsh-liangshen-fork/agent.cordis.yml`
и sync-скрипт), затем `systemctl --user restart dsh.service`. Никакие файлы репозиториев
апстрима/форка не трогаем.

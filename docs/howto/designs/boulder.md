# Boulder — todo-continuation enforcer для DSH

Источники: /etc/nixos/docs/howto/agent-guards.ru.md п.6; omo
packages/omo-opencode/src/hooks/todo-continuation-enforcer/ (constants.ts, handler.ts,
idle-event.ts, continuation-injection.ts, non-idle-events.ts, session-state.ts,
compaction-guard.ts, stagnation-detection.ts, countdown.ts, types.ts); DSH-типы
@deepseek-ai/dsh-agent, dsh-session, dsh-tool-todo, dsh-session-projection,
dsh-llm (createUserMessage); пример dsh-plan-mode.

## 1. Поведенческая спецификация

Цель: когда агент ушёл в idle, а в todo остались незакрытые задачи, харнесс сам
будит агента системной директивой и заставляет продолжить работу, пока задачи не
закончены. Это «камень Сизифа»: агент не должен останавливаться.

### Триггеры

- Основной триггер — переход агента в idle: DSH-событие agent/status со
  status === "idle". На нём запускается проверка и обратный отсчёт.
- Стоп-события отменяют уже идущий отсчёт и сбрасывают часть состояния:
  новое пользовательское сообщение, assistant-сообщение, tool-call
  (message.updated, message.part.updated, message.part.delta,
  tool.execute.before/after, agent/status → running).
- session.error с AbortError / MessageAbortedError выставляет wasCancelled и
  отменяет countdown; token-limit или неретрабельная ошибка запроса (400/422 +
  isRetryable:false) ставит соответствующий флаг и прекращает цикл.

### Обратный отсчёт — 2 секунды

- Успешная проверка НЕ инжектит сразу: startCountdown() показывает toast
  «Resuming in Ns... (K tasks remaining)», TOAST_DURATION_MS = 900ms, тик 1s.
- COUNTDOWN_SECONDS = 2: через 2000ms countdown отменяется и вызывается
  injectContinuation().
- COUNTDOWN_GRACE_PERIOD_MS = 500: пользовательское сообщение в первые 500ms
  после старта отсчёта игнорируется (защита от гонки «уже считаем, а
  пользователь допечатывает»). Позже — отсчёт отменяется, инъекции нет.
- ABORT_WINDOW_MS = 3000: если abort зафиксирован меньше 3s назад, idle
  пропускается один раз (не бомбим сразу после отмены).

### Backoff и cooldown

- CONTINUATION_COOLDOWN_MS = 5000: минимальный интервал между двумя инъекциями
  одной сессии (также передаётся как semanticDedupeHoldMs в gate — не плодить
  дубли за 5s).
- Экспоненциальный backoff на повторных фейлах: эффективный cooldown =
  COOLDOWN_MS * 2 ** min(consecutiveFailures, 5) → 5s, 10s, 20s, 40s, 80s, 160s
  (база ×2, потолок ×32).
- MAX_CONSECUTIVE_FAILURES = 5: после 5 подряд неудачных инъекций инъекции
  прекращаются; повтор разрешается только после FAILURE_RESET_WINDOW_MS =
  5 * 60 * 1000 (5 минут паузы), счётчик при этом сбрасывается в 0.
- ⚠️ Расхождение с бэклогом: agent-harness-features.ru.md и agent-guards.ru.md
  пишут «база 30s, ×2». В omo-коде база экспоненты — 5s
  (CONTINUATION_COOLDOWN_MS). Решить до имплементации (см. риски): для DSH
  рекомендую следовать omo-коду (5s), если не требуется буквальный перенос
  текста бэклога.

### Stagnation detection — max 3

- Считается на каждый idle после успешной инъекции: если следующая проверка не
  увидела прогресса по todo, stagnationCount += 1.
- Прогресс = уменьшение incompleteCount, рост числа completed, либо изменение
  snapshot {id → status} (изменение только content/priority прогрессом НЕ
  считается — omo issue #4013).
- При stagnationCount >= MAX_STAGNATION_COUNT = 3 инъекция прекращается для
  сессии (агент «отвечает на директиву, но не двигает задачи»). Сброс — при
  любом прогрессе.

### Compaction guard — 60 секунд

- COMPACTION_GUARD_MS = 60_000. На событии компакции вооружается guard с новым
  epoch.
- Пока guard активен и epoch не подтверждён агентом, idle-инъекция
  пропускается: после компакции контекст только что пересобран, немедленная
  директива ломает восстановление. Guard подтверждается (acknowledge), когда у
  резолвнутого агента появляется agent-info; после ack или 60s можно инжектить.

### Когда НЕ вставлять (полный список)

1. allTodosCompletedAt установлен (всё уже закрыто).
2. Сессия в recovery (isRecovering).
3. wasCancelled (был abort).
4. Sync-subagent уже вернул результат родителю (handedBackSyncSessions).
5. tokenLimitDetected — ретрай ухудшит переполнение контекста.
6. unrecoverableErrorDetected — повторная директива соберёт тот же запрос.
7. Abort был меньше 3s назад (ABORT_WINDOW_MS).
8. Есть running/pending фоновые задачи сессии или pending parent-wake.
9. Последнее assistant-сообщение — aborted (API fallback).
10. Ждём ответа пользователя (hasUnansweredQuestion).
11. Ожидается ответ на внутреннюю continuation-директиву
    (latestAssistantTurnBlocksInternalPrompt).
12. Todo пуст или incompleteCount == 0.
13. inFlight — инъекция уже идёт.
14. consecutiveFailures >= 5 и не прошло 5 минут.
15. Cooldown ещё не прошёл.
16. Последнее сообщение — маркер компакции.
17. Агент в skipAgents (omo: prometheus, compaction, plan; в DSH —
    соответствующие системные/субагентные роли).
18. Compaction guard активен для текущего epoch (или компакция без
    резолвнутого агента).
19. isContinuationStopped(sessionID) — внешняя остановка продолжения.
20. continuationBlockReason — пауза на границе хода (directive-response или
    user-interruption).
21. Нет write-пермишена у агента (edit/write не deny/false).
22. Fetch сообщений/todo упал — пропускаем безопасно (не инжектим вслепую).

## 2. Интеграционный дизайн (слой DSH)

DSH — Cordis-плагин в web-профиле. Хостовая половина apply(ctx) подписывается на
события; браузерная client.ts рисует только toast/индикатор.

### Файлы для добавления (в форке dsh-web-ui, packages/dsh-boulder/)

- package.json — имя @deepseek-ai/dsh-boulder, exports . и ./client,
  dsh.client.platform: "web", peerDeps на dsh-agent/dsh-session/dsh-llm/
  dsh-tool-todo/cordis.
- src/index.ts → lib/index.js — хост: apply + state-store + вся логика.
- src/client.ts → lib/client.js — браузер: window.__ModuleLoader__.load(...),
  рендер countdown-toast/статуса.
- src/constants.ts — все константы + CONTINUATION_PROMPT.
- src/session-state.ts — per-session Map (перенос логики omo session-state.ts).
- src/types.ts — SessionState, ResolvedAgentInfo.
- test/*.test.ts — на @deepseek-ai/dsh-agent-loop-testkit.

### Детект idle

ctx.on("agent/status", ({ agent, status }) => ...) — Cordis emit-событие,
scope-filtered. При status === "idle" вызываем handleSessionIdle(agent).
Обратный переход status === "running" — отменяем countdown (аналог
non-idle-events).

### Детект незакрытых todo

Два пути:
1. Проекция (предпочтительно): ctx.sessionProjections.snapshot(agent.session)
   .values.todos → TodoItem[] | null (последний todo/write, last-wins).
   Проекцию регистрирует dsh-tool-todo; если сервис ещё не загружен — fallback.
2. Fallback без зависимостей: свернуть agent.session.events и взять последний
   todo/write: events.filter(e => e.type === "todo/write").at(-1)?.data.todos.

incomplete = todos.filter(t => t.status !== "completed").length (в DSH статусы
только pending | in_progress | completed; cancelled/blocked/deleted отсутствуют).

### Инъекция системной директивы

Использовать agent.steer() (а не agent.inject()): steer будит idle-драйвер и
запускает ход; inject только кладёт контекст до следующего шага и idle-агента
не разбудит.

    import { createUserMessage } from "@deepseek-ai/dsh-llm";
    agent.steer(createUserMessage({
      content: [{ type: "text", text: prompt }],
      source: { kind: "user" },
    }));

Точный prompt = CONTINUATION_PROMPT + статус-хвост («[Status: D/T completed,
K remaining]» + список «- [status] content»).

### Состояние и жизненный цикл

- SessionStateStore: Map<SessionId, State>; поля omo: countdownTimer/Interval,
  lastInjectedAt, lastIncompleteCount, stagnationCount, consecutiveFailures,
  abortDetectedAt, wasCancelled, tokenLimitDetected, unrecoverableErrorDetected,
  inFlight, awaitingPostInjectionProgressCheck, continuationResponseObserved,
  continuationBlockReason, pendingUserMessageID, allTodosCompletedAt,
  recentCompactionAt/Epoch, acknowledgedCompactionEpoch.
- TTL 10 мин + prune каждые 2 мин; session.deleted → cleanup().
- dispose()/fiber disposal → cancelAllCountdowns + shutdown.

## 3. Плагин skeleton

### package.json

    {
      "name": "@deepseek-ai/dsh-boulder",
      "description": "Todo-continuation enforcer: wake idle agents with incomplete todos",
      "version": "0.1.0-rc.6",
      "type": "module",
      "main": "lib/index.js",
      "types": "lib/types/index.d.ts",
      "exports": {
        ".": { "types": "./lib/types/index.d.ts", "default": "./lib/index.js" },
        "./client": "./lib/client.js",
        "./package.json": "./package.json"
      },
      "files": ["lib/index.js", "lib/client.js", "lib/types/**/*.d.ts"],
      "license": "MIT",
      "dsh": { "client": { "inject": [], "platform": "web" } },
      "peerDependencies": {
        "@deepseek-ai/cordis": "^4.0.1",
        "@deepseek-ai/dsh-agent": "^0.1.0-rc.6",
        "@deepseek-ai/dsh-session": "^0.1.0-rc.6",
        "@deepseek-ai/dsh-llm": "^0.1.0-rc.6",
        "@deepseek-ai/dsh-tool-todo": "^0.1.0-rc.6"
      }
    }

### src/constants.ts (точный текст)

    export const HOOK_NAME = "dsh-boulder";

    export const CONTINUATION_PROMPT = [
      "[system-directive todo_continuation]",
      "",
      "Incomplete tasks remain in your todo list. Continue working on the next pending task.",
      "",
      "- Proceed without asking for permission",
      "- Mark each task complete when finished",
      "- Do not stop until all tasks are done",
      "- If you believe all work is already complete, the system is questioning your completion claim. Critically re-examine each todo item from a skeptical perspective, verify the work was actually done correctly, and update the todo list accordingly."
    ].join(String.fromCharCode(10));

    export const COUNTDOWN_SECONDS = 2;
    export const TOAST_DURATION_MS = 900;
    export const COUNTDOWN_GRACE_PERIOD_MS = 500;
    export const ABORT_WINDOW_MS = 3_000;
    export const COMPACTION_GUARD_MS = 60_000;
    export const CONTINUATION_COOLDOWN_MS = 5_000;
    export const MAX_STAGNATION_COUNT = 3;
    export const MAX_CONSECUTIVE_FAILURES = 5;
    export const FAILURE_RESET_WINDOW_MS = 5 * 60 * 1000;
    export const DEFAULT_SKIP_AGENTS = ["compaction", "plan"];

Точный текст CONTINUATION_PROMPT (рендер, без JS-конкатенации):

[system-directive todo_continuation]

Incomplete tasks remain in your todo list. Continue working on the next pending task.

- Proceed without asking for permission
- Mark each task complete when finished
- Do not stop until all tasks are done
- If you believe all work is already complete, the system is questioning your completion claim. Critically re-examine each todo item from a skeptical perspective, verify the work was actually done correctly, and update the todo list accordingly.

### src/index.ts (хост, ключевая логика)

    import type { Context } from "@deepseek-ai/cordis";
    import { createUserMessage } from "@deepseek-ai/dsh-llm";
    import type { Agent } from "@deepseek-ai/dsh-agent";
    import type { TodoItem } from "@deepseek-ai/dsh-session";
    import { CONTINUATION_PROMPT, CONTINUATION_COOLDOWN_MS, ABORT_WINDOW_MS,
      COMPACTION_GUARD_MS, DEFAULT_SKIP_AGENTS, FAILURE_RESET_WINDOW_MS,
      MAX_CONSECUTIVE_FAILURES, MAX_STAGNATION_COUNT } from "./constants";
    import { createSessionStateStore } from "./session-state";

    interface EnforcerState {
      countdownTimer?: ReturnType<typeof setTimeout>;
      countdownInterval?: ReturnType<typeof setInterval>;
      countdownStartedAt?: number;
      lastInjectedAt?: number;
      lastIncompleteCount?: number;
      stagnationCount: number;
      consecutiveFailures: number;
      inFlight?: boolean;
      wasCancelled?: boolean;
      abortDetectedAt?: number;
      tokenLimitDetected?: boolean;
      unrecoverableErrorDetected?: boolean;
      allTodosCompletedAt?: number;
      recentCompactionAt?: number;
      recentCompactionEpoch?: number;
      acknowledgedCompactionEpoch?: number;
    }

    export const name = "dsh-boulder";

    function readTodos(agent: Agent, ctx: Context): TodoItem[] {
      const snap = (ctx as any).sessionProjections?.snapshot(agent.session).values.todos;
      if (Array.isArray(snap)) return snap as TodoItem[];
      const last = [...agent.session.events].reverse().find(e => e.type === "todo/write");
      return ((last as any)?.data?.todos ?? []) as TodoItem[];
    }

    function incompleteCount(todos: TodoItem[]): number {
      return todos.filter(t => t.status !== "completed").length;
    }

    export function apply(ctx: Context, config: Record<string, unknown> = {}) {
      const store = createSessionStateStore();
      const skipAgents: string[] = (config.skipAgents as string[]) ?? DEFAULT_SKIP_AGENTS;

      ctx.on("agent/status", ({ agent, status }) => {
        const sid = agent.session.id as string;
        const st = store.getState(sid);
        if (status === "running") { store.cancelCountdown(sid); return; }
        if (status !== "idle") return;
        void handleIdle(ctx, agent, store, skipAgents);
      });

      ctx.on("agent/pre-step", ({ agent }) => {
        store.cancelCountdown(agent.session.id as string);
      });

      // Заменить на фактическое событие компакции из dsh-compaction.
      ctx.on("session/compacted" as any, (payload: any, next?: () => void) => {
        const sid = payload?.session?.id ?? payload?.sessionId;
        if (!sid) return next?.();
        const st = store.getState(sid as string);
        st.recentCompactionAt = Date.now();
        st.recentCompactionEpoch = (st.recentCompactionEpoch ?? 0) + 1;
        st.acknowledgedCompactionEpoch = undefined;
        return next?.();
      });

      ctx.effect(() => () => store.shutdown(), name + ": shutdown");
    }

    async function handleIdle(
      ctx: Context, agent: Agent, store: ReturnType<typeof createSessionStateStore>,
      skipAgents: string[],
    ): Promise<void> {
      const sid = agent.session.id as string;
      const st = store.getState(sid);
      const now = Date.now();

      if (st.allTodosCompletedAt || st.wasCancelled || st.tokenLimitDetected
          || st.unrecoverableErrorDetected || st.inFlight) return;
      if (st.abortDetectedAt && now - st.abortDetectedAt < ABORT_WINDOW_MS) {
        st.abortDetectedAt = undefined; return;
      }

      const todos = readTodos(agent, ctx);
      const incomplete = incompleteCount(todos);
      if (incomplete === 0) {
        st.allTodosCompletedAt = now;
        store.resetContinuationProgress(sid);
        return;
      }

      if (st.recentCompactionAt
          && st.acknowledgedCompactionEpoch !== st.recentCompactionEpoch
          && now - st.recentCompactionAt < COMPACTION_GUARD_MS) return;

      if (skipAgents.some(s => (agent as any).name === s)) return;

      if (st.consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
        if (st.lastInjectedAt && now - st.lastInjectedAt >= FAILURE_RESET_WINDOW_MS) {
          st.consecutiveFailures = 0;
        } else return;
      }

      const cooldown = CONTINUATION_COOLDOWN_MS * 2 ** Math.min(st.consecutiveFailures, 5);
      if (st.lastInjectedAt && now - st.lastInjectedAt < cooldown) return;

      const prev = st.lastIncompleteCount;
      if (prev !== undefined && incomplete < prev) st.stagnationCount = 0;
      st.lastIncompleteCount = incomplete;
      if (st.stagnationCount >= MAX_STAGNATION_COUNT) return;

      startCountdown(ctx, agent, incomplete, todos.length);
    }

    function startCountdown(ctx: Context, agent: Agent, incomplete: number, total: number) {
      const sid = agent.session.id as string;
      const store = (ctx as any).__boulderStore;
      const st = store.getState(sid);
      store.cancelCountdown(sid);

      let seconds = 2;
      st.countdownStartedAt = Date.now();
      emitToast("Resuming in " + seconds + "s... (" + incomplete + " tasks remaining)");
      st.countdownInterval = setInterval(() => {
        seconds -= 1;
        if (seconds > 0) emitToast("Resuming in " + seconds + "s... (" + incomplete + " tasks remaining)");
      }, 1000);

      st.countdownTimer = setTimeout(() => {
        store.cancelCountdown(sid);
        injectContinuation(ctx, agent, incomplete, total);
      }, 2000);
    }

    async function injectContinuation(
      ctx: Context, agent: Agent, incomplete: number, total: number,
    ): Promise<void> {
      const sid = agent.session.id as string;
      const store = (ctx as any).__boulderStore;
      const st = store.getState(sid);
      if (st.inFlight || st.wasCancelled || st.tokenLimitDetected
          || st.unrecoverableErrorDetected) return;

      const todos = readTodos(agent, ctx);
      const fresh = incompleteCount(todos);
      if (fresh === 0) { st.allTodosCompletedAt = Date.now(); return; }

      const list = todos.filter(t => t.status !== "completed")
        .map(t => "- [" + t.status + "] " + t.content).join(String.fromCharCode(10));
      const prompt = [CONTINUATION_PROMPT, "",
        "[Status: " + (total - fresh) + "/" + total + " completed, " + fresh + " remaining]",
        "", "Remaining tasks:", list].join(String.fromCharCode(10));

      st.inFlight = true;
      try {
        agent.steer(createUserMessage({
          content: [{ type: "text", text: prompt }],
          source: { kind: "user" },
        }));
        st.inFlight = false;
        st.lastInjectedAt = Date.now();
        st.consecutiveFailures = 0;
      } catch (err) {
        st.inFlight = false;
        st.lastInjectedAt = Date.now();
        st.consecutiveFailures += 1;
        if (isTokenLimit(err)) st.tokenLimitDetected = true;
        if (isUnrecoverable(err)) st.unrecoverableErrorDetected = true;
      }
    }

    function emitToast(message: string): void {
      (globalThis as any).__boulderToast?.(message);
    }

Примечание по реализации: в реальном коде state-store хранится в замыкании
apply и передаётся явно (здесь для краткости — через ctx.__boulderStore);
чтение todos — через ctx.inject(["sessionProjections"], ...) либо fold
agent.session.events; имя события компакции заменить на фактическое из
dsh-compaction. Код — скелет ключевой логики, не продакшен.

### src/client.ts (браузер)

    window.__ModuleLoader__.load({
      id: "@deepseek-ai/dsh-boulder/client",
      factory: () => {
        let toastEl: HTMLElement | null = null;
        (window as any).__boulderToast = (message: string) => {
          toastEl?.remove();
          toastEl = document.createElement("div");
          toastEl.textContent = message;
          Object.assign(toastEl.style, {
            position: "fixed", bottom: "16px", right: "16px", zIndex: "9999",
            background: "var(--color-warning, #b45309)", color: "#fff",
            padding: "8px 12px", borderRadius: "8px", fontFamily: "monospace",
          });
          document.body.appendChild(toastEl);
          setTimeout(() => toastEl?.remove(), 900);
        };
      },
    });

## 4. Риски / открытые вопросы

1. 30s vs 5s. Бэклог (agent-harness-features.ru.md, agent-guards.ru.md) фиксирует
   «backoff 30s×2», но omo constants.ts — CONTINUATION_COOLDOWN_MS = 5_000 как
   базу экспоненты. Нужно явное решение владельца: 30s (по бэклогу) или 5s (по
   коду omo).
2. steer vs inject. steer будит агента и может быть воспринят как новое
   пользовательское сообщение; нужен internal-source UserMessage или
   dedupe-маркер, чтобы не попасть в «user-interruption» и не зациклить
   классификацию. В omo это createInternalAgentContinuationTextPart +
   prompt-async-gate; в DSH аналога нет.
3. skip-agents. omo-список prometheus/compaction/plan не маппится 1:1 на
   DSH-агентов; решить, какие DSH-роли/субагенты исключать (вероятно:
   compaction-агент, plan-mode агент, subagent-сессии).
4. Compaction-событие. В DSH компакцию делает dsh-compaction; имя события и
   payload (session.compacted?) надо подтвердить по его типам, иначе guard не
   сработает.
5. Pending question. omo использует hasUnansweredQuestion по сообщениям; в DSH
   вопросы — dsh-user-questions / ask_user_question. Нужен точный признак «ждём
   ответа пользователя», чтобы не будить агента поверх вопроса.
6. Персистентность состояния. omo-стейт живёт в памяти процесса. В DSH при
   перезапуске web-профиля счётчики (stagnation/failures) потеряются; либо
   смириться, либо хранить в session-проекции/JSON-файле.
7. Гонки и reentrancy. agent/status — emit; инъекция асинхронна. Нужен inFlight
   + отмена countdown на любом running/tool/message-событии, иначе возможны
   двойные инъекции на быстрых idle⇄running флипах.
8. Тесты. Покрыть на dsh-agent-loop-testkit: idle+incomplete → инъекция; все
   skip-условия; cooldown/backoff; stagnation 3; compaction-guard 60s;
   abort-window; token-limit; user-interruption.
9. Права. Перед инъекцией проверять, что агент имеет edit/write-пермишены;
   read-only агента будить бессмысленно (в omo — hasWritePermission).
10. UI-прозрачность. Toast 900ms в client.ts — минимум; желательно показать
    причину («boulder: 3 tasks remaining») и дать пользователю кнопку «стоп»
    (isContinuationStopped).

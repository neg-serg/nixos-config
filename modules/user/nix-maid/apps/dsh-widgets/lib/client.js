/**
 * dsh-widgets, browser half.
 *
 * Two families of keyed `tool.call.toolview` cards:
 *   1. `json` — a collapsible, syntax-highlighted JSON tree over the tool's
 *      persisted presentationMeta descriptor (replay-stable, no re-parse).
 *   2. subagent / subagent_fork / workflow / ralph / goal / jobs / list_agents —
 *      readable cards over the tool args + rendered result text, replacing the
 *      stock "Tool call" generic row that otherwise shows a raw JSON dump. The
 *      subagent card shows the full prompt (collapsed by default), so a
 *      delegated task reads as text, not as a JSON blob.
 *
 * Plus a DOM-level transform for the subagent settlement notice: when a
 * background subagent settles, the parent session receives a user message with
 * source.kind "subagent-settled" whose body re-emits the child's closing
 * message. The stock UI renders that as a "context" row whose non-text blocks
 * (reasoning / tool-call) fall back to "Unknown content block" JSON dumps.
 * This transform replaces those rows with a readable card — status badge,
 * short child id, and the closing message (text + collapsible reasoning /
 * tool calls) — read straight from the live "chat" projection, then the stock
 * row is hidden (React never sees the injected card).
 *
 * Everything renders with React.createElement + text nodes only — no
 * dangerouslySetInnerHTML (the JSON value comes from the model's own output and
 * is treated as untrusted). Theme colors come from the host's --dsw-alias-*
 * design tokens, so dark/light follows automatically.
 */

window.__ModuleLoader__.load({
  id: "dsh-widgets",
  factory: (require) => {
    const React = require("react");
    const h = React.createElement;
    const { useState, useMemo } = React;

    const inject = ["slots", "sessions"];

    const MAX_DEPTH = 400;
    const CHILD_CAP = 100;
    const STRING_PREVIEW = 200;

    // ---------------------------------------------------------------------
    // shared helpers
    // ---------------------------------------------------------------------

    function isContainer(v) {
      return v !== null && typeof v === "object";
    }

    function done(block) {
      return "kind" in block;
    }

    function argsRaw(block) {
      return (done(block) ? block.call?.argsRaw : block.argsRaw) ?? "";
    }

    function parseArgs(block) {
      const raw = argsRaw(block);
      if (typeof raw !== "string" || raw === "") return null;
      try {
        const parsed = JSON.parse(raw);
        return parsed !== null && typeof parsed === "object" ? parsed : null;
      } catch {
        return null;
      }
    }

    function resultText(block) {
      if (!done(block) || !Array.isArray(block.content)) return null;
      const text = block.content
        .filter((b) => b !== null && typeof b === "object" && b.type === "text" && typeof b.text === "string")
        .map((b) => b.text)
        .join("\n")
        .trim();
      return text === "" ? null : text;
    }

    function firstResultLine(block) {
      const text = resultText(block);
      if (text === null) return "результат";
      const newline = text.indexOf("\n");
      return newline === -1 ? text : text.slice(0, newline);
    }

    function indent(depth) {
      return { paddingLeft: depth * 14 };
    }

    // ---------------------------------------------------------------------
    // JSON tree
    // ---------------------------------------------------------------------

    function narrowMeta(meta) {
      if (typeof meta !== "object" || meta === null) return undefined;
      if (meta.kind !== "json-tree") return undefined;
      if (typeof meta.title !== "string") return undefined;
      const out = { kind: "json-tree", title: meta.title };
      if (Object.prototype.hasOwnProperty.call(meta, "value")) out.value = meta.value;
      for (const k of ["sizeBytes", "nodes", "depth", "truncatedNodes"]) {
        if (typeof meta[k] === "number" && Number.isFinite(meta[k])) out[k] = meta[k];
      }
      if (meta.truncated === true) out.truncated = true;
      if (typeof meta.path === "string") out.path = meta.path;
      if (typeof meta.error === "object" && meta.error !== null && typeof meta.error.message === "string") {
        out.error = { message: meta.error.message };
        if (typeof meta.error.line === "number") out.error.line = meta.error.line;
        if (typeof meta.error.column === "number") out.error.column = meta.error.column;
      }
      if (out.value === undefined && out.error === undefined) return undefined;
      return out;
    }

    function childPath(path, key, isArray) {
      if (isArray) return path + "[" + key + "]";
      return /^[A-Za-z_$][A-Za-z0-9_$]*$/u.test(key) ? path + "." + key : path + "[" + JSON.stringify(key) + "]";
    }

    function scalarClass(v) {
      if (v === null) return "dw-null";
      if (typeof v === "string") return "dw-str";
      if (typeof v === "number") return "dw-num";
      if (typeof v === "boolean") return "dw-bool";
      return "dw-null";
    }

    function displayScalar(v) {
      if (v === null) return "null";
      if (typeof v === "string") {
        const s = JSON.stringify(v);
        return s.length > STRING_PREVIEW ? s.slice(0, STRING_PREVIEW - 1) + "…" : s;
      }
      return String(v);
    }

    function fullScalar(v) {
      if (v === null) return "null";
      if (typeof v === "string") return JSON.stringify(v);
      return String(v);
    }

    function collectContainers(value) {
      const out = [];
      const stack = [{ v: value, path: "$", depth: 0 }];
      while (stack.length > 0) {
        const { v, path, depth } = stack.pop();
        if (!isContainer(v)) continue;
        out.push({ path, depth });
        const isArray = Array.isArray(v);
        const keys = isArray ? v.map((_, i) => String(i)) : Object.keys(v);
        for (let i = keys.length - 1; i >= 0; i -= 1) {
          const k = keys[i];
          stack.push({ v: v[k], path: childPath(path, k, isArray), depth: depth + 1 });
        }
      }
      return out;
    }

    function flattenSearchRows(value) {
      const rows = [];
      const stack = [{ v: value, name: null, path: "$" }];
      while (stack.length > 0) {
        const { v, name, path } = stack.pop();
        if (isContainer(v)) {
          const isArray = Array.isArray(v);
          const count = isArray ? v.length : Object.keys(v).length;
          rows.push({
            path,
            name,
            text: (isArray ? "[" : "{") + (count === 0 ? (isArray ? "]" : "}") : " " + count + " …"),
          });
          const keys = isArray ? v.map((_, i) => String(i)) : Object.keys(v);
          for (let i = keys.length - 1; i >= 0; i -= 1) {
            const k = keys[i];
            stack.push({ v: v[k], name: k, path: childPath(path, k, isArray) });
          }
        } else {
          rows.push({ path, name, text: displayScalar(v) });
        }
      }
      return rows;
    }

    function JsonNode(props) {
      const { value, name, depth, path, expanded, onToggle, windowMap, onMore } = props;

      if (isContainer(value) && depth > MAX_DEPTH) {
        return h(
          "div",
          { className: "dw-row", style: indent(depth) },
          name !== null ? h("span", { className: "dw-key" }, String(name), h("span", { className: "dw-punct" }, ": ")) : null,
          h("span", { className: "dw-null" }, "(вложенность > " + MAX_DEPTH + " — не отображается)")
        );
      }

      if (!isContainer(value)) {
        return h(
          "div",
          { className: "dw-row", style: indent(depth) },
          h("span", { className: "dw-toggle dw-toggle-none" }, ""),
          name !== null ? h("span", { className: "dw-key" }, String(name), h("span", { className: "dw-punct" }, ": ")) : null,
          h("span", { className: scalarClass(value), title: fullScalar(value) }, displayScalar(value))
        );
      }

      const isArray = Array.isArray(value);
      const childCount = isArray ? value.length : Object.keys(value).length;
      const open = expanded.has(path);
      const win = windowMap.get(path) ?? CHILD_CAP;
      const openChar = isArray ? "[" : "{";
      const closeChar = isArray ? "]" : "}";

      const toggleEl = childCount > 0
        ? h("button", { className: "dw-toggle", onClick: () => onToggle(path), "aria-label": open ? "Свернуть" : "Развернуть" }, open ? "▾" : "▸")
        : h("span", { className: "dw-toggle dw-toggle-none" }, "");

      const headSummary = open
        ? h("span", { className: "dw-punct" }, openChar)
        : h("span", { className: "dw-punct" }, openChar + (childCount === 0 ? closeChar : " … " + childCount + " " + closeChar));

      const rows = [];
      if (open) {
        const keys = isArray ? value.map((_, i) => String(i)) : Object.keys(value);
        const slice = keys.slice(0, win);
        for (const k of slice) {
          const cp = childPath(path, k, isArray);
          rows.push(h(JsonNode, { key: cp, value: value[k], name: k, depth: depth + 1, path: cp, expanded, onToggle, windowMap, onMore }));
        }
        if (childCount > win) {
          rows.push(h(
            "div",
            { key: path + "__more", className: "dw-row", style: indent(depth + 1) },
            h("button", { className: "dw-more", onClick: () => onMore(path) }, "+ ещё " + (childCount - win))
          ));
        }
        rows.push(h(
          "div",
          { key: path + "__close", className: "dw-row", style: indent(depth) },
          h("span", { className: "dw-toggle dw-toggle-none" }, ""),
          h("span", { className: "dw-punct" }, closeChar)
        ));
      }

      return h(
        "div",
        null,
        h(
          "div",
          { className: "dw-row", style: indent(depth) },
          toggleEl,
          name !== null ? h("span", { className: "dw-key" }, String(name), h("span", { className: "dw-punct" }, ": ")) : null,
          headSummary
        ),
        rows
      );
    }

    function Highlight(props) {
      const { text, q } = props;
      if (!q) return text;
      const lower = text.toLowerCase();
      const parts = [];
      let i = 0;
      while (true) {
        const idx = lower.indexOf(q, i);
        if (idx === -1) {
          parts.push(text.slice(i));
          break;
        }
        if (idx > i) parts.push(text.slice(i, idx));
        parts.push(h("mark", { className: "dw-mark", key: parts.length }, text.slice(idx, idx + q.length)));
        i = idx + q.length;
      }
      return parts;
    }

    function JsonTreeBody(props) {
      const { value, title, nodes, depth, sizeBytes, truncated, truncatedNodes } = props;
      const containers = useMemo(() => collectContainers(value), [value]);
      const [expanded, setExpanded] = useState(() => {
        const s = new Set();
        for (const c of containers) if (c.depth < 3) s.add(c.path);
        return s;
      });
      const [windowMap, setWindowMap] = useState(() => new Map());
      const [query, setQuery] = useState("");
      const [copied, setCopied] = useState(false);

      const toggle = (path) => {
        setExpanded((prev) => {
          const next = new Set(prev);
          if (next.has(path)) next.delete(path);
          else next.add(path);
          return next;
        });
      };
      const expandAll = () => setExpanded(new Set(containers.map((c) => c.path)));
      const collapseAll = () => setExpanded(new Set());
      const onMore = (path) => {
        setWindowMap((prev) => {
          const next = new Map(prev);
          next.set(path, (next.get(path) ?? CHILD_CAP) + CHILD_CAP);
          return next;
        });
      };
      const copy = () => {
        try {
          const text = JSON.stringify(value, null, 2);
          if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).catch(() => {});
          }
        } catch {
          /* ignore */
        }
        setCopied(true);
        setTimeout(() => setCopied(false), 1500);
      };

      const searchRows = useMemo(() => (query.trim() === "" ? null : flattenSearchRows(value)), [value, query]);

      const badges = [];
      if (typeof nodes === "number") badges.push(h("span", { key: "n", className: "dw-chip" }, nodes + " узлов"));
      if (typeof depth === "number") badges.push(h("span", { key: "d", className: "dw-chip" }, "глубина " + depth));
      if (typeof sizeBytes === "number") badges.push(h("span", { key: "s", className: "dw-chip" }, humanBytes(sizeBytes)));

      const searchResults = searchRows === null ? null : (() => {
        const q = query.trim().toLowerCase();
        const matches = searchRows.filter(
          (r) => r.path.toLowerCase().includes(q) || (r.name !== null && String(r.name).toLowerCase().includes(q)) || r.text.toLowerCase().includes(q)
        );
        const shown = matches.slice(0, 200);
        return h(
          "div",
          { className: "dw-search" },
          h("div", { className: "dw-search-meta" }, "Найдено: " + matches.length + (matches.length > 200 ? " (показано первые 200)" : "")),
          shown.map((r, i) =>
            h(
              "div",
              { key: i, className: "dw-row dw-search-row" },
              h("span", { className: "dw-search-path", title: r.path }, r.path),
              r.name !== null
                ? h("span", { className: "dw-key" }, Highlight({ text: String(r.name), q }), h("span", { className: "dw-punct" }, ": "))
                : null,
              h("span", { className: "dw-search-text" }, Highlight({ text: r.text, q }))
            )
          )
        );
      })();

      return h(
        "div",
        { className: "dw-tree-wrap" },
        h(
          "div",
          { className: "dw-toolbar" },
          h("span", { className: "dw-tree-title" }, title),
          badges,
          h("span", { className: "dw-toolbar-spacer" }),
          h("input", {
            className: "dw-search-input",
            type: "search",
            placeholder: "Поиск…",
            value: query,
            onChange: (e) => setQuery(e.target.value),
          }),
          h("button", { className: "dw-btn", onClick: expandAll, title: "Развернуть всё" }, "⤢"),
          h("button", { className: "dw-btn", onClick: collapseAll, title: "Свернуть всё" }, "⤡"),
          h("button", { className: "dw-btn", onClick: copy, title: "Скопировать JSON" }, copied ? "✓" : "⧉")
        ),
        truncated === true
          ? h("div", { className: "dw-truncated" }, "Показан фрагмент — полный JSON обрезан на сервере" + (typeof truncatedNodes === "number" ? " (" + truncatedNodes + " узлов скрыто)" : ""))
          : null,
        h(
          "div",
          { className: "dw-tree" },
          searchResults !== null
            ? searchResults
            : h(JsonNode, { value, name: null, depth: 0, path: "$", expanded, onToggle: toggle, windowMap, onMore })
        )
      );
    }

    function humanBytes(n) {
      if (n < 1024) return n + " Б";
      if (n < 1024 * 1024) return (n / 1024).toFixed(1) + " КБ";
      return (n / (1024 * 1024)).toFixed(2) + " МБ";
    }

    function JsonTreeCard({ block }) {
      if (!done(block)) {
        return h("div", { className: "dw-inline" }, "JSON · рендеринг…");
      }
      if (block.isError) {
        return h("div", { className: "dw-inline" }, "JSON · " + firstResultLine(block));
      }
      const meta = narrowMeta(block.meta);
      if (meta === undefined) {
        return h("div", { className: "dw-inline" }, firstResultLine(block));
      }
      if (meta.error !== undefined) {
        return h(
          "div",
          { className: "dw-card" },
          h(
            "div",
            { className: "dw-head" },
            h("span", { className: "dw-badge dw-badge-error" }, h("span", { className: "dw-dot" }), "Ошибка парсинга"),
            h("span", { className: "dw-label" }, meta.title)
          ),
          h("div", { className: "dw-body" },
            h("div", { className: "dw-err-msg" }, meta.error.message),
            meta.error.line !== undefined
              ? h("div", { className: "dw-err-pos" }, "строка " + meta.error.line + ", столбец " + meta.error.column)
              : null)
        );
      }
      return JsonTreeBody({
        value: meta.value,
        title: meta.title,
        nodes: meta.nodes,
        depth: meta.depth,
        sizeBytes: meta.sizeBytes,
        truncated: meta.truncated,
        truncatedNodes: meta.truncatedNodes,
      });
    }

    // ---------------------------------------------------------------------
    // shared card frame + output
    // ---------------------------------------------------------------------

    function CardFrame(props) {
      const { title, badge, badgeCls, label, chips, children } = props;
      return h(
        "div",
        { className: "dw-card" },
        h(
          "div",
          { className: "dw-head" },
          h("span", { className: "dw-title" }, title),
          badge ? h("span", { className: "dw-badge " + badgeCls }, h("span", { className: "dw-dot" }), badge) : null,
          label ? h("span", { className: "dw-label" }, label) : null,
          chips ? chips.map((c, i) => h("span", { key: i, className: "dw-chip" }, c)) : null
        ),
        children ? h("div", { className: "dw-body" }, children) : null
      );
    }

    function LongText(props) {
      const { text } = props;
      const [open, setOpen] = useState(false);
      const long = text.length > 2000;
      const shown = long && !open ? text.slice(0, 2000) + "…" : text;
      return h(
        "div",
        null,
        h("pre", { className: "dw-out" }, shown),
        long
          ? h("button", { className: "dw-more", onClick: () => setOpen((o) => !o) }, open ? "Свернуть" : "Развернуть весь вывод")
          : null
      );
    }

    // ---------------------------------------------------------------------
    // agent-activity cards
    // ---------------------------------------------------------------------

    function PromptToggle(props) {
      const { prompt } = props;
      const [open, setOpen] = useState(false);
      if (typeof prompt !== "string" || prompt === "") return null;
      return h(
        "div",
        { className: "dw-prompt" },
        h(
          "button",
          { className: "dw-more", onClick: () => setOpen((o) => !o) },
          open ? "Скрыть промпт ▴" : "Показать промпт ▾"
        ),
        h("span", { className: "dw-prompt-count" }, prompt.length + " симв."),
        open ? h("pre", { className: "dw-out dw-prompt-text" }, prompt) : null
      );
    }

    function SubagentCard(props) {
      const { block } = props;
      const settled = done(block);
      const args = parseArgs(block);
      const description = typeof args?.description === "string" && args.description.trim() !== "" ? args.description.trim() : null;
      const background = args?.run_in_background === true;
      const prompt = typeof args?.prompt === "string" && args.prompt.trim() !== "" ? args.prompt : null;
      const chips = background ? ["фон"] : [];
      const children = [];
      const promptToggle = PromptToggle({ prompt });
      if (promptToggle !== null) children.push(promptToggle);
      if (!settled) {
        return CardFrame({ title: "Субагент", badge: "Выполняется", badgeCls: "dw-badge-running", label: description, chips, children });
      }
      const text = resultText(block);
      if (block.isError) {
        if (text !== null) children.push(h(LongText, { text }));
        return CardFrame({ title: "Субагент", badge: "Ошибка", badgeCls: "dw-badge-error", label: description, chips, children });
      }
      if (text !== null && text.startsWith("started background subagent task ")) {
        chips.push(text.slice("started background subagent task ".length).trim());
        return CardFrame({ title: "Субагент", badge: "Фоновая задача", badgeCls: "dw-badge-muted", label: description, chips, children });
      }
      if (text !== null && text.startsWith("started subagent ")) {
        chips.push(text.slice("started subagent ".length).trim());
        return CardFrame({ title: "Субагент", badge: "Запущен", badgeCls: "dw-badge-done", label: description, chips, children });
      }
      if (text !== null) children.push(h(LongText, { text }));
      return CardFrame({ title: "Субагент", badge: "Готово", badgeCls: "dw-badge-done", label: description, chips, children });
    }

    function WorkflowCard(props) {
      const { block } = props;
      const settled = done(block);
      const args = parseArgs(block);
      const wfName = typeof args?.meta?.name === "string" && args.meta.name.trim() !== "" ? args.meta.name.trim() : null;
      if (!settled) {
        return CardFrame({ title: "Workflow", badge: "Выполняется", badgeCls: "dw-badge-running", label: wfName });
      }
      const text = resultText(block) || "";
      if (block.isError) {
        return CardFrame({ title: "Workflow", badge: "Ошибка", badgeCls: "dw-badge-error", label: wfName, children: h(LongText, { text }) });
      }
      const m = /^workflow "(.*)" completed \((\d+) agent\(s\)\)\.\nReturn value:\n([\s\S]*)$/u.exec(text);
      let agents;
      let resultJson;
      if (m) {
        agents = m[2];
        resultJson = m[3];
      }
      let parsed;
      let parseFailed = false;
      if (resultJson !== undefined) {
        try {
          parsed = JSON.parse(resultJson);
        } catch {
          parseFailed = true;
        }
      }
      const chips = agents !== undefined ? [agents + " агент(ов)"] : null;
      if (parsed !== undefined) {
        return CardFrame({ title: "Workflow", badge: "Завершён", badgeCls: "dw-badge-done", label: wfName, chips, children: JsonTreeBody({ value: parsed, title: "Результат" }) });
      }
      return CardFrame({ title: "Workflow", badge: "Завершён", badgeCls: "dw-badge-done", label: wfName, chips, children: h(LongText, { text: parseFailed ? resultJson : text }) });
    }

    function RalphCard(props) {
      const { block } = props;
      const settled = done(block);
      if (!settled) {
        return CardFrame({ title: "Ralph", badge: "Выполняется", badgeCls: "dw-badge-running" });
      }
      const text = resultText(block) || "";
      if (block.isError) {
        return CardFrame({ title: "Ralph", badge: "Ошибка", badgeCls: "dw-badge-error", children: h(LongText, { text }) });
      }
      let badge = "Готово";
      let badgeCls = "dw-badge-done";
      if (text.startsWith("Ralph worker reported a blocker")) {
        badge = "Блокировка";
        badgeCls = "dw-badge-error";
      } else if (text.startsWith("Ralph reached its")) {
        badge = "Лимит раундов";
        badgeCls = "dw-badge-warn";
      }
      const roundMatch = /after (\d+)/u.exec(text) || /its (\d+) limit/u.exec(text);
      const rounds = roundMatch ? roundMatch[1] : null;

      const idx = text.indexOf("\nFinal report:\n");
      let report = null;
      if (idx !== -1) {
        try {
          report = JSON.parse(text.slice(idx + "\nFinal report:\n".length));
        } catch {
          report = null;
        }
      }
      const children = [];
      if (report !== null && typeof report === "object") {
        if (typeof report.summary === "string" && report.summary !== "") {
          children.push(h("div", { className: "dw-ralph-summary" }, report.summary));
        }
        if (Array.isArray(report.evidence) && report.evidence.length > 0) {
          children.push(h("div", { className: "dw-ralph-evidence" },
            h("div", { className: "dw-ralph-h" }, "Сделано:"),
            report.evidence.map((e, i) => h("div", { key: i, className: "dw-ralph-e" }, "• " + e))));
        }
        if (Array.isArray(report.nextSteps) && report.nextSteps.length > 0) {
          children.push(h("div", { className: "dw-ralph-next" },
            h("div", { className: "dw-ralph-h" }, "Дальше:"),
            report.nextSteps.map((e, i) => h("div", { key: i, className: "dw-ralph-n" }, (i + 1) + ". " + e))));
        }
        if (typeof report.blocker === "string" && report.blocker !== "") {
          children.push(h("div", { className: "dw-blocked" }, report.blocker));
        }
      } else {
        children.push(h(LongText, { text }));
      }
      return CardFrame({ title: "Ralph", badge, badgeCls, chips: rounds ? [rounds + " раунд(ов)"] : null, children });
    }

    function GoalCard(props) {
      const { block } = props;
      const settled = done(block);
      if (!settled) {
        return CardFrame({ title: "Цель", badge: "Выполняется", badgeCls: "dw-badge-running" });
      }
      const text = resultText(block);
      let parsed = null;
      if (text) {
        try {
          parsed = JSON.parse(text);
        } catch {
          parsed = null;
        }
      }
      const goal = parsed !== null && parsed.goal !== undefined ? parsed.goal : null;
      const activation = parsed?.activation;
      if (goal === null) {
        return CardFrame({ title: "Цель", badge: "Нет активной цели", badgeCls: "dw-badge-muted" });
      }
      const phase = goal.phase;
      const badge = phase === "active"
        ? ["Активна", "dw-badge-running"]
        : phase === "paused"
          ? ["Пауза", "dw-badge-warn"]
          : phase === "blocked"
            ? ["Заблокирована", "dw-badge-error"]
            : phase === "complete"
              ? ["Завершена", "dw-badge-done"]
              : [String(phase ?? "—"), "dw-badge-muted"];
      const chips = [];
      if (typeof goal.roundsStarted === "number" && typeof goal.maxGoalRounds === "number") {
        chips.push("раунды " + goal.roundsStarted + "/" + goal.maxGoalRounds);
      }
      if (activation === "disarmed") chips.push("не вооружена");
      const children = [];
      if (typeof goal.objective === "string" && goal.objective !== "") {
        children.push(h("div", { className: "dw-goal-obj" }, goal.objective));
      }
      if (phase === "blocked" && goal.blockedReason && typeof goal.blockedReason.message === "string") {
        children.push(h("div", { className: "dw-blocked" }, goal.blockedReason.message));
      }
      return CardFrame({ title: "Цель", badge: badge[0], badgeCls: badge[1], chips, children });
    }

    function JobCard(props) {
      const { block } = props;
      const settled = done(block);
      const args = parseArgs(block);
      const jobId = typeof args?.job_id === "string" ? args.job_id : null;
      if (!settled) {
        return CardFrame({ title: "Задача", badge: "Чтение…", badgeCls: "dw-badge-running", chips: jobId ? [jobId] : null });
      }
      const text = resultText(block);
      if (block.isError) {
        return CardFrame({ title: "Задача", badge: "Ошибка", badgeCls: "dw-badge-error", chips: jobId ? [jobId] : null, children: text ? h(LongText, { text }) : null });
      }
      const statusMatch = text ? /\[status: ([^\]]+)\]\s*$/u.exec(text) : null;
      const status = statusMatch ? statusMatch[1].split(",")[0].trim() : null;
      const badge = status === "running"
        ? ["Выполняется", "dw-badge-running"]
        : status === "completed"
          ? ["Завершена", "dw-badge-done"]
          : status === "killed"
            ? ["Остановлена", "dw-badge-warn"]
            : status === "failed"
              ? ["Ошибка", "dw-badge-error"]
              : status === "stopping"
                ? ["Останавливается", "dw-badge-warn"]
                : [status ?? "Задача", "dw-badge-muted"];
      return CardFrame({ title: "Задача", badge: badge[0], badgeCls: badge[1], chips: jobId ? [jobId] : null, children: text ? h(LongText, { text }) : null });
    }

    function JobListCard(props) {
      const { block } = props;
      if (!done(block)) {
        return CardFrame({ title: "Задачи", badge: "Чтение…", badgeCls: "dw-badge-running" });
      }
      const text = resultText(block);
      return CardFrame({ title: "Задачи", badge: "Список", badgeCls: "dw-badge-muted", children: text ? h(LongText, { text }) : null });
    }

    function JobKillCard(props) {
      const { block } = props;
      const settled = done(block);
      const args = parseArgs(block);
      const jobId = typeof args?.job_id === "string" ? args.job_id : null;
      if (!settled) {
        return CardFrame({ title: "Остановка задачи", badge: "…", badgeCls: "dw-badge-running", chips: jobId ? [jobId] : null });
      }
      const text = resultText(block) || "";
      const already = text.includes("had already finished");
      return CardFrame({
        title: "Остановка задачи",
        badge: already ? "Уже завершена" : "Запрос отправлен",
        badgeCls: already ? "dw-badge-muted" : "dw-badge-warn",
        chips: jobId ? [jobId] : null,
      });
    }

    function ListAgentsCard(props) {
      const { block } = props;
      if (!done(block)) {
        return CardFrame({ title: "Субагенты", badge: "Чтение…", badgeCls: "dw-badge-running" });
      }
      const text = resultText(block);
      return CardFrame({ title: "Субагенты", badge: "Список", badgeCls: "dw-badge-muted", children: text ? h(LongText, { text }) : null });
    }

    // ---------------------------------------------------------------------
    // subagent settlement notices ("unknown content block" fix)
    // ---------------------------------------------------------------------
    //
    // When a background subagent settles, the parent session receives a user
    // message with source.kind "subagent-settled". The stock UI projects it as
    // a "context" chat node whose body re-emits the child's closing message;
    // every non-text block (reasoning / tool-call) falls back to an
    // "Unknown content block" JSON dump. There is no keyed slot for it, so
    // this transform works at the DOM level, reading the notice data from the
    // live "chat" projection (same store the chat view renders from):
    //
    //   1. find the stock row by its data-chat-flow-key;
    //   2. build a readable card (badge + child id + closing message with
    //      collapsible reasoning / tool calls) from the projection node;
    //   3. insert the card before the row and hide the row.
    //
    // React never sees the injected card; when a re-render recreates the stock
    // row, the observer re-applies the transform. All text goes through
    // textContent — the blocks are the child model's own output (untrusted).

    const NOTICE_STATUS_PATTERNS = [
      { re: /failed before it finished/u, badge: "Упал", cls: "dw-badge-error" },
      { re: /ended abnormally/u, badge: "Оборван", cls: "dw-badge-error" },
      { re: /ran out of room/u, badge: "Лимит токенов", cls: "dw-badge-warn" },
      { re: /was stopped before it finished/u, badge: "Остановлен", cls: "dw-badge-warn" },
      { re: /declined the task/u, badge: "Отказ", cls: "dw-badge-muted" },
      { re: /finished and will do no further work/u, badge: "Завершён", cls: "dw-badge-done" },
    ];

    function noticeStatus(summary) {
      for (const p of NOTICE_STATUS_PATTERNS) {
        if (p.re.test(summary)) return p;
      }
      return { badge: "Уведомление", cls: "dw-badge-muted" };
    }

    function noticeEl(tag, className, text) {
      const node = document.createElement(tag);
      if (className !== undefined && className !== "") node.className = className;
      if (text !== undefined && text !== null) node.textContent = text;
      return node;
    }

    function shortId(id) {
      if (typeof id !== "string" || id === "") return null;
      return id.length <= 14 ? id : id.slice(0, 8) + "…" + id.slice(-4);
    }

    function capText(s, max) {
      if (typeof s !== "string") return "";
      return s.length > max ? s.slice(0, max) + "\n… (обрезано)" : s;
    }

    // One collapsible section: a toggle button plus a hidden <pre>.
    function noticeCollapsible(title, text, cls, defaultOpen) {
      const wrap = noticeEl("div", "dw-notice-collapsible");
      const pre = noticeEl("pre", "dw-out " + cls, text);
      pre.style.display = defaultOpen ? "block" : "none";
      const btn = noticeEl("button", "dw-more dw-notice-toggle");
      btn.textContent = (defaultOpen ? "▾" : "▸") + " " + title;
      btn.addEventListener("click", () => {
        const opening = pre.style.display === "none";
        pre.style.display = opening ? "block" : "none";
        btn.textContent = (opening ? "▾" : "▸") + " " + title;
      });
      wrap.appendChild(btn);
      wrap.appendChild(pre);
      return wrap;
    }

    function noticeBlock(b) {
      if (b !== null && typeof b === "object" && b.type === "reasoning" && typeof b.text === "string") {
        const short = b.text.length > 120 ? b.text.slice(0, 120) + "…" : b.text;
        return noticeCollapsible("Размышления · " + short, b.text, "dw-notice-reason", b.text.length < 2500);
      }
      if (b !== null && typeof b === "object" && (b.type === "tool-call" || b.type === "tool-call-delta")) {
        const name = typeof b.name === "string" ? b.name : "tool";
        let argsText = "";
        try {
          argsText = JSON.stringify(b.arguments ?? b.input ?? {}, null, 1);
        } catch {
          argsText = String(b.arguments ?? "");
        }
        return noticeCollapsible("🛠 " + name, capText(argsText, 600), "dw-notice-tool", false);
      }
      if (b !== null && typeof b === "object" && (b.type === "tool-result" || b.type === "tool-result-delta")) {
        let json;
        try {
          json = JSON.stringify({ result: b }, null, 1);
        } catch {
          json = String(b);
        }
        return noticeCollapsible("Результат вызова", capText(json, 600), "dw-notice-tool", false);
      }
      let json;
      try {
        json = JSON.stringify(b, null, 1);
      } catch {
        json = String(b);
      }
      return noticeCollapsible("Блок", capText(json, 600), "dw-notice-tool", false);
    }

    function buildNoticeCard(node) {
      const data = node.data;
      const source = data && typeof data.source === "object" && data.source !== null ? data.source : {};
      const summary = typeof source.summary === "string" ? source.summary : "";
      const st = noticeStatus(summary);
      const sender = shortId(source.senderSessionId);
      const content = Array.isArray(data.content) ? data.content : [];

      const card = noticeEl("div", "dw-card dw-notice");
      const head = noticeEl("div", "dw-head");
      head.appendChild(noticeEl("span", "dw-title", "Субагент"));
      const badge = noticeEl("span", "dw-badge " + st.cls);
      badge.appendChild(noticeEl("span", "dw-dot"));
      badge.appendChild(document.createTextNode(st.badge));
      head.appendChild(badge);
      if (sender !== null) head.appendChild(noticeEl("span", "dw-chip", sender));
      if (summary !== "") head.appendChild(noticeEl("span", "dw-label", summary.replace(/^Background\s+/u, "")));
      card.appendChild(head);

      const body = noticeEl("div", "dw-body");
      const texts = [];
      const blocks = [];
      for (const b of content) {
        if (b !== null && typeof b === "object" && b.type === "text" && typeof b.text === "string") texts.push(b.text);
        else if (b !== null && typeof b === "object") blocks.push(b);
      }
      // The first text block repeats the summary; the "Its closing message:"
      // line is a label — drop both from the body.
      let closingStart = texts.findIndex((t) => /closing message/i.test(t));
      if (closingStart === -1) closingStart = texts.length > 1 ? 1 : texts.length;
      const closingTexts = texts.slice(closingStart + 1);
      if (closingTexts.length > 0 || blocks.length > 0) {
        body.appendChild(noticeEl("div", "dw-ralph-h", "Заключительное сообщение"));
        for (const t of closingTexts) {
          body.appendChild(noticeEl("div", "dw-notice-para", t));
        }
        for (const b of blocks) {
          body.appendChild(noticeBlock(b));
        }
      } else {
        body.appendChild(noticeEl("div", "dw-notice-para", "Сообщения нет."));
      }
      card.appendChild(body);
      return card;
    }

    // ---------------------------------------------------------------------
    // styles
    // ---------------------------------------------------------------------

    const DW_CSS = `
      .dw-inline { font-size: 12px; opacity: 0.65; margin: 2px 0 6px; }
      .dw-card {
        border: 1px solid var(--dsw-alias-border-l1);
        border-radius: 12px;
        background: var(--dsw-alias-bg-layer-2);
        margin: 4px 0;
        overflow: hidden;
        font: var(--dsw-font-xs-13);
        color: var(--dsw-alias-label-primary);
      }
      .dw-head {
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 8px 12px;
        border-bottom: 1px solid var(--dsw-alias-border-l1);
        flex-wrap: wrap;
      }
      .dw-title { font-weight: 600; white-space: nowrap; }
      .dw-label { color: var(--dsw-alias-label-secondary); overflow-wrap: anywhere; min-width: 0; flex: 1 1 auto; }
      .dw-badge {
        flex: none; display: inline-flex; align-items: center; gap: 5px;
        font-size: 11px; line-height: 1; padding: 3px 8px; border-radius: 999px;
        border: 1px solid transparent; white-space: nowrap;
      }
      .dw-badge .dw-dot { width: 6px; height: 6px; border-radius: 50%; background: currentColor; }
      .dw-badge-running { color: var(--dsw-alias-state-business-primary); border-color: color-mix(in srgb, var(--dsw-alias-state-business-primary) 40%, transparent); background: color-mix(in srgb, var(--dsw-alias-state-business-primary) 12%, transparent); }
      .dw-badge-running .dw-dot { animation: dw-pulse 1.2s ease-in-out infinite; }
      .dw-badge-done { color: var(--dsw-alias-state-success-primary); border-color: color-mix(in srgb, var(--dsw-alias-state-success-primary) 40%, transparent); background: color-mix(in srgb, var(--dsw-alias-state-success-primary) 12%, transparent); }
      .dw-badge-error { color: var(--dsw-alias-state-error-primary); border-color: color-mix(in srgb, var(--dsw-alias-state-error-primary) 40%, transparent); background: color-mix(in srgb, var(--dsw-alias-state-error-primary) 12%, transparent); }
      .dw-badge-warn { color: var(--dsw-alias-state-warn-primary); border-color: color-mix(in srgb, var(--dsw-alias-state-warn-primary) 40%, transparent); background: color-mix(in srgb, var(--dsw-alias-state-warn-primary) 12%, transparent); }
      .dw-badge-muted { color: var(--dsw-alias-label-secondary); border-color: var(--dsw-alias-border-l1); background: var(--dsw-alias-bg-layer-3); }
      @keyframes dw-pulse { 0%, 100% { opacity: 0.35; } 50% { opacity: 1; } }
      .dw-chip {
        flex: none; font-family: var(--ds-font-family-code); font-size: 11px;
        padding: 2px 7px; border-radius: 6px; background: var(--dsw-alias-bg-layer-3);
        color: var(--dsw-alias-label-secondary); white-space: nowrap;
      }
      .dw-body { padding: 8px 12px 10px; }
      .dw-out {
        white-space: pre-wrap; overflow-wrap: anywhere; color: var(--dsw-alias-label-secondary);
        font-family: var(--ds-font-family-code); font-size: 12px; line-height: 1.5;
        max-height: 320px; overflow-y: auto; margin: 0;
      }
      .dw-more {
        border: 0; background: transparent; cursor: pointer; color: var(--dsw-alias-state-business-primary);
        font-size: 12px; padding: 2px 4px; border-radius: 4px;
      }
      .dw-more:hover { background: var(--dsw-alias-interactive-bg-hover); }
      .dw-goal-obj { line-height: 1.45; overflow-wrap: anywhere; }
      .dw-blocked {
        margin-top: 8px; padding: 8px 10px; border-radius: 8px;
        background: color-mix(in srgb, var(--dsw-alias-state-error-primary) 10%, transparent);
        border: 1px solid color-mix(in srgb, var(--dsw-alias-state-error-primary) 35%, transparent);
        color: var(--dsw-alias-state-error-primary); overflow-wrap: anywhere; line-height: 1.45;
      }
      .dw-ralph-summary { line-height: 1.45; overflow-wrap: anywhere; margin-bottom: 6px; }
      .dw-ralph-h { color: var(--dsw-alias-label-caption); font-size: 11px; text-transform: uppercase; letter-spacing: 0.04em; margin: 6px 0 3px; }
      .dw-ralph-e, .dw-ralph-n { line-height: 1.45; overflow-wrap: anywhere; padding-left: 4px; }
      .dw-err-msg { color: var(--dsw-alias-state-error-primary); font-family: var(--ds-font-family-code); font-size: 12px; overflow-wrap: anywhere; }
      .dw-err-pos { color: var(--dsw-alias-label-tertiary); font-size: 11px; margin-top: 4px; }

      .dw-prompt { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
      .dw-prompt-count { color: var(--dsw-alias-label-tertiary); font-size: 11px; }
      .dw-prompt-text { max-height: 320px; overflow-y: auto; }

      .dw-notice { margin: 4px 0; }
      .dw-notice-para { line-height: 1.5; overflow-wrap: anywhere; color: var(--dsw-alias-label-secondary); }
      .dw-notice-para + .dw-notice-para { margin-top: 6px; }
      .dw-notice-collapsible { margin-top: 6px; }
      .dw-notice-toggle { font-size: 12px; padding: 2px 4px; }
      .dw-notice-reason {
        color: var(--dsw-alias-label-secondary);
        border-left: 2px solid var(--dsw-alias-border-l2);
        padding-left: 10px;
        font-style: italic;
      }
      .dw-notice-tool { max-height: 260px; overflow-y: auto; }

      .dw-tree-wrap { display: flex; flex-direction: column; }
      .dw-toolbar {
        display: flex; align-items: center; gap: 8px; padding: 8px 12px;
        border-bottom: 1px solid var(--dsw-alias-border-l1); flex-wrap: wrap;
      }
      .dw-tree-title { font-weight: 600; white-space: nowrap; }
      .dw-toolbar-spacer { flex: 1; min-width: 8px; }
      .dw-btn {
        flex: none; border: 1px solid var(--dsw-alias-border-l1); background: var(--dsw-alias-bg-layer-3);
        color: var(--dsw-alias-label-secondary); cursor: pointer; font-size: 12px; line-height: 1;
        padding: 4px 7px; border-radius: 6px;
      }
      .dw-btn:hover { color: var(--dsw-alias-label-primary); background: var(--dsw-alias-interactive-bg-hover); }
      .dw-search-input {
        border: 1px solid var(--dsw-alias-border-l1); background: var(--dsw-alias-bg-layer-3);
        color: var(--dsw-alias-label-primary); font: var(--dsw-font-xs-13);
        padding: 3px 8px; border-radius: 6px; min-width: 120px;
      }
      .dw-search-input:focus { outline: none; border-color: var(--dsw-alias-state-business-primary); }
      .dw-truncated {
        padding: 6px 12px; color: var(--dsw-alias-state-warn-primary); font-size: 11px;
        background: color-mix(in srgb, var(--dsw-alias-state-warn-primary) 8%, transparent);
        border-bottom: 1px solid var(--dsw-alias-border-l1);
      }
      .dw-tree {
        font-family: var(--ds-font-family-code); font-size: 12px; line-height: 1.6;
        padding: 8px 12px 10px; overflow-x: auto; max-height: 560px; overflow-y: auto;
      }
      .dw-row { display: flex; align-items: baseline; white-space: nowrap; min-width: max-content; }
      .dw-toggle {
        flex: none; width: 16px; height: 16px; margin-right: 2px; border: 0; background: transparent;
        color: var(--dsw-alias-label-tertiary); cursor: pointer; padding: 0; font-size: 10px;
        line-height: 16px; text-align: center; border-radius: 4px;
      }
      .dw-toggle:hover { color: var(--dsw-alias-label-primary); background: var(--dsw-alias-interactive-bg-hover); }
      .dw-toggle-none { visibility: hidden; }
      .dw-key { color: var(--dsw-alias-brand-text); }
      .dw-punct { color: var(--dsw-alias-label-tertiary); }
      .dw-str { color: var(--dsw-alias-state-success-primary); }
      .dw-num { color: var(--dsw-alias-state-business-primary); }
      .dw-bool { color: var(--dsw-alias-state-warn-primary); }
      .dw-null { color: var(--dsw-alias-label-tertiary); font-style: italic; }
      .dw-search { display: flex; flex-direction: column; }
      .dw-search-meta { color: var(--dsw-alias-label-tertiary); font-size: 11px; margin-bottom: 4px; }
      .dw-search-row { display: flex; align-items: baseline; }
      .dw-search-path { color: var(--dsw-alias-label-tertiary); margin-right: 10px; flex: none; }
      .dw-search-text { color: var(--dsw-alias-label-secondary); }
      .dw-mark {
        background: var(--dsw-alias-interactive-bg-hover-accent); color: inherit;
        border-radius: 2px; padding: 0 1px;
      }
    `;

    // ---------------------------------------------------------------------
    // registration
    // ---------------------------------------------------------------------

    const KEYED_VIEWS = {
      json: JsonTreeCard,
      subagent: SubagentCard,
      subagent_fork: SubagentCard,
      workflow: WorkflowCard,
      ralph: RalphCard,
      get_goal: GoalCard,
      create_goal: GoalCard,
      update_goal: GoalCard,
      job_output: JobCard,
      job_list: JobListCard,
      job_kill: JobKillCard,
      list_agents: ListAgentsCard,
    };

    function apply(ctx) {
      ctx.slots.inject("tool.call.toolview", function* () {
        for (const key of Object.keys(KEYED_VIEWS)) {
          yield ctx.slots.register(
            { name: "tool.call.toolview", key, priority: -10 },
            KEYED_VIEWS[key]
          );
        }
      });

      // ---- settlement-notice transform ----
      const sessions = ctx.sessions;
      let boundSessionId = undefined;
      let unsubAny = null;
      let rafPending = false;

      function findNoticeRow(key) {
        if (key === undefined || key === null) return null;
        let safe;
        try {
          safe = CSS.escape(String(key));
        } catch {
          safe = String(key).replace(/[^a-zA-Z0-9:_-]/g, "\\$&");
        }
        return document.querySelector('[data-chat-flow-key="' + safe + '"]');
      }

      function rescan() {
        if (rafPending) return;
        rafPending = true;
        requestAnimationFrame(() => {
          rafPending = false;
          try {
            const list = sessions.list.getSnapshot();
            const sessionId = list.current;
            if (sessionId === undefined) return;
            const binding = sessions.binding(sessionId);
            const chat = binding?.session?.projections?.get("chat");
            if (chat === undefined || chat === null || typeof chat.order !== "object" || chat.order === null) return;
            for (const key of chat.order) {
              const node = chat.nodes.get(key);
              const data = node?.data;
              if (data === undefined || data === null || data.kind !== "context") continue;
              const source = data.source;
              if (source === undefined || source === null || source.kind !== "subagent-settled") continue;
              const row = findNoticeRow(key);
              if (row === null || row.dataset.dwNoticeHandled === "1") continue;
              const card = buildNoticeCard(node);
              if (card === null) continue;
              row.parentNode?.insertBefore(card, row);
              row.style.display = "none";
              row.dataset.dwNoticeHandled = "1";
            }
          } catch (err) {
            // A transform failure must never break the page or the plugin.
            if (typeof console !== "undefined") console.debug("dsh-widgets notice transform:", err);
          }
        });
      }

      function ensureBound() {
        const list = sessions.list.getSnapshot();
        const id = list.current;
        if (id === boundSessionId) return;
        if (unsubAny !== null) {
          try { unsubAny(); } catch { /* ignore */ }
          unsubAny = null;
        }
        boundSessionId = id;
        if (id === undefined) return;
        try {
          const binding = sessions.binding(id);
          const projections = binding?.session?.projections;
          if (projections !== undefined && projections !== null) unsubAny = projections.subscribeAny(rescan);
        } catch { /* ignore */ }
      }

      ctx.effect(() => {
        const style = document.createElement("style");
        style.setAttribute("data-plugin", "dsh-widgets");
        style.textContent = DW_CSS;
        document.head.appendChild(style);

        ensureBound();
        rescan();
        const unsubList = sessions.list.subscribe(() => {
          ensureBound();
          rescan();
        });
        const observer = new MutationObserver(() => {
          ensureBound();
          rescan();
        });
        observer.observe(document.body, { childList: true, subtree: true });

        return () => {
          style.remove();
          unsubList();
          if (unsubAny !== null) {
            try { unsubAny(); } catch { /* ignore */ }
            unsubAny = null;
          }
          observer.disconnect();
        };
      });
    }

    return { apply, inject };
  },
});

/**
 * dsh-widgets, browser half.
 *
 * Two families of keyed `tool.call.toolview` cards:
 *   1. `json` — a collapsible, syntax-highlighted JSON tree over the tool's
 *      persisted presentationMeta descriptor (replay-stable, no re-parse).
 *   2. subagent / subagent_fork / workflow / ralph / goal / jobs / list_agents —
 *      readable cards over the tool args + rendered result text, replacing the
 *      stock "Tool call" generic row that otherwise shows a raw JSON dump.
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

    const inject = ["slots"];

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

    function SubagentCard(props) {
      const { block } = props;
      const settled = done(block);
      const args = parseArgs(block);
      const description = typeof args?.description === "string" && args.description.trim() !== "" ? args.description.trim() : null;
      const background = args?.run_in_background === true;
      if (!settled) {
        return CardFrame({ title: "Субагент", badge: "Выполняется", badgeCls: "dw-badge-running", label: description, chips: background ? ["фон"] : null });
      }
      const text = resultText(block);
      if (block.isError) {
        return CardFrame({ title: "Субагент", badge: "Ошибка", badgeCls: "dw-badge-error", label: description, children: text ? h(LongText, { text }) : null });
      }
      if (text !== null && text.startsWith("started background subagent task ")) {
        const jobId = text.slice("started background subagent task ".length).trim();
        return CardFrame({ title: "Субагент", badge: "Фоновая задача", badgeCls: "dw-badge-muted", label: description, chips: jobId ? [jobId] : null });
      }
      if (text !== null && text.startsWith("started subagent ")) {
        const id = text.slice("started subagent ".length).trim();
        return CardFrame({ title: "Субагент", badge: "Запущен", badgeCls: "dw-badge-done", label: description, chips: id ? [id] : null });
      }
      return CardFrame({ title: "Субагент", badge: "Готово", badgeCls: "dw-badge-done", label: description, children: text ? h(LongText, { text }) : null });
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

      ctx.effect(() => {
        const style = document.createElement("style");
        style.setAttribute("data-plugin", "dsh-widgets");
        style.textContent = DW_CSS;
        document.head.appendChild(style);
        return () => style.remove();
      });
    }

    return { apply, inject };
  },
});

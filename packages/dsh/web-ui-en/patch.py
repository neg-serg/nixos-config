#!/usr/bin/env python3
"""dsh web UI: replace hardcoded Chinese UI copy with English.

The dsh 0.1.0-rc.6 web frontend hardcodes a handful of Chinese UI strings
directly in the compiled bundle (search/glob result banners, terminal-card
labels, truncation notices). The locale system (preference en + complete en
dictionaries in the runtime client modules) already covers the rest, so this
patch only touches the bundle and the static index.html lang attribute.

Run:  python3 patch.py <path-to-@deepseek-ai-subtree>
"""

import pathlib
import re
import sys

# Ordered replacement table. Longer / more specific keys must come first
# (the script sorts by length descending). Keys are the exact byte sequences
# found in the compiled bundle; values are the English copy they render.
REPL = [
    # template pieces (contain template syntax / punctuation)
    (
        " / 共 ",
        " / ",
    ),  # search banner: "显示 250 / 共 1072" -> "Showing 250 / 1072"
    (
        "，共 ",
        ", ",
    ),  # truncation: "… 已截断，共 N 字符" -> "… truncated, N chars"
    # multi-word phrases
    ("来源列表已截断", "Source list truncated"),
    ("内容已截断", "Content truncated"),
    ("连接已断开", "Connection lost"),
    ("未找到结果", "No results found"),
    ("复制成功", "Copied"),
    ("展开其余", "Show remaining"),
    ("正在重连", "Reconnecting"),
    ("收起输出", "Collapse output"),
    ("收起内容", "Collapse content"),
    ("收起差异", "Collapse diff"),
    ("收起结果", "Collapse results"),
    ("退出码", "Exit code"),
    ("行输出", "lines of output"),
    ("行差异", "diff lines"),
    ("行结果", "result lines"),
    ("运行中", "Running"),
    ("已完成", "Done"),
    ("无输出", "No output"),
    ("无结果", "No results"),
    ("处匹配", "matches"),
    ("个文件", "files"),
    ("个路径", "paths"),
    ("已截断", "truncated"),
    ("显示", "Showing"),
    ("其余", "remaining"),
    ("复制", "Copy"),
    ("收起", "Collapse"),
    ("信号", "Signal"),
    ("失败", "Failed"),
    ("字符", "chars"),
    ("行", "lines"),
]

REPL.sort(key=lambda kv: len(kv[0]), reverse=True)

# Conversation client bundle (dsh-client-ui-conversation/lib/client.js):
# 1) drop the "{turns} turns · {steps} steps" metric from the turn status
#    (user doesn't understand it), and
# 2) shorten the token displays: drop the "tok" unit word while KEEPING the
#    numbers ("{throughput} tok/s" -> "{throughput}/s", "{tps} tok/s" ->
#    "{tps}/s"), and render the token counts as compact arrow icons +
#    IN/OUT labels ("Input {input} tok · Output {output} tok" ->
#    "IN {input} / OUT {output}").
# The joins that build the status line filter empty segments so the removed
# metric leaves no stray " | " separators behind.
CONV_REPL = [
    # turns/steps metric -> remove entirely (en + zh dictionaries)
    ('"{turns} turns · {steps} steps"', '""'),  # en stats.counts
    ('"{turns} 轮 · {steps} 步"', '""'),  # zh stats.counts
    # tok words -> drop the unit, keep the numbers
    (
        '"{throughput} tok/s"',
        '"{throughput}/s"',
    ),  # stats.tokensPerSecond (en + zh)
    ('"{tps} tok/s"', '"{tps}/s"'),  # message.tokensPerSecond (en + zh)
    (
        '"Input {input} tok · Output {output} tok"',
        '"IN {input} / OUT {output}"',
    ),  # en stats.tokens
    (
        '"输入 {input} tok · 输出 {output} tok"',
        '"输入 {input} / 输出 {output}"',
    ),  # zh stats.tokens
    # joins: drop the now-empty segments so no stray " | " separators remain
    ('groups.join(" | ")', 'groups.filter(Boolean).join(" | ")'),
    ('speeds.join(" · ")', 'speeds.filter(Boolean).join(" · ")'),
    # render: the emptied turns/steps group still occupies a slot and gets its
    # own separator span (and the next group its own) — that renders stray
    # "|" glyphs and doubled separators. Filter empty groups before the map.
    ("groups.map((group, i) =>", "groups.filter(Boolean).map((group, i) =>"),
]

CJK = re.compile(r"[\u4e00-\u9fff]")

# dsh-client-ui-primitives/lib/index.js: the shared UI kit hardcodes Chinese
# default labels that render as text and tooltips (terminal-card pills
# "运行中"/"已完成"/"无输出", copy buttons "复制"/"复制成功", collapse/expand
# toggles, connection banner "连接已断开，正在重连…", search/glob result
# banners "显示 N / 共 M", truncation notices, JSON view copy tooltips) when
# callers don't pass their own locale-aware props. Rewrite them to English.
PRIM_REPL = [
    # DEFAULT_LABELS terminal-card pills
    (
        "signal: (signal) => `信号 ${signal}`",
        "signal: (signal) => `Signal ${signal}`",
    ),
    (
        "exitCode: (exitCode) => `退出码 ${exitCode}`",
        "exitCode: (exitCode) => `Exit code ${exitCode}`",
    ),
    ('running: "运行中"', 'running: "Running"'),
    ('failed: "失败"', 'failed: "Failed"'),
    ('done: "已完成"', 'done: "Done"'),
    ('copy: "复制"', 'copy: "Copy"'),
    ('copied: "复制成功"', 'copied: "Copied"'),
    ('noOutput: "无输出"', 'noOutput: "No output"'),
    ('collapseAria: "收起输出"', 'collapseAria: "Collapse output"'),
    ('collapse: "收起"', 'collapse: "Collapse"'),
    (
        "expandAria: (hidden) => `展开其余 ${hidden} 行输出`",
        "expandAria: (hidden) => `Expand ${hidden} more output lines`",
    ),
    (
        "expand: (hidden) => `… 其余 ${hidden} 行`",
        "expand: (hidden) => `… ${hidden} more lines`",
    ),
    # component default props (tooltips)
    ('copyLabel = "复制"', 'copyLabel = "Copy"'),
    ('copiedLabel = "复制成功"', 'copiedLabel = "Copied"'),
    (
        'label = "连接已断开，正在重连…"',
        'label = "Connection lost, reconnecting…"',
    ),
    # terminal output banner
    (
        "children: `显示 ${lines.length} / ${totalLines} 行`",
        "children: `Showing ${lines.length} / ${totalLines} lines`",
    ),
    (
        'children: copied ? "复制成功" : "复制"',
        'children: copied ? "Copied" : "Copy"',
    ),
    (
        '"aria-label": expanded ? "收起内容" : `展开其余 ${hidden} 行`',
        '"aria-label": expanded ? "Collapse content" : `Expand ${hidden} more lines`',
    ),
    (
        'children: expanded ? "收起" : `… 其余 ${hidden} 行`',
        'children: expanded ? "Collapse" : `… ${hidden} more lines`',
    ),
    (
        '"aria-label": expanded ? "收起差异" : `展开其余 ${hidden} 行差异`',
        '"aria-label": expanded ? "Collapse diff" : `Expand ${hidden} more diff lines`',
    ),
    (
        "const count = truncated ? `显示 ${shown} / 共 ${total}` : `${shown}`",
        "const count = truncated ? `Showing ${shown} / ${total}` : `${shown}`",
    ),
    (
        'return props.kind === "paths" ? `${count} 个路径` : `${count} 处匹配 · ${props.files.length} 个文件`',
        'return props.kind === "paths" ? `${count} paths` : `${count} matches · ${props.files.length} files`',
    ),
    ('children: "无结果"', 'children: "No results"'),
    (
        '"aria-label": expanded ? "收起结果" : `展开其余 ${hidden} 行结果`',
        '"aria-label": expanded ? "Collapse results" : `Expand ${hidden} more result lines`',
    ),
    ('children: "未找到结果"', 'children: "No results found"'),
    ('children: "来源列表已截断"', 'children: "Source list truncated"'),
    ('children: "内容已截断"', 'children: "Content truncated"'),
    (
        "return `… 已截断，共 ${total} 字符`",
        "return `… truncated, ${total} chars`",
    ),
]

# dsh-client-locale/lib/client.js: the language picker shows the zh locale
# under its native name "中文". The GUI runs English; show the English name.
LOCALE_REPL = [
    ('label: "中文"', 'label: "Chinese"'),
]

# dsh-client-connection/lib/client.js: the fixture model catalog served when
# no real model groups are configured (fixtureModelGroups) labels the
# DeepSeek models in Chinese.
CONN_REPL = [
    ('description: "快速响应"', 'description: "Fast responses"'),
    ('description: "复杂任务"', 'description: "Complex tasks"'),
]


def patch_bytes(
    data: bytes, table: list[tuple[str, str]]
) -> tuple[bytes, list[str]]:
    """Replace all table keys; report keys that were not found."""
    text = data.decode("utf-8")
    missing = []
    for old, new in table:
        if old in text:
            text = text.replace(old, new)
        else:
            missing.append(old)
    return text.encode("utf-8"), missing


def patch_conversation(root: pathlib.Path) -> int:
    """Drop turns/steps metric and shorten tok displays in the conversation bundle."""
    conv = root / "dsh-client-ui-conversation" / "lib" / "client.js"
    if not conv.exists():
        print(f"skip (absent): {conv.relative_to(root)}")
        return 0
    data = conv.read_bytes()
    new_data, missing = patch_bytes(data, CONV_REPL)
    if new_data != data:
        conv.write_bytes(new_data)
        print(f"patched: {conv.relative_to(root)}")
        if missing:
            print(
                f"note: {len(missing)} conversation keys absent: {sorted(missing)}"
            )
        return 1
    print(f"note: conversation bundle unchanged (keys absent: {missing})")
    return 0


# Client-side slash commands injected into the commands plugin bundle
# (dsh-client-ui-commands/lib/client.js). The host already exposes the
# session.fork / session.create RPCs and the client sessions service has
# fork()/open() — these contributions surface them as /fork and /new.
COMMANDS_ANCHOR = "this.directory.resetConnected();\n\t\t\t\t});"
COMMANDS_INSERT = (
    "\n"
    "\t\t\t\tthis.register({\n"
    '\t\t\t\t\tname: "fork",\n'
    '\t\t\t\t\tdescription: "Fork the current session into a new one",\n'
    "\t\t\t\t\tavailable: () => true,\n"
    "\t\t\t\t\tui: {\n"
    "\t\t\t\t\t\toptions: async (session) => [ {\n"
    '\t\t\t\t\t\t\tid: "fork",\n'
    '\t\t\t\t\t\t\tlabel: "Fork session",\n'
    '\t\t\t\t\t\t\tdetail: "New session carrying this conversation history"\n'
    "\t\t\t\t\t\t} ],\n"
    "\t\t\t\t\t\tonSelect: async (option, session) => {\n"
    "\t\t\t\t\t\t\tconst result = await this.sessions.fork({ sessionId: session.sessionId });\n"
    "\t\t\t\t\t\t\tif (result.ok) this.sessions.open(result.value.sessionId);\n"
    "\t\t\t\t\t\t}\n"
    "\t\t\t\t\t}\n"
    "\t\t\t\t});\n"
    "\t\t\t\tthis.register({\n"
    '\t\t\t\t\tname: "new",\n'
    '\t\t\t\t\tdescription: "Start a new blank session",\n'
    "\t\t\t\t\tavailable: () => true,\n"
    "\t\t\t\t\tui: {\n"
    "\t\t\t\t\t\toptions: async (session) => [ {\n"
    '\t\t\t\t\t\t\tid: "new",\n'
    '\t\t\t\t\t\t\tlabel: "New session",\n'
    '\t\t\t\t\t\t\tdetail: "Open a fresh blank conversation"\n'
    "\t\t\t\t\t\t} ],\n"
    "\t\t\t\t\t\tonSelect: async (option, session) => {\n"
    "\t\t\t\t\t\t\tconst result = await this.sessions.create();\n"
    "\t\t\t\t\t\t\tif (result.ok) this.sessions.open(result.value.sessionId);\n"
    "\t\t\t\t\t\t}\n"
    "\t\t\t\t\t}\n"
    "\t\t\t\t});\n"
    "\t\t\t"
)


def patch_commands(root: pathlib.Path) -> int:
    """Add /fork and /new client-side slash commands to the commands bundle."""
    cmd = root / "dsh-client-ui-commands" / "lib" / "client.js"
    if not cmd.exists():
        print(f"skip (absent): {cmd.relative_to(root)}")
        return 0
    data = cmd.read_bytes()
    text = data.decode("utf-8")
    if COMMANDS_INSERT.strip() in text:
        print("note: commands bundle already patched")
        return 0
    if COMMANDS_ANCHOR not in text:
        print(
            "WARNING: commands anchor not found — /fork and /new not injected",
            file=sys.stderr,
        )
        return 0
    text = text.replace(COMMANDS_ANCHOR, COMMANDS_ANCHOR + COMMANDS_INSERT, 1)
    cmd.write_bytes(text.encode("utf-8"))
    print(f"patched: {cmd.relative_to(root)} (/fork, /new)")
    return 1


def patch_simple(root: pathlib.Path, rel: str, table, name: str) -> int:
    """Apply a literal replacement table to one bundle; report absent keys."""
    p = root / rel
    if not p.exists():
        print(f"skip (absent): {rel}")
        return 0
    data = p.read_bytes()
    new_data, missing = patch_bytes(data, table)
    if new_data != data:
        p.write_bytes(new_data)
        print(f"patched: {rel} ({name})")
        if missing:
            print(
                f"note: {len(missing)} {name} keys absent: {sorted(missing)}"
            )
        return 1
    print(f"note: {rel} unchanged ({name}; keys absent: {missing})")
    return 0


def main() -> int:
    root = pathlib.Path(sys.argv[1])
    if not root.is_dir():
        print(f"error: {root} is not a directory", file=sys.stderr)
        return 1

    bundle = (
        root / "dsh-web-frontend" / "dist" / "assets" / "index-Dqw48FrP.js"
    )
    html = root / "dsh-web-frontend" / "dist" / "index.html"

    patched = 0
    if bundle.exists():
        data = bundle.read_bytes()
        new_data, missing = patch_bytes(data, REPL)
        if new_data != data:
            bundle.write_bytes(new_data)
            patched += 1
            print(f"patched: {bundle.relative_to(root)}")
        if missing:
            print(
                f"note: {len(missing)} dictionary keys absent from the bundle: {sorted(missing)}"
            )
    else:
        print(f"skip (absent): {bundle.relative_to(root)}")

    patched += patch_conversation(root)
    patched += patch_commands(root)
    patched += patch_simple(
        root, "dsh-client-ui-primitives/lib/index.js", PRIM_REPL, "primitives"
    )
    patched += patch_simple(
        root, "dsh-client-locale/lib/client.js", LOCALE_REPL, "locale"
    )
    patched += patch_simple(
        root,
        "dsh-client-connection/lib/client.js",
        CONN_REPL,
        "connection fixtures",
    )

    # index.html: declare the page language explicitly as English
    if html.exists():
        s = html.read_text(encoding="utf-8")
        s2 = s.replace('lang="zh-CN"', 'lang="en"')
        if s2 != s:
            html.write_text(s2, encoding="utf-8")
            patched += 1
            print(f"patched: {html.relative_to(root)} lang -> en")

    # verify no CJK left in the bundle
    if bundle.exists():
        left = sorted(set(CJK.findall(bundle.read_text(encoding="utf-8"))))
        if left:
            print(
                f"WARNING: bundle still contains CJK: {left}", file=sys.stderr
            )

    print(f"done: patched {patched} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())

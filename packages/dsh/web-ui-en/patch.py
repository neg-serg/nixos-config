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
#    "IN ↓ {input} / OUT ↑ {output}").
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
        '"IN ↓ {input} / OUT ↑ {output}"',
    ),  # en stats.tokens
    (
        '"输入 {input} tok · 输出 {output} tok"',
        '"输入 ↓ {input} / 输出 ↑ {output}"',
    ),  # zh stats.tokens
    # joins: drop the now-empty segments so no stray " | " separators remain
    ('groups.join(" | ")', 'groups.filter(Boolean).join(" | ")'),
    ('speeds.join(" · ")', 'speeds.filter(Boolean).join(" · ")'),
]

CJK = re.compile(r"[\u4e00-\u9fff]")


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

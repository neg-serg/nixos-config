"""Shared helpers for the F-Sy-H theme tools (compress-theme, alt-compactor)."""


def strip_quotes(s: str) -> str:
    """Remove one pair of matching single/double quotes around the string."""
    s = s.strip()
    if (s.startswith('"') and s.endswith('"')) or (
        s.startswith("'") and s.endswith("'")
    ):
        return s[1:-1]
    return s


def cut_comment(s: str) -> str:
    """Strip a trailing '#' comment, ignoring '#' inside quotes."""
    out = []
    in_q = False
    q = ""
    i = 0
    while i < len(s):
        ch = s[i]
        if ch in ("'", '"'):
            if not in_q:
                in_q = True
                q = ch
            elif q == ch:
                in_q = False
                q = ""
            out.append(ch)
            i += 1
            continue
        if ch == "#" and not in_q:
            break
        out.append(ch)
        i += 1
    return "".join(out).strip()

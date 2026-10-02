import re
import sys

# Keep a session that already had a prompt from being hidden again.
#
# Usage: dsh-tui-session-visibility-patch.py <path/to/list.js>
#
# The bug (dsh-TUI 0.10.x, lib/types/dsh-adapter/sessions/list.js): the index
# records `hasPrompt` from the log's head window, and the append-only
# carry-forward copies that flag from the *previous* revision verbatim:
#
#     hasPrompt = previous.hasPrompt;
#
# A session is first indexed while its log is still a few hundred bytes (a
# header, no human prompt yet), so it is stored with hasPrompt = false; when
# the log later grows past the window the fresh digest says true, but the
# carry-forward overwrites it with the stale false. The stored revision then
# matches the file, so the cache-hit path reuses the entry verbatim forever and
# the session never appears in the conversations list again — the user's
# "session disappeared".
#
# Session logs are append-only, so the flag is monotonic: once a prompt has been
# observed it can never become absent again. The fix is therefore to OR the
# carried flag with the freshly derived one instead of replacing it.
#
# Idempotent: re-running on an already patched file is a no-op, and a file with
# neither spelling (a future dsh-TUI that fixed this upstream, or moved the
# code) is reported instead of being silently "fixed".

PATH = sys.argv[1] if len(sys.argv) > 1 else ""
if not PATH:
    print(
        "dsh-tui-session-visibility-patch: no target path given",
        file=sys.stderr,
    )
    sys.exit(2)

with open(PATH, encoding="utf-8") as f:
    src = f.read()

BROKEN = re.compile(r"(?m)^([ \t]*)hasPrompt = previous\.hasPrompt;$")
FIXED = re.compile(
    r"(?m)^([ \t]*)hasPrompt = hasPrompt \|\| previous\.hasPrompt;$"
)

if FIXED.search(src):
    print(f"dsh-tui-session-visibility-patch: {PATH}: already patched")
    sys.exit(0)

patched, count = BROKEN.subn(
    r"\1hasPrompt = hasPrompt || previous.hasPrompt;", src
)
if count == 0:
    print(
        f"dsh-tui-session-visibility-patch: {PATH}: no carry-forward line found — "
        "the TUI source moved; re-check the hasPrompt propagation by hand",
        file=sys.stderr,
    )
    sys.exit(1)

with open(PATH, "w", encoding="utf-8") as f:
    f.write(patched)
print(
    f"dsh-tui-session-visibility-patch: {PATH}: patched {count} carry-forward site(s)"
)

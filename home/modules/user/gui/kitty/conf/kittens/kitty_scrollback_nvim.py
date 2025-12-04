import os
import sys
import importlib.util

# Resolve the real kitty-scrollback-nvim kitten implementation.
# Prefer a Nix-installed path provided via env, then fall back to a
# Lazy.nvim install in the user home.

NIX_KSB = os.environ.get("KITTY_KSB_NIX_PATH", "")
LAZY_KSB = os.path.expanduser(
    "~/.local/share/nvim/lazy/kitty-scrollback.nvim/python/kitty_scrollback_nvim.py"
)


def _resolve_path():
    for p in (NIX_KSB, LAZY_KSB):
        if p and os.path.exists(p):
            return p
    return None


_path = _resolve_path()
if not _path:
    print(
        "kitty-scrollback-nvim: kitten not found (set KITTY_KSB_NIX_PATH or install via Lazy)",
        file=sys.stderr,
    )
    sys.exit(1)

spec = importlib.util.spec_from_file_location("kitty_scrollback_nvim_impl", _path)
if spec is None or spec.loader is None:
    print(f"failed to load spec for {_path}", file=sys.stderr)
    sys.exit(1)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def main(args):
    return mod.main(args)


def handle_result(args, data, target_window_id, boss):
    return mod.handle_result(args, data, target_window_id, boss)


def is_main_thread():
    f = getattr(mod, "is_main_thread", None)
    return f() if callable(f) else False

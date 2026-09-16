"""Count-asserted exact-string patcher for the dsh build scripts (patch-*.py).

A replacement that does not match the expected number of times (a dsh upgrade,
formatting drift) aborts the build instead of shipping a half-patched tree.
post-install.sh puts this directory on PYTHONPATH; a manual run needs the same:
PYTHONPATH=packages/dsh/lib python3 packages/dsh/patch-widgets.py <dir>
"""


def normalizer(doc, body, anchor):
    """A migration normalizer: doc comment + body, chained on `anchor`."""
    return f"{doc}\n{body}\n\n{anchor}"


def patch_file(root, rel, replacements, prog, announce=False):
    """Apply `replacements` to `<root>/<rel>` and write it back.

    A replacement is `(old, new, expected)`. A string in the expected slot
    means "exactly once" and names the anchor in the error message instead of
    quoting it (the patch-session-format wording). `announce` logs each patch.
    """
    path = f"{root}/{rel}"
    with open(path, encoding="utf-8") as f:
        src = f.read()
    for old, new, spec in replacements:
        label = spec if isinstance(spec, str) else ""
        expected = 1 if label else spec
        n = src.count(old)
        if n != expected:
            if label:
                raise SystemExit(
                    f"{prog}: {label} found {n} time(s) in {rel}, "
                    f"expected {expected}"
                )
            raise SystemExit(
                f"{prog}: {rel}: pattern found {n} time(s), expected "
                f"{expected}: {old[:90]!r}"
            )
        src = src.replace(old, new)
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    if announce:
        print(f"{prog}: patched {rel}")


def patch_path(path, rewrites, prog):
    """Apply a `{old: new}` mapping to `path`, each key matching exactly once."""
    text = path.read_text(encoding="utf-8")
    for old, new in rewrites.items():
        count = text.count(old)
        if count != 1:
            raise SystemExit(
                f"{prog}: expected exactly 1 occurrence of {old!r} in "
                f"{path}, found {count}"
            )
        text = text.replace(old, new)
    path.write_text(text, encoding="utf-8")

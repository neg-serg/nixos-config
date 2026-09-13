import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
if not path.exists():
    print(f"dsh-models: {path} absent — nothing to do")
    sys.exit(0)

blocks = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
src = path.read_text(encoding="utf-8")
lines = src.split("\n")


def drop(start: int, stop: int) -> None:
    del lines[start:stop]


def remove(key: str, begin: str, end: str) -> None:
    """Drop the managed block, else a hand-written section for the same key."""
    bi = next(
        (i for i, line in enumerate(lines) if line.startswith(begin)), None
    )
    if bi is not None:
        ei = next(
            (i for i in range(bi, len(lines)) if lines[i].startswith(end)),
            None,
        )
        if ei is None:
            raise SystemExit(
                f"dsh-models: {path}: unterminated managed block {begin}"
            )
        drop(bi, ei + 1)
        return
    # A hand-written section: replace it up to the next top-level key so two
    # `key:` entries can never coexist in one YAML document.
    own = next(
        (i for i, line in enumerate(lines) if line.startswith(key + ":")), None
    )
    if own is None:
        return
    stop = len(lines)
    for i in range(own + 1, len(lines)):
        line = lines[i]
        if line.strip() and not line[0].isspace() and not line.startswith("#"):
            stop = i
            break
    drop(own, stop)


for block in blocks:
    remove(
        block["key"],
        f"# {block['marker']}: begin",
        f"# {block['marker']}: end",
    )

# Drop the blank separators left in front of the insertion point, then
# append every block at EOF so a user edit above them is never disturbed.
while len(lines) > 1 and lines[-1] == "" and lines[-2] == "":
    lines.pop()
if lines and lines[-1] != "":
    lines.append("")
for block in blocks:
    lines.extend(block["body"].rstrip("\n").split("\n"))
    lines.append("")
while lines and lines[-1] == "":
    lines.pop()
out = "\n".join(lines) + "\n"

if out == src:
    print(f"dsh-models: {path}: managed blocks already current")
    sys.exit(0)
path.write_text(out, encoding="utf-8")
print(f"dsh-models: {path}: wrote {len(blocks)} managed block(s)")

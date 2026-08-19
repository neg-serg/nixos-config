import sys, json, io, contextlib, traceback

ns = {}

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        req = json.loads(line)
    except Exception:
        continue
    rid = req.get("id")
    if req.get("reset"):
        ns.clear()
        sys.stdout.write(
            json.dumps(
                {
                    "id": rid,
                    "ok": True,
                    "stdout": "",
                    "stderr": "",
                    "error": None,
                }
            )
            + chr(10)
        )
        sys.stdout.flush()
        continue
    buf = io.StringIO()
    err = None
    try:
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
            exec(compile(req.get("code", ""), "<eval>", "exec"), ns, ns)
    except Exception:
        err = traceback.format_exc()
    sys.stdout.write(
        json.dumps(
            {
                "id": rid,
                "ok": err is None,
                "stdout": buf.getvalue(),
                "stderr": "",
                "error": err,
            }
        )
        + chr(10)
    )
    sys.stdout.flush()

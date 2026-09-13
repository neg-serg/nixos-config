import json
import pathlib
import re
import subprocess
import sys

STATE_FILE = pathlib.Path("@stateFile@")
STATE_DIR = pathlib.Path("@stateDir@")
ZPOOL = "/run/current-system/sw/bin/zpool"
SENDER = "@sender@/bin/telegram-send"

# vdev states that indicate a fault even when the error counters are 0.
FAULT_STATES = {"DEGRADED", "FAULTED", "OFFLINE", "UNAVAIL", "REMOVED"}
_MONTHS = {
    m: i + 1
    for i, m in enumerate(
        [
            "Jan",
            "Feb",
            "Mar",
            "Apr",
            "May",
            "Jun",
            "Jul",
            "Aug",
            "Sep",
            "Oct",
            "Nov",
            "Dec",
        ]
    )
}


def run_cmd(argv):
    proc = subprocess.run(
        argv,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return proc.stdout


def list_pools():
    out = run_cmd([ZPOOL, "list", "-H", "-o", "name"])
    return [line.strip() for line in out.splitlines() if line.strip()]


def scrub_key(date):
    # zpool scan dates look like "Sat Sep  5 01:35:33 2026" (%c); normalise
    # runs of whitespace so a bare int-comparable tuple can order them.
    norm = re.sub(r"\s+", " ", date.strip())
    m = re.match(r"^\w+\s+(\w+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\d{4})$", norm)
    if not m or m.group(1) not in _MONTHS:
        return None
    mon, day, hh, mm, ss, year = m.groups()
    return (int(year), _MONTHS[mon], int(day), int(hh), int(mm), int(ss))


def parse_status(text):
    # Returns (overall_state, problems[], last_scrub{date,errors}|None).
    # problems: human-readable lines for any vdev with non-zero counters or
    # a faulted state; derived purely from `zpool status <pool>`.
    state = None
    problems = []
    scan = None
    in_config = False
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        m2 = re.match(r"^state:\s+(\S+)$", line)
        if m2:
            state = m2.group(1)
        if line.startswith("scan:"):
            scan = line
        if line.startswith("config:"):
            in_config = True
            continue
        if (
            line.startswith("errors:")
            or line.startswith("actions:")
            or line.startswith("status:")
            or line.startswith("scrub:")
        ):
            in_config = False
        if not in_config:
            continue
        toks = line.split()
        if not toks or toks[0] == "NAME":
            continue  # table header
        # A real vdev row always ends with three numeric error counters.
        if len(toks) >= 5 and all(t.isdigit() for t in toks[-3:]):
            name = toks[0]
            vstate = toks[1]
            read = int(toks[-3])
            write = int(toks[-2])
            cksum = int(toks[-1])
            bits = []
            if read:
                bits.append("read={0}".format(read))
            if write:
                bits.append("write={0}".format(write))
            if cksum:
                bits.append("cksum={0}".format(cksum))
            if bits:
                problems.append("{0}: {1}".format(name, " ".join(bits)))
            elif vstate in FAULT_STATES:
                problems.append("{0}: state {1}".format(name, vstate))
    scrub = None
    if scan:
        sm = re.search(
            r"\bscrub\b.*?\bwith\s+(\d+)\s+errors\s+on\s+(.+?)\s*$", scan
        )
        if sm:
            scrub = {"errors": int(sm.group(1)), "date": sm.group(2).strip()}
    return state, problems, scrub


def load_state():
    try:
        return json.loads(STATE_FILE.read_text())
    except (OSError, ValueError):
        return {"pools": {}}


def send_telegram(text):
    # The shared sender (hosts/odin/telegram.nix) owns the socks-proxy retry.
    proc = subprocess.run([SENDER, text], check=False)
    if proc.returncode != 0:
        print(
            "zfs-watch: telegram delivery failed for: {0}".format(text),
            file=sys.stderr,
        )
        return False
    return True


def main():
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    data = load_state()
    pools = data.get("pools", {})
    new_pools = {}
    messages = []
    had_pending = False
    for pool in list_pools():
        try:
            status = run_cmd([ZPOOL, "status", pool])
        except subprocess.CalledProcessError as exc:
            print(
                "zfs-watch: zpool status {0} failed: {1}".format(pool, exc),
                file=sys.stderr,
            )
            continue
        try:
            state, problems, scrub = parse_status(status)
        except Exception as exc:  # defensive: never crash on parse trouble
            print(
                "zfs-watch: parse error for {0}: {1}".format(pool, exc),
                file=sys.stderr,
            )
            continue
        cur_ok = (not problems) and (state == "ONLINE" or state is None)
        entry = {
            "ok": cur_ok,
            "problems": problems,
            "state": state,
            "scrub": scrub,
        }
        prev = pools.get(pool)
        if prev is not None:
            # Problem-appeared / recovered transitions (skip on first run =
            # baseline so a fresh install does not dump the whole history).
            prev_ok = bool(prev.get("ok", True))
            if prev_ok and not cur_ok:
                body = (
                    "; ".join(problems)
                    if problems
                    else "state {0}".format(state)
                )
                messages.append("⚠️ ZFS {0}: {1}".format(pool, body))
                had_pending = True
            elif (not prev_ok) and cur_ok:
                messages.append("✅ ZFS {0}: recovered".format(pool))
                had_pending = True
            # New (newer) scrub completion for this pool.
            prev_scrub = prev.get("scrub")
            if scrub and prev_scrub:
                kc = scrub_key(scrub["date"])
                kp = scrub_key(prev_scrub.get("date", ""))
                if scrub["date"] != prev_scrub.get("date") and (
                    kc is None or kp is None or kc > kp
                ):
                    messages.append(
                        "🧹 ZFS scrub {0} закончен: {1} ошибок ({2})".format(
                            pool, scrub["errors"], scrub["date"]
                        )
                    )
                    had_pending = True
        new_pools[pool] = entry

    # Deliver everything. If any transition/scrub message cannot be
    # delivered, keep the previous state so the same transition is retried
    # next run (no loss, still no spam) instead of being swallowed.
    delivered = all(send_telegram(m) for m in messages) if messages else True
    if not had_pending or delivered:
        data["pools"] = new_pools
        STATE_FILE.write_text(json.dumps(data, ensure_ascii=False, indent=2))


try:
    main()
except Exception as exc:  # never crash the unit on unexpected failures
    print("zfs-watch: fatal: {0}".format(exc), file=sys.stderr)
    sys.exit(1)
sys.exit(0)

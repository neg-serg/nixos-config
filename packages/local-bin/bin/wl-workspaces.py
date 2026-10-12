#!/usr/bin/env python3
"""Per-workspace wallpapers for Hyprland, painted by the wl daemon.

`wl` paints one image per *output*; this helper gives every workspace its own
image by swapping `wl img` whenever an output's active workspace changes.

How it stays out of the way of the rest of the wallpaper stack:

  * swaps are painted with `--no-notify`, so ~/.cache/quickshell-wallpaper-path
    keeps naming the wallpaper the *user* picked — the greeter does not follow
    workspace hops;
  * before every swap a marker (~/.local/state/wl/workspaces-swap) is written;
    wl-state-sync skips state changes that match it, so the greeter chain does
    not run on every workspace switch either;
  * the assignment is a pure function of (seed, workspace) — the watcher and
    any one-shot invocation agree without sharing memory, and a workspace keeps
    its image for the whole session (a new day starts with a new seed).

Commands:

  watch     follow Hyprland's event socket and repaint on workspace changes
  apply     one-shot paint for the current (or a given) workspace/output
  shuffle   new seed, repaint the current workspaces (the wallpaper keybind)
  show      print the current mapping without touching anything
  selftest  exercise the mapping/apply/skip logic against fakes (no session)

Environment overrides (tests use them; the service leaves them alone):

  WL_WORKSPACES_WL       path to the wl client (default /run/current-system/sw/bin/wl)
  WL_WORKSPACES_HYPRCTL  path to hyprctl   (default /run/current-system/sw/bin/hyprctl)
  WL_WORKSPACES_SOCKET   Hyprland event socket (default $XDG_RUNTIME_DIR/hypr/<sig>/.socket2.sock)
  WL_WORKSPACES_CONFIG   workspaces.toml
  WL_WORKSPACES_STATE    seed/applied state (workspaces.json)
  WL_WORKSPACES_MARKER   swap marker read by wl-state-sync
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import random
import signal
import socket
import subprocess
import sys
import time
import tomllib
from pathlib import Path

IMAGE_EXTS = {
    ".jpg",
    ".jpeg",
    ".png",
    ".webp",
    ".gif",
    ".bmp",
    ".tif",
    ".tiff",
    ".pnm",
    ".tga",
    ".svg",
    ".avif",
}

DEFAULT_POOL = "~/pic/wl"
DEFAULT_TRANSITION = "wipe"
DEFAULT_DURATION = 0.35

# Events that can change which workspace an output shows. `focusedmon` carries
# the workspace with the output, `workspace` only the name — the monitor table
# is re-read after either, so both are equally useful.
WATCH_EVENTS = {
    "workspace",
    "focusedmon",
    "monitoradded",
    "monitorremoved",
    "activespecial",
}

# Special workspaces overlay a normal one; repainting under them makes no sense.
SPECIAL_PREFIX = "special"


_quiet = False


def log(msg: str) -> None:
    if not _quiet:
        print(f"wl-workspaces: {msg}", file=sys.stderr, flush=True)


def expand(path: str) -> Path:
    return Path(os.path.expanduser(path))


def _env_path(name: str, default: str) -> Path:
    raw = os.environ.get(name) or default
    return Path(os.path.expanduser(raw))


class Env:
    """Everything the helper touches outside its own logic."""

    def __init__(self) -> None:
        runtime = (
            os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
        )
        sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
        self.wl = _env_path(
            "WL_WORKSPACES_WL", "/run/current-system/sw/bin/wl"
        )
        self.hyprctl = _env_path(
            "WL_WORKSPACES_HYPRCTL", "/run/current-system/sw/bin/hyprctl"
        )
        default_sock = f"{runtime}/hypr/{sig}/.socket2.sock"
        self.socket = _env_path("WL_WORKSPACES_SOCKET", default_sock)
        self.config = _env_path(
            "WL_WORKSPACES_CONFIG", "~/.config/wl/workspaces.toml"
        )
        state_default = "~/.local/state/wl/workspaces.json"
        self.state = _env_path("WL_WORKSPACES_STATE", state_default)
        marker_default = "~/.local/state/wl/workspaces-swap"
        self.marker = _env_path("WL_WORKSPACES_MARKER", marker_default)
        self.pidfile = self.state.with_suffix(".pid")


class Config:
    def __init__(self, raw: dict) -> None:
        general = raw.get("general", {})
        self.pool = expand(str(general.get("pool", DEFAULT_POOL)))
        self.transition = str(general.get("transition", DEFAULT_TRANSITION))
        self.duration = float(general.get("duration", DEFAULT_DURATION))
        self.overrides = {
            str(k).strip().lower(): str(v)
            for k, v in (raw.get("workspaces", {}) or {}).items()
        }

    @classmethod
    def load(cls, path: Path) -> "Config":
        if not path.is_file():
            log(f"no config at {path}, using the pool default")
            return cls({})
        with path.open("rb") as fh:
            return cls(tomllib.load(fh))


def iter_images(directory: Path) -> list[Path]:
    if not directory.is_dir():
        return []
    found = [
        p
        for p in sorted(directory.rglob("*"))
        if p.is_file() and p.suffix.lower() in IMAGE_EXTS
    ]
    return found


def name_key(ws_name: str) -> str:
    """`𐌰:term` -> `term`; a plain name is returned as is."""
    return ws_name.rsplit(":", 1)[-1].strip().lower() if ws_name else ""


def override_for(cfg: Config, ws_id: int, ws_name: str) -> str | None:
    """Return the raw override value for a workspace, or None for the pool."""
    for key in (name_key(ws_name), str(ws_id)):
        if key and key in cfg.overrides:
            return cfg.overrides[key]
    return cfg.overrides.get("*")


class Assigner:
    """Workspace -> image mapping for one seed.

    Assignments are persisted (keyed by workspace, tagged with the rule that
    produced them), so the watcher, `shuffle` and a manual `apply` all agree on
    what a workspace shows — and a workspace keeps its image even across
    restarts. A new seed starts with a clean sheet.
    """

    def __init__(self, cfg: Config, seed: int, state: dict, save) -> None:
        self.cfg = cfg
        self.seed = seed
        self.state = state
        self.save = save
        self.pool = iter_images(cfg.pool)
        self._shuffled = list(self.pool)
        random.Random(seed).shuffle(self._shuffled)
        if state.get("assignments_seed") != seed:
            state["assignments_seed"] = seed
            state["assignments"] = {}
        self._entries: dict[str, dict] = state.setdefault("assignments", {})
        self._used: set[str] = {
            e["image"] for e in self._entries.values() if e.get("image")
        }

    def _hash(self, *parts: object) -> int:
        raw = ":".join([str(self.seed), *map(str, parts)])
        return int(hashlib.sha1(raw.encode()).hexdigest()[:12], 16)

    def _pick(self, images: list[Path], *key: object) -> Path | None:
        """Deterministic, collision-free pick from one image list."""
        if not images:
            return None
        start = self._hash(*key) % len(images)
        for offset in range(len(images)):
            cand = images[(start + offset) % len(images)]
            if str(cand) not in self._used and cand.is_file():
                return cand
        # Every candidate is taken (or gone): reuse one rather than paint
        # nothing, but stay deterministic about which.
        for offset in range(len(images)):
            cand = images[(start + offset) % len(images)]
            if cand.is_file():
                return cand
        return None

    def _compute(
        self, rule: str | None, ws_id: int, ws_name: str
    ) -> Path | None:
        if rule is not None:
            if rule.strip().lower() in {"keep", "off", "none", ""}:
                return None
            target = expand(rule)
            if target.is_dir():
                return self._pick(iter_images(target), ws_id, ws_name)
            if target.is_file():
                return target
            log(
                f"{ws_name or ws_id}: {target} is gone, falling back to the pool"
            )
        return self._pick(self._shuffled, ws_id, ws_name)

    def image_for(self, ws_id: int, ws_name: str) -> Path | None:
        """The image a workspace should show; None means `keep`."""
        key = str(ws_id) if ws_id else (name_key(ws_name) or "unknown")
        rule = override_for(self.cfg, ws_id, ws_name)
        rule_tag = "" if rule is None else rule
        entry = self._entries.get(key)
        if entry and entry.get("rule", "") == rule_tag:
            remembered = entry.get("image") or ""
            if not remembered:
                return None
            image = Path(remembered)
            if image.is_file():
                return image
            log(f"{ws_name or ws_id}: remembered {image} is gone, repicking")
            self._used.discard(remembered)
        image = self._compute(rule, ws_id, ws_name)
        if image is not None:
            self._used.add(str(image))
        self._entries[key] = {
            "rule": rule_tag,
            "image": "" if image is None else str(image),
        }
        self.save()
        return image


def load_state(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}


def save_state(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")


def default_seed() -> int:
    """Fresh seed per day keeps the set stable within a session."""
    return int(time.strftime("%Y%m%d"))


def ensure_seed(env: Env) -> tuple[int, dict]:
    state = load_state(env.state)
    if not isinstance(state.get("seed"), int):
        state["seed"] = default_seed()
        save_state(env.state, state)
    return state["seed"], state


def make_assigner(env: Env, cfg: Config) -> Assigner:
    """Load the seed + remembered assignments and hand back an Assigner."""
    seed, state = ensure_seed(env)

    def save() -> None:
        save_state(env.state, state)

    return Assigner(cfg, seed, state, save)


def monitors(env: Env) -> list[dict]:
    """[{name, workspace_id, workspace_name}] for every output."""
    try:
        out = subprocess.run(
            [str(env.hyprctl), "-j", "monitors"],
            capture_output=True,
            text=True,
            timeout=5,
            check=True,
        ).stdout
        data = json.loads(out)
    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        log(f"hyprctl monitors failed: {exc}")
        return []
    result = []
    for mon in data:
        ws = mon.get("activeWorkspace") or {}
        name = str(mon.get("name", ""))
        ws_name = str(ws.get("name", ""))
        if not name or ws_name.startswith(SPECIAL_PREFIX):
            continue
        result.append(
            {
                "name": name,
                "workspace_id": int(ws.get("id", 0) or 0),
                "workspace_name": ws_name,
            }
        )
    return result


def _run(cmd: list[str]) -> tuple[bool, str]:
    try:
        done = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
    except OSError as exc:
        return False, str(exc)
    if done.returncode == 0:
        return True, ""
    return False, (done.stderr or done.stdout or "").strip()


def paint(env: Env, image: Path, output: str, cfg: Config) -> bool:
    """Mark the swap (so wl-state-sync ignores it) and hand it to wl."""
    try:
        env.marker.parent.mkdir(parents=True, exist_ok=True)
        env.marker.write_text(f"{int(time.time())} {image}\n")
    except OSError as exc:
        log(f"cannot write swap marker {env.marker}: {exc}")
    base = [str(env.wl), "img", str(image), "--outputs", output, "--no-notify"]
    ok, err = _run(
        base
        + [
            "--transition-type",
            cfg.transition,
            "--transition-duration",
            str(cfg.duration),
        ]
    )
    if not ok:
        # A typo in `transition` (or a name this wl build dropped) must not cost
        # the wallpaper: say what wl answered and retry with its own default.
        log(
            f"wl img {output} with transition {cfg.transition!r} failed: {err}"
        )
        ok, err = _run(base)
    if not ok:
        log(f"wl img failed for {output}: {err}")
        return False
    log(f"{output}: {image}")
    return True


class Session:
    """Applies assignments to outputs and remembers what is already painted."""

    def __init__(self, env: Env, cfg: Config, assigner: Assigner) -> None:
        self.env = env
        self.cfg = cfg
        self.assigner = assigner
        self.applied: dict[str, Path] = {}

    def sync(self, only_output: str | None = None, force: bool = False) -> int:
        painted = 0
        for mon in monitors(self.env):
            output = mon["name"]
            if only_output and output != only_output:
                continue
            image = self.assigner.image_for(
                mon["workspace_id"], mon["workspace_name"]
            )
            if image is None:
                continue
            if not force and self.applied.get(output) == image:
                continue
            if paint(self.env, image, output, self.cfg):
                self.applied[output] = image
                painted += 1
        return painted

    def show(self) -> None:
        for mon in monitors(self.env):
            image = self.assigner.image_for(
                mon["workspace_id"], mon["workspace_name"]
            )
            target = "keep" if image is None else str(image)
            print(f"{mon['name']}\t{mon['workspace_name']}\t{target}")


def watch(env: Env, cfg: Config) -> int:
    def reseed() -> Assigner:
        assigner = make_assigner(env, cfg)
        log(
            f"seed {assigner.seed}, "
            f"{len(assigner.pool)} images in {cfg.pool}"
        )
        return assigner

    assigner = reseed()
    session = Session(env, cfg, assigner)
    pending = {"reseed": False}

    def on_usr1(_signum, _frame):
        pending["reseed"] = True

    signal.signal(signal.SIGUSR1, on_usr1)
    try:
        env.pidfile.parent.mkdir(parents=True, exist_ok=True)
        env.pidfile.write_text(f"{os.getpid()}\n")
    except OSError as exc:
        log(f"cannot write pidfile {env.pidfile}: {exc}")

    while True:
        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.connect(str(env.socket))
        except OSError as exc:
            log(f"{env.socket}: {exc}; retrying in 5 s")
            time.sleep(5)
            continue
        log(f"following {env.socket}")
        session.sync()
        buf = b""
        try:
            while True:
                if pending["reseed"]:
                    pending["reseed"] = False
                    assigner = reseed()
                    session = Session(env, cfg, assigner)
                    session.sync(force=True)
                chunk = sock.recv(4096)
                if not chunk:
                    break
                buf += chunk
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    event = line.decode(errors="replace").split(">>", 1)[0]
                    if event in WATCH_EVENTS:
                        session.sync()
                        if pending["reseed"]:
                            break
        finally:
            sock.close()
        log("event socket closed; reconnecting in 2 s")
        time.sleep(2)


def should_skip(env: Env, path: str) -> bool:
    """True when `path` is one of our own swaps (so callers can ignore it).

    wl-state-sync uses this: the daemon rewrites state.json on every paint, and
    without the marker the greeter chain would copy a new image on every
    workspace switch. A marker for the same image, younger than 10 s, is ours;
    anything else is the user changing the wallpaper.
    """
    try:
        raw = env.marker.read_text().strip()
        marked_at, marked_path = raw.split(" ", 1)
        age = time.time() - int(marked_at)
    except (OSError, ValueError):
        return False
    return marked_path == path and 0 <= age <= 10


def cmd_shuffle(env: Env, cfg: Config) -> int:
    state = load_state(env.state)
    state["seed"] = random.randrange(1, 2**31)
    save_state(env.state, state)
    log(f"new seed {state['seed']}")
    Session(env, cfg, make_assigner(env, cfg)).sync(force=True)
    try:
        pid = int(env.pidfile.read_text().strip())
        os.kill(pid, signal.SIGUSR1)
    except (OSError, ValueError):
        pass  # no watcher running: the one-shot paint above is enough
    return 0


def cmd_apply(
    env: Env,
    cfg: Config,
    workspace: int | None,
    output: str | None,
    force: bool,
) -> int:
    session = Session(env, cfg, make_assigner(env, cfg))
    assigner = session.assigner
    if workspace is None and output is None:
        session.sync(force=force)
        return 0
    if output is None:
        for mon in monitors(env):
            session.sync(only_output=mon["name"], force=force)
        return 0
    image = assigner.image_for(workspace or 0, "")
    if image is None:
        log("keep: nothing to paint")
        return 0
    return 0 if paint(env, image, output, cfg) else 1


# --- selftest -----------------------------------------------------------------


def selftest() -> int:
    """Drive the mapping and the paint path against fakes; no session needed."""
    import shutil
    import tempfile

    global _quiet

    failures: list[str] = []
    verbose = os.environ.get("WL_WORKSPACES_VERBOSE") == "1"
    _quiet = not verbose

    def check(name: str, ok: bool) -> None:
        if verbose or not ok:
            print(f"  {'ok  ' if ok else 'FAIL'} {name}")
        if not ok:
            failures.append(name)

    tmp = Path(tempfile.mkdtemp(prefix="wl-workspaces-selftest-"))
    try:
        pool = tmp / "pool"
        pool.mkdir()
        for i in range(6):
            (pool / f"img{i}.jpg").write_bytes(b"x")
        extra = tmp / "extra"
        extra.mkdir()
        (extra / "only.png").write_bytes(b"x")

        wl_log = tmp / "wl.log"
        fake_wl = tmp / "wl"
        # Rejects the `bogus` transition exactly like wl does (exit 2 + the
        # invalid-value message), so the fallback path is exercised for real.
        fake_wl.write_text(
            "#!/bin/sh\n"
            'for a in "$@"; do [ "$a" = bogus ] && { echo "error: invalid value" >&2; exit 2; }; done\n'
            f'echo "$@" >> {wl_log}\n'
            "exit 0\n"
        )
        fake_wl.chmod(0o755)

        monitors_json = tmp / "monitors.json"
        fake_hyprctl = tmp / "hyprctl"
        fake_hyprctl.write_text(f"#!/bin/sh\ncat {monitors_json}\n")
        fake_hyprctl.chmod(0o755)

        def set_monitors(ws_id: int, ws_name: str) -> None:
            monitors_json.write_text(
                json.dumps(
                    [
                        {
                            "name": "TEST-1",
                            "activeWorkspace": {"id": ws_id, "name": ws_name},
                        }
                    ]
                )
            )

        cfg_file = tmp / "workspaces.toml"
        cfg_file.write_text(
            "[general]\n"
            f'pool = "{pool}"\n'
            'transition = "bogus"\n'
            "duration = 0.25\n"
            "\n[workspaces]\n"
            'games = "keep"\n'
            f'8 = "{extra}"\n'
            f'9 = "{tmp / "gone.jpg"}"\n'
        )
        os.environ.update(
            WL_WORKSPACES_WL=str(fake_wl),
            WL_WORKSPACES_HYPRCTL=str(fake_hyprctl),
            WL_WORKSPACES_CONFIG=str(cfg_file),
            WL_WORKSPACES_STATE=str(tmp / "state.json"),
            WL_WORKSPACES_MARKER=str(tmp / "swap"),
        )
        env = Env()
        cfg = Config.load(cfg_file)
        check("config: pool parsed", cfg.pool == pool)
        check("config: duration parsed", abs(cfg.duration - 0.25) < 1e-9)

        assigner = make_assigner(env, cfg)
        ws_list = [
            (1, "𐌰:term"),
            (2, "𐌱:web"),
            (3, "𐌲:dev"),
            (5, "𐌳:doc"),
            (6, "𐌵:vid"),
            (7, "𐌶:obs"),
        ]
        picks = {ws: assigner.image_for(ws, name) for ws, name in ws_list}
        check("mapping: every workspace gets an image", all(picks.values()))
        check("mapping: images are distinct", len(set(picks.values())) == 6)
        check(
            "mapping: kept by name override",
            assigner.image_for(4, "𐌸:games") is None,
        )
        check(
            "mapping: directory override picks from it",
            assigner.image_for(8, "𐌷:pic") == extra / "only.png",
        )
        gone_fallback = assigner.image_for(9, "𐌺:vm")
        check(
            "mapping: missing file falls back to the pool",
            gone_fallback is not None and gone_fallback.is_file(),
        )
        again = make_assigner(env, cfg)
        check(
            "mapping: another process agrees (persisted)",
            again.image_for(1, "𐌰:term") == picks[1]
            and again.image_for(7, "𐌶:obs") == picks[7],
        )
        state = load_state(env.state)
        check("state: seed persisted", isinstance(state.get("seed"), int))
        # The first assigner used default_seed(), which is today's date
        # (YYYYMMDD): whether a different seed re-picked the same image was a
        # 1-in-6 coin flip that changed with the calendar, so the gate failed
        # for a whole day at a time.  Pin the starting seed and check the sheet
        # semantics (assignments dropped, seed recorded) plus that the sheet
        # really moved across the six workspaces rather than one pair.
        state["seed"] = 4242
        save_state(env.state, state)
        pinned = {
            ws: make_assigner(env, cfg).image_for(ws, name)
            for ws, name in ws_list
        }
        state["seed"] = 777
        save_state(env.state, state)
        other = make_assigner(env, cfg)
        wiped = not other.state.get("assignments")
        moved = {ws: other.image_for(ws, name) for ws, name in ws_list}
        check(
            "mapping: a new seed starts a new sheet",
            other.state.get("assignments_seed") == 777
            and wiped
            and any(moved[ws] != pinned[ws] for ws, _ in ws_list),
        )
        state["seed"] = 4242
        save_state(env.state, state)

        set_monitors(1, "𐌰:term")
        session = Session(env, cfg, make_assigner(env, cfg))
        expected = session.assigner.image_for(1, "𐌰:term")
        check("apply: first sync paints once", session.sync() == 1)
        check(
            "apply: nothing to do while the workspace stays",
            session.sync() == 0,
        )
        first = wl_log.read_text()
        check(
            "apply: wl called with output and --no-notify",
            "--outputs TEST-1" in first and "--no-notify" in first,
        )
        check(
            "apply: a rejected transition falls back to wl's default",
            "--transition-type" not in first,
        )
        check(
            "apply: swap marker names the image",
            env.marker.is_file() and str(expected) in env.marker.read_text(),
        )
        check(
            "apply: marker is a timestamp plus the path",
            env.marker.read_text().split()[1] == str(expected),
        )

        set_monitors(4, "𐌸:games")
        check("apply: `keep` paints nothing", session.sync() == 0)
        set_monitors(5, "𐌳:doc")
        check("apply: a workspace change paints", session.sync() == 1)
        painted = [line.split()[1] for line in wl_log.read_text().splitlines()]
        if verbose:
            print(f"       painted so far: {painted}")
        check(
            "apply: the new workspace got its own image",
            len(painted) == 2 and len(set(painted)) == 2,
        )
        set_monitors(8, "𐌷:pic")
        check("apply: directory override painted", session.sync() == 1)
        check(
            "apply: it painted the override image",
            str(extra / "only.png") in wl_log.read_text().splitlines()[-1],
        )
        set_monitors(4, "𐌸:games")
        check(
            "apply: back to a kept workspace paints nothing",
            session.sync() == 0,
        )

        image = painted[-1]
        env.marker.write_text(f"{int(time.time())} {image}\n")
        check("guard: our own fresh swap is skipped", should_skip(env, image))
        check(
            "guard: a different image is not",
            not should_skip(env, str(pool / "img5.jpg")),
        )
        env.marker.write_text(f"{int(time.time()) - 60} {image}\n")
        check("guard: a stale marker is not ours", not should_skip(env, image))
        env.marker.unlink()
        check("guard: no marker means not ours", not should_skip(env, image))
        env.marker.write_text("not-a-timestamp" + " " + image + "\n")
        check(
            "guard: a corrupt marker is not ours", not should_skip(env, image)
        )

        seed_before = load_state(env.state)["assignments_seed"]
        cmd_shuffle(env, cfg)
        after = load_state(env.state)
        check(
            "shuffle: new seed stored",
            after["assignments_seed"] != seed_before,
        )
        check(
            "shuffle: the current workspace was repainted",
            len(wl_log.read_text().splitlines()) > len(painted),
        )
        check(
            "shuffle: a kept workspace stays kept",
            any(
                e.get("rule") == "keep" and not e.get("image")
                for e in after["assignments"].values()
            ),
        )

        print(
            "wl-workspaces selftest: "
            + ("OK" if not failures else f"{len(failures)} failure(s)")
        )
        return 1 if failures else 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="wl-workspaces", description=__doc__.splitlines()[0]
    )
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("watch", help="follow Hyprland events and repaint")
    sub.add_parser("shuffle", help="new seed and repaint now")
    sub.add_parser("show", help="print the current mapping")
    sub.add_parser("selftest", help="run the built-in test (no session)")
    skip_parser = sub.add_parser(
        "should-skip", help="is this paint one of our own workspace swaps?"
    )
    skip_parser.add_argument("path")
    apply_parser = sub.add_parser("apply", help="paint once")
    apply_parser.add_argument("--workspace", type=int, default=None)
    apply_parser.add_argument("--output", default=None)
    apply_parser.add_argument("--force", action="store_true")
    args = parser.parse_args(argv)

    if args.cmd == "selftest":
        return selftest()

    env = Env()
    if args.cmd == "should-skip":
        return 0 if should_skip(env, args.path) else 1
    cfg = Config.load(env.config)
    if args.cmd == "watch":
        return watch(env, cfg)
    if args.cmd == "shuffle":
        return cmd_shuffle(env, cfg)
    if args.cmd == "apply":
        return cmd_apply(env, cfg, args.workspace, args.output, args.force)
    if args.cmd == "show":
        Session(env, cfg, make_assigner(env, cfg)).show()
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main())

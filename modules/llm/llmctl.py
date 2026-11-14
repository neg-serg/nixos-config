#!/usr/bin/env python3
"""llmctl — one entry point for the local llama-swap fleet.

Subcommands cover the daily loop: see what is loaded, switch models, ask a
one-shot question, turn a git diff into a commit (`llmctl commit`), and run the
chemistry/Lean/fp/commit benchmarks. The model catalog carries the measured
scores so `llmctl models` answers "which one for what".
"""

import argparse
import atexit
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

BASE = os.environ.get("LLMCTL_URL", "http://127.0.0.1:9292")
# Chat goes through llm-proxy when it is up, so `ask`/`bench` get the context
# guard and the tool protocol. Management stays on llama-swap: the proxy does
# not own /unload or /running.
PROXY = os.environ.get("LLMCTL_PROXY_URL", "http://127.0.0.1:9300")
STATE = os.path.expanduser("~/.local/state/llmctl")

# Measured on trantor 2026-11-05: chem = six olympiad problems (13 values),
# lean = seven core-Lean theorems (7 tasks).
CATALOG = {
    "gemma4-26b-abliterated": {
        "aliases": ["gemma4", "gemma4-26b"],
        "role": "26B-A4B MoE, creative",
        "ctx": "32k",
        "size": "12 GB",
        "chem": "12/13",
        "lean": "2/7",
        "fp": "3.0/6",
    },
    "qwen3-vl-8b-abliterated": {
        "aliases": ["vision-fast", "vision-8b", "qwen3-vl-8b"],
        "role": "fast vision (8B) / chemistry",
        "ctx": "64k",
        "size": "5 GB",
        "chem": "13/13",
        "lean": "0/7",
        "fp": "-",
    },
    "qwen3.8-27b-abliterated": {
        "aliases": ["qwen3.8", "ru"],
        "role": "dense 27B: text quality tier",
        "ctx": "32k",
        "size": "11 GB",
        "chem": "12/13",
        "lean": "4/7",
        "fp": "3.7/6",
    },
    "qwen3.8-27b-vision": {
        "aliases": ["vision", "vision-27b"],
        "role": "vision + docs (27B + mmproj)",
        "ctx": "16k",
        "size": "11 GB",
        "chem": "-",
        "lean": "-",
        "fp": "-",
    },
    "qwen3.8-27b-bartowski": {
        "aliases": ["bart27b", "bartowski"],
        "role": "dense 27B, bartowski IQ3_M",
        "ctx": "16k",
        "size": "13 GB",
        "chem": "13/13",
        "lean": "-",
        "fp": "3.3/6",
    },
    "qwen3.8-27b-unsloth": {
        "aliases": ["unsloth27b", "ud"],
        "role": "dense 27B, unsloth UD-IQ3_S (base)",
        "ctx": "32k",
        "size": "12 GB",
        "chem": "13/13",
        "lean": "-",
        "fp": "4.2/6",
    },
    "qwen3.8-4b": {
        "aliases": ["commit", "commit-4b", "q4b"],
        "role": "4B distill: commit messages",
        "ctx": "16k",
        "size": "2.8 GB",
        "chem": "-",
        "lean": "-",
        "fp": "-",
        "commit": "76.9/90",
    },
    "gpt-oss-20b": {
        "aliases": ["gpt-oss", "oss20b"],
        "role": "21B MoE, MXFP4 fast tier",
        "ctx": "64k",
        "size": "10.8 GB",
        "chem": "-",
        "lean": "-",
        "fp": "-",
    },
    "qwen3.8-flash-next-abliterated": {
        "aliases": ["qwen3.8-flash", "next"],
        "role": "180B-A6B MoE, next tier",
        "ctx": "128k",
        "size": "78 GB",
        "chem": "13/13",
        "lean": "7/7",
        "fp": "6.0/6*",
    },
    "ui-tars-1.5-7b": {
        "aliases": ["uitars", "ui-tars"],
        "role": "GUI agent VLM",
        "ctx": "32k",
        "size": "7.6 GB",
        "chem": "-",
        "lean": "-",
        "fp": "-",
    },
    "oprover-8b": {
        "aliases": ["oprover", "prover"],
        "role": "Lean 4 agentic prover, 8B",
        "ctx": "32k",
        "size": "6.7 GB",
        "chem": "-",
        "lean": "0/7",
        "fp": "-",
    },
    "falcon-h1-3b": {
        "aliases": ["falcon-3b", "falcon3b", "falcon"],
        "role": "3B parallel-hybrid Mamba, fast",
        "ctx": "64k",
        "size": "3.4 GB",
        "chem": "8/13",
        "lean": "-",
        "fp": "-",
    },
    "falcon-h1r-7b": {
        "aliases": ["falcon-h1r", "h1r", "reasoner"],
        "role": "7B hybrid reasoner (long thoughts)",
        "ctx": "64k",
        "size": "5.8 GB",
        "chem": "8/13",
        "lean": "-",
        "fp": "-",
    },
    "k8s-qwen2.5-0.5b": {
        "aliases": ["k8s", "kubectl"],
        "role": "0.5B k8s: kubectl commands",
        "ctx": "32k",
        "size": "0.5 GB",
        "chem": "-",
        "lean": "-",
        "fp": "-",
    },
    "magos-k8s-0.6b": {
        "aliases": ["magos", "k8s-diag"],
        "role": "0.6B k8s RCA (kubehealth)",
        "ctx": "8k",
        "size": "0.6 GB",
        "chem": "-",
        "lean": "-",
        "fp": "-",
    },
    "holo2-4b": {
        "aliases": ["holo2"],
        "role": "GUI 4B Holo2 (Qwen3-VL)",
        "ctx": "16k",
        "size": "3.2 GB",
        "chem": "-",
        "lean": "-",
        "fp": "-",
    },
    "holo1.5-3b": {
        "aliases": ["holo3b", "holo1.5"],
        "role": "GUI 3B Holo1.5 (Qwen2.5-VL)",
        "ctx": "16k",
        "size": "3.0 GB",
        "chem": "-",
        "lean": "-",
        "fp": "-",
    },
    "gui-owl-4b": {
        "aliases": ["guiowl", "gui-owl"],
        "role": "GUI 4B GUI-Owl-1.5",
        "ctx": "16k",
        "size": "3.0 GB",
        "chem": "-",
        "lean": "-",
        "fp": "-",
    },
    "ui-tars-2b": {
        "aliases": ["uitars2b", "tars2b"],
        "role": "GUI 2B UI-TARS (fast)",
        "ctx": "16k",
        "size": "2.4 GB",
        "chem": "-",
        "lean": "-",
        "fp": "-",
    },
    # Runs on the other machine (RX 7900 XTX, 24 GB): llama-swap only routes to
    # it over ssh/proxy, so the cold load is ~3.5 min and the "VRAM" figure is
    # the remote card's, not trantor's.
    "gyro-coder": {
        "aliases": ["gyro", "gyrocoder"],
        "role": "125B MoE coder (7900 XTX box, remote)",
        "ctx": "64k",
        "size": "19.9 GB remote",
        "chem": "-",
        "lean": "-",
        "fp": "-",
    },
    # Same box; the weights and projector ride the gyro-coder SMB share under
    # mxfp4/, so a cold load streams them over the LAN (minutes).
    "swift-1.5-27b-mxfp4": {
        "aliases": ["swift27b", "swift"],
        "role": "27B dense MXFP4 (7900 XTX box, remote)",
        "ctx": "64k",
        "size": "15.8 GB remote",
        "chem": "-",
        "lean": "-",
        "fp": "-",
    },
}

CHEM_SYSTEM = """Ты — химик. Обязательные проверки:
- «Простое вещество» — это химический элемент, а не соединение.
- Молярную массу газа проверяй по относительной плотности.
- «Средняя соль» — все атомы H кислоты замещены: H3PO4 → Na3PO4.
- Для слабой кислоты при Ka/C > 0.01 решай квадратное уравнение."""

CHEM_STD = [
    (
        "P1 карбонаты",
        "Олимпиадная задача по химии. Смесь карбонатов кальция и магния массой 9.22 г "
        "полностью прокалили. Выделилось 2.24 л CO2 (н.у.). Найдите массовые доли "
        "карбонатов в исходной смеси в процентах.\n"
        "В последней строке напиши: ОТВЕТ: w(CaCO3)=...%; w(MgCO3)=...%.",
    ),
    (
        "P2 углеводород",
        "Олимпиадная задача по химии. При полном сгорании 4.40 г углеводорода "
        "образовалось 13.2 г CO2 и 7.20 г H2O. Относительная плотность паров этого "
        "вещества по водороду равна 22. Определите молекулярную формулу.\n"
        "В последней строке напиши: ОТВЕТ: формула ...",
    ),
    (
        "P3 термодинамика",
        "Олимпиадная задача по химии. Для газовой реакции A ⇌ B стандартная энергия "
        "Гиббса при 298 К равна +5.71 кДж/моль.\n1) Найдите константу равновесия K.\n"
        "2) Приняв ΔH° = +20.0 кДж/моль и ΔS° = +50.0 Дж/(моль·К) постоянными, "
        "найдите температуру (в кельвинах), выше которой реакция идёт самопроизвольно.\n"
        "В последней строке напиши: ОТВЕТ: K=...; T=... К.",
    ),
    (
        "P4 титрование",
        "Олимпиадная задача по химии. На нейтрализацию 20.0 мл раствора H2SO4 "
        "израсходовано 25.0 мл 0.100 М раствора NaOH. Найдите молярную концентрацию "
        "кислоты и массу H2SO4 в 1.00 л этого раствора.\n"
        "В последней строке напиши: ОТВЕТ: C=... М; m=... г.",
    ),
    (
        "P5 redox",
        "Олимпиадная задача по химии. Какой объём 0.0200 М раствора KMnO4 нужен для "
        "полного окисления 0.100 г FeSO4 в кислой среде? Уравнение: "
        "MnO4− + 5Fe2+ + 8H+ → Mn2+ + 5Fe3+ + 4H2O.\n"
        "В последней строке напиши: ОТВЕТ: V=... мл.",
    ),
]
CHEM_HARD = (
    "P6 фосфор",
    """Реши олимпиадную задачу по химии. Нужен полный ход решения и численные ответы.

Навеску простого вещества A массой 1.000 г полностью сожгли в избытке кислорода. Единственный продукт B имеет массу 2.291 г.

1. Определи вещество A и формулу B. Подтверди расчётом массовую долю кислорода в B.
2. Какой объём кислорода (н.у., молярный объём 22.4 л/моль) израсходован?
3. Продукт B растворили в воде и довели объём раствора до 500 мл. Рассчитай pH раствора. Считай, что кислота диссоциирует только по первой ступени, Ka1 = 7.1e-3. Объёмом воды, образующейся при реакции, пренебречь.
4. Рассчитай массу NaOH, необходимую для полной нейтрализации этого раствора до средней соли.

В конце обязательно приведи одну строку в формате:
ОТВЕТ: A=...; B=...; V(O2)=...; pH=...; m(NaOH)=...""",
)

LEAN_TASKS = [
    ("L1 contra", "theorem contra (p q : Prop) : (p → q) → (¬q → ¬p)"),
    ("L2 add3", "theorem add3 (a b c : Nat) : a + b + c = a + (b + c)"),
    (
        "L3 rev_rev",
        "theorem rev_rev (xs : List Nat) : xs.reverse.reverse = xs",
    ),
    (
        "L4 len_map",
        "theorem len_map (f : Nat → Nat) (xs : List Nat) : (xs.map f).length = xs.length",
    ),
    (
        "L5 total_append",
        "def total : List Nat → Nat\n  | [] => 0\n  | x :: xs => x + total xs\n\n"
        "theorem total_append (xs ys : List Nat) : total (xs ++ ys) = total xs + total ys",
    ),
    (
        "L6 double",
        "def double : Nat → Nat\n  | 0 => 0\n  | n + 1 => double n + 2\n\n"
        "theorem double_eq (n : Nat) : double n = 2 * n",
    ),
    (
        "L7 map_map",
        "theorem map_map (f g : Nat → Nat) (xs : List Nat) :\n    (xs.map f).map g = xs.map (fun x => g (f x))",
    ),
]
LEAN_PROMPT = """Задача по Lean 4. Доступно только ядро Lean 4.35, без Mathlib.

Допиши доказательство вместо комментария `-- proof`. Верни ТОЛЬКО полный код файла,
без markdown-ограждений и без пояснений. Не меняй формулировку теоремы.
Запрещены sorry, admit, axiom. Можно использовать ядровые тактики: rfl, simp, rw,
induction, cases, exact, intro, omega и любые другие из ядра.

```lean
{code}
```"""


# ---------------------------------------------------------------- HTTP helpers


def api(path, payload=None, timeout=900, base=None):
    url = (base or BASE) + path
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        url, data=data, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read()
    return json.loads(raw) if raw else {}


_CHAT_BASE = None


def chat_base():
    """The guard when it is running, llama-swap otherwise.

    Probed once per process: a stale proxy address would otherwise turn every
    `ask` into a connection error instead of falling back.
    """
    global _CHAT_BASE
    if _CHAT_BASE is None:
        _CHAT_BASE = BASE
        if PROXY and PROXY != BASE:
            try:
                with urllib.request.urlopen(PROXY + "/health", timeout=2):
                    _CHAT_BASE = PROXY
            except OSError:
                pass
    return _CHAT_BASE


def chat(
    model, messages, max_tokens=1024, temperature=0, cache=True, extra=None
):
    body = {
        "model": model,
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": temperature,
    }
    if not cache:
        body["cache_prompt"] = False
    if extra:
        body.update(extra)
    t0 = time.perf_counter()
    d = None
    base = chat_base()
    # The proxy owns the swap-race retry when it is in the path: it sits next
    # to llama-swap, unloads and waits there already, so retrying here as well
    # would turn one failure into up to nine upstream attempts. Talking to
    # llama-swap directly, llmctl keeps its own retry.
    attempts = 1 if base == PROXY else 3
    for attempt in range(attempts):
        try:
            d = api("/v1/chat/completions", body, base=base)
            break
        except urllib.error.HTTPError as exc:
            # llama-swap answers 500 "group: starting <model> failed: aborted"
            # when a model start is cancelled under it (observed on the first
            # request after a switch or an unload, and it can wedge for a
            # minute). Retry 5xx only — a 4xx is the caller's mistake — and
            # unload in between: an explicit unload clears the wedged state,
            # which is what made the same request succeed by hand.
            if exc.code < 500 or attempt == attempts - 1:
                raise
            try:
                with urllib.request.urlopen(BASE + "/unload", timeout=15):
                    pass
            except OSError:
                pass
            # Wait until the router reports no resident model: retrying while
            # the previous backend is still stopping re-creates the race (the
            # new llama-server starts and dies on a VRAM allocation, which
            # reaches the client as 502 "proxy error: EOF").
            deadline = time.time() + 120
            while time.time() < deadline and running():
                time.sleep(2)
            time.sleep(5 * (attempt + 1))
        except urllib.error.URLError:
            if attempt == attempts - 1:
                raise
            time.sleep(5 * (attempt + 1))
    wall = time.perf_counter() - t0
    msg = (d.get("choices") or [{}])[0].get("message") or {}
    return {
        "content": msg.get("content") or "",
        "reasoning": msg.get("reasoning_content") or "",
        "timings": d.get("timings") or {},
        "wall": wall,
        "finish": (d.get("choices") or [{}])[0].get("finish_reason"),
    }


def running():
    try:
        return api("/running", timeout=5).get("running", [])
    except Exception:
        return []


def vram_card():
    best = None
    for dev in glob.glob("/sys/class/drm/card[0-9]*/device"):
        try:
            total = int(
                open(os.path.join(dev, "mem_info_vram_total")).read().strip()
            )
        except OSError:
            continue
        if total > 8 * 2**30 and (best is None or total > best[1]):
            best = (dev, total)
    return best


def fmt_gib(n):
    return f"{n / 2**30:.1f}"


def vram_used(card):
    if not card:
        return None
    try:
        return int(
            open(os.path.join(card[0], "mem_info_vram_used")).read().strip()
        )
    except OSError:
        return None


def service_state():
    r = subprocess.run(
        ["systemctl", "is-active", "llama-swap"],
        capture_output=True,
        text=True,
    )
    return r.stdout.strip() or "unknown"


def model_names():
    try:
        return [m["id"] for m in api("/v1/models", timeout=10).get("data", [])]
    except Exception:
        return list(CATALOG)


def resolve(name):
    if name in CATALOG:
        return name
    for real, meta in CATALOG.items():
        if name in meta.get("aliases", []):
            return real
    for real in model_names():
        if real == name:
            return real
    return None


def print_status():
    print(f"llama-swap  {service_state()}  ({BASE})")
    r = running()
    if r:
        for m in r:
            print(
                f"running     {m.get('model')}  ctx={m.get('ttl', '?')}s ttl  "
                f"{m.get('state', '')}"
            )
    else:
        print("running     — (idle, model unloads after TTL)")
    card = vram_card()
    if card:
        total = card[1]
        used = vram_used(card)
        if used is not None:
            print(f"VRAM        {fmt_gib(used)} / {fmt_gib(total)} GiB")
    try:
        live = model_names()
        print(f"models      {len(live)}: " + ", ".join(live))
    except Exception:
        print("models      unavailable")


def print_models():
    live = set(model_names())
    print(
        f"{'NAME':32s} {'ROLE':28s} {'CTX':>4s} {'VRAM':>6s} {'CHEM':>6s} "
        f"{'LEAN':>5s} {'FP':>5s} {'COMMIT':>6s}  ALIASES"
    )
    for name, meta in CATALOG.items():
        mark = "*" if name in live else " "
        print(
            f"{mark}{name:31s} {meta['role']:28s} {meta['ctx']:>4s} "
            f"{meta['size']:>6s} {meta['chem']:>6s} {meta['lean']:>5s} "
            f"{meta['fp']:>5s} {meta.get('commit', '-'):>6s}  "
            f"{', '.join(meta['aliases'])}"
        )
    print(
        "\n* = present in the live catalog. Scores are measured on trantor; "
        "chem = 6 olympiad problems (13 values), lean = 7 core-Lean "
        "theorems, fp = 6 build-planning cases (partial credit), "
        "commit = 9 real diffs from this repository (10 points each). "
        "* = fp with the tier's own thinking config; every other fp score has "
        "thinking pinned off for comparability. The qwen tiers repeat exactly "
        "across runs. The Lean prover (oprover) is "
        "trained against Mathlib, which this host does not have, so its "
        "core-only score understates it and is not comparable with the "
        "general tiers."
    )


def cmd_use(args):
    name = (
        resolve(args.name) if args.name else pick_model("Загрузить модель: ")
    )
    if not name:
        sys.exit("unknown model")
    print(f"loading {name} ...")
    try:
        r = chat(
            name,
            [{"role": "user", "content": "Reply with the single word: ok."}],
            max_tokens=2,
        )
    except Exception as exc:  # noqa: BLE001
        sys.exit(f"failed: {exc}")
    t = r["timings"]
    print(
        f"loaded in {r['wall']:.1f}s  "
        f"decode {t.get('predicted_per_second', 0):.1f} tok/s  "
        f"ctx {t.get('prompt_n', '?')} prompt tokens"
    )
    print_status()


def cmd_prewarm(args):
    """Warm the page cache for a model's gguf files without touching VRAM.

    The load path is mmap, so a prewarmed file turns an 8.3 s cold start into
    a 2.5 s one (measured 2026-11-11 on the 27B vision slot). It does not
    create speed out of nothing: the same ~12 GB is read from disk, just
    before the answer is needed instead of inside the request. Pages are
    reclaimable, so under memory pressure the warmth is lost again.
    """
    name = resolve(args.model)
    if not name:
        sys.exit(f"unknown model: {args.model}")
    if not shutil.which("vmtouch"):
        sys.exit("vmtouch not found (nixpkgs#vmtouch)")
    files = model_files(name)
    total = sum(os.path.getsize(f) for f in files)
    if args.check:
        subprocess.run(["vmtouch", *files], check=False)
        return
    t0 = time.time()
    subprocess.run(["vmtouch", "-t", *files], capture_output=True, check=False)
    dt = time.time() - t0
    rate = total / dt / 2**30 if dt else 0
    print(
        f"prewarmed {name}: {len(files)} files, {total / 2**30:.1f} GiB "
        f"in {dt:.1f}s ({rate:.1f} GiB/s)",
        flush=True,
    )
    subprocess.run(["vmtouch", *files], check=False)


def model_files(name):
    """gguf paths the router will mmap for `name`.

    Read out of the live llama-swap config (the unit names it with
    `--config=`), so the paths have one source of truth in llama-swap.nix and
    cannot drift from a copy in here.
    """
    try:
        unit = subprocess.run(
            ["systemctl", "cat", "llama-swap"],
            capture_output=True,
            text=True,
            timeout=10,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        unit = ""
    cfg = ""
    for tok in unit.split():
        # The unit quotes every argument ('--config=/nix/store/...yaml'), so
        # the quote has to come off before the prefix check.
        tok = tok.strip("'\"")
        if tok.startswith("--config="):
            cfg = tok.split("=", 1)[1].strip("'\"")
            break
    if not cfg or not os.path.exists(cfg):
        sys.exit(
            "cannot find the llama-swap config (systemctl cat llama-swap)"
        )
    block, current = [], None
    for line in open(cfg):
        m = re.match(r"^  ([A-Za-z0-9][A-Za-z0-9._-]*):\s*$", line)
        if m:
            current = m.group(1)
            continue
        if current == name:
            block.append(line)
    text = "".join(block)
    files = []
    for flag in ("-m", "--mmproj"):
        m = re.search(rf"(?:^|\s){re.escape(flag)}\s+(/\S+?\.gguf)", text)
        if m:
            files.append(m.group(1))
    if not files:
        sys.exit(f"no gguf paths in the llama-swap cmd for {name}")
    return files


def cmd_unload(_args):
    # Targeted unload, not GET /unload: that form blocks until every backend
    # is gone, so it hung for its whole 15 s timeout whenever a model was
    # still `starting` (observed 2026-11-11). POST /api/models/unload answers
    # at once with {"msg":"ok"} and stops the backend in the background, so
    # the command returns in ~0.1 s and the caller only waits on VRAM.
    card = vram_card()
    before = vram_used(card)
    names = [m.get("model") for m in running() if m.get("model")]
    if names:
        for name in names:
            req = urllib.request.Request(
                BASE + "/api/models/unload",
                json.dumps({"name": name}).encode(),
                {"Content-Type": "application/json"},
                method="POST",
            )
            try:
                urllib.request.urlopen(req, timeout=10).read()
            except Exception as exc:  # noqa: BLE001
                sys.exit(f"unload of {name} failed: {exc}")
    else:
        # /running can be empty while a backend is still coming up; the
        # blanket unload is the only lever that also catches that case.
        try:
            with urllib.request.urlopen(BASE + "/unload", timeout=10):
                pass
        except Exception:  # noqa: BLE001
            pass
    for _ in range(40):  # up to 20 s: VRAM is released shortly after the OK
        if not running():
            break
        time.sleep(0.5)
    # /running clears before the backend has actually exited, so wait for the
    # VRAM figure to settle (three identical samples, ~1.5 s) before
    # reporting: sampling right after the OK understates what was freed.
    last, stable = None, 0
    for _ in range(40):
        cur = vram_used(card)
        if cur is not None and cur == last:
            stable += 1
            if stable >= 3:
                break
        else:
            stable, last = 0, cur
        time.sleep(0.5)
    after = vram_used(card)
    freed = ""
    if before is not None and after is not None:
        freed = f"  ({fmt_gib(before - after)} GiB freed)"
    print(f"unloaded {', '.join(names) or 'nothing'}{freed}")
    print_status()


def cmd_ask(args):
    name = resolve(args.model)
    if not name:
        sys.exit(f"unknown model: {args.model}")
    messages = []
    if args.chem:
        messages.append({"role": "system", "content": CHEM_SYSTEM})
    messages.append({"role": "user", "content": args.text})
    r = chat(name, messages, max_tokens=args.max, temperature=args.temp)
    body = r["content"].strip()
    if not body and r["reasoning"]:
        body = r["reasoning"].strip()
        print("[content empty, showing reasoning]\n")
    print(body)
    t = r["timings"]
    print(
        f"\n— {name}  {r['wall']:.1f}s  "
        f"{t.get('predicted_n', '?')} tok  "
        f"{t.get('predicted_per_second', 0):.1f} tok/s  finish={r['finish']}"
    )


# ------------------------------------------------------------------ chem bench


def _nums(text):
    t = re.sub(r"(?<=\d),(?=\d)", ".", text)
    return [
        float(x)
        for x in re.findall(
            r"(?<![A-Za-zА-Яа-я0-9])(\d+(?:\.\d+)?)(?![A-Za-zА-Яа-я0-9])", t
        )
    ]


def _norm_formula(s):
    subs = str.maketrans("₀₁₂₃₄₅₆₇₈₉", "0123456789")
    s = re.sub(r"\\text\{([A-Za-z]+)\}", r"\1", s).translate(subs)
    return re.sub(r"[\s${}\\_]", "", s).upper()


def _tail(text):
    i = text.upper().rfind("ОТВЕТ")
    return text[i:] if i >= 0 else text[-700:]


def _near(x, v, tol):
    return abs(x - v) <= tol


def grade_chem(idx, text):
    t = _tail(text)
    n = _nums(t)
    if idx == 0:
        ok = len(n) >= 2 and (
            (_near(n[0], 54.28, 0.8) and _near(n[1], 45.72, 0.8))
            or (_near(n[0], 55.59, 0.8) and _near(n[1], 44.41, 0.8))
        )
        return [ok, ok]
    if idx == 1:
        return ["C3H8" in _norm_formula(t)]
    if idx == 2:
        return [
            any(_near(x, 0.0998, 0.005) for x in n),
            any(_near(x, 400, 8) for x in n),
        ]
    if idx == 3:
        return [
            any(_near(x, 0.0625, 0.0013) for x in n),
            any(_near(x, 6.13, 0.12) for x in n),
        ]
    if idx == 4:
        return [
            any(_near(x, 6.58, 0.13) or _near(x, 0.00658, 0.00013) for x in n)
        ]
    flat = _norm_formula(t)
    a = bool(re.search(r"A[=:—-](P(?![A-Z0-9])|ФОСФОР)", flat))
    b = ("P4O10" in flat) or ("P2O5" in flat)
    if not (a and b):
        return [a, b, False, False, False]
    return [
        a,
        b,
        any(_near(x, 0.904, 0.02) for x in n),
        any(1.65 <= x <= 1.80 for x in n),
        any(_near(x, 3.87, 0.18) for x in n),
    ]


def _result_path(kind, started):
    """One file per run, named so runs sort chronologically and never clash.

    The old `{kind}-{epoch}.json` silently lost data: two runs that finished
    inside the same second resolved to the same name and overwrote each other
    (a partial chem record disappeared that way). Seconds plus pid keep both
    concurrent and repeated runs apart.
    """
    stamp = time.strftime("%Y%m%d-%H%M%S", time.localtime(started))
    path = os.path.join(STATE, f"{kind}-{stamp}-{os.getpid()}.json")
    # The counter only fires for two runs in the same second from the same
    # process (the CLI never does that), but it makes the name unique by
    # construction instead of by assumption.
    n = 1
    while os.path.exists(path):
        n += 1
        path = os.path.join(STATE, f"{kind}-{stamp}-{os.getpid()}-{n}.json")
    return path


def _save_results(kind, models, started, results, extra=None):
    """Persist one bench run with provenance next to the per-model records.

    `__meta__` sits beside the model keys rather than wrapping them, so the
    flat records written before this field stay queryable by the same
    `jq '.["model"]'` form. `seed` is null on purpose: the server default
    (-1) draws a fresh random seed per request, i.e. every run is an
    independent sample, not a replay of one. `extra` carries bench-specific
    provenance (repository and prompt variant for the commit bench).
    """
    os.makedirs(STATE, exist_ok=True)
    path = _result_path(kind, started)
    data = {
        "__meta__": {
            "kind": kind,
            "started": time.strftime(
                "%Y-%m-%dT%H:%M:%S", time.localtime(started)
            ),
            "finished": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "models": models,
            "temperature": 0,
            "cache_prompt": False,
            "seed": None,
            "url": BASE,
            "pid": os.getpid(),
            **(extra or {}),
        },
        **results,
    }
    with open(path, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"\nsaved {path}")
    return path


def bench_chem(models, use_prompt=False):
    started = time.time()
    tasks = CHEM_STD + [CHEM_HARD]
    results = {}
    print(
        f"\nХимия: {len(tasks)} задач, {len(models)} моделей"
        + (" (chem system prompt)" if use_prompt else "")
    )
    for model in models:
        results[model] = []
        vals = 0
        total = 0
        print(f"\n== {model}")
        for i, (label, text) in enumerate(tasks):
            messages = (
                [{"role": "system", "content": CHEM_SYSTEM}]
                if use_prompt
                else []
            )
            messages.append({"role": "user", "content": text})
            try:
                r = chat(model, messages, max_tokens=6000, cache=False)
                m = grade_chem(i, r["content"])
            except Exception as exc:  # noqa: BLE001
                m, r = [], {"wall": 0, "timings": {}, "finish": "error"}
                print(f"  {label}: FAILED {exc}")
                results[model].append(
                    {"label": label, "matched": m, "error": str(exc)}
                )
                continue
            vals += sum(m)
            total += len(m)
            print(
                f"  {label:18s} {sum(m)}/{len(m)}  {r['wall']:5.1f}s  "
                f"finish={r['finish']}"
            )
            results[model].append(
                {
                    "label": label,
                    "matched": m,
                    "wall": r["wall"],
                    "finish": r["finish"],
                    "answer": _tail(r["content"]).strip()[-300:],
                }
            )
        print(f"  -> {vals}/{total}")
        results[model].append({"total": vals, "of": total})
    _save_results("chem", models, started, results)
    return results


# ------------------------------------------------------------------ lean bench


def _extract_code(text):
    fences = re.findall(r"```(?:lean|lean4)?\s*\n(.*?)```", text, re.S)
    if fences:
        return max(fences, key=len)
    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if re.match(r"\s*(theorem|def|import|open|set_option)\b", line):
            start = i
            break
    return "\n".join(lines[start:]) if start is not None else text


def _normalize(s):
    return re.sub(r"\s+", " ", s).strip()


def _lean_check(lean, task, code, path):
    name = re.search(r"theorem\s+(\w+)", task[1]).group(1)
    stmt = task[1][task[1].index(f"theorem {name}") :]
    if re.search(r"\b(sorry|admit|axiom)\b", code):
        return False, "sorry/admit/axiom"
    if not re.search(rf"\btheorem\s+{re.escape(name)}\b", code):
        return False, "theorem missing"
    m = re.search(rf"theorem\s+{re.escape(name)}\b(.*?):=", code, re.S)
    if not m:
        return False, "signature not found"
    got = _normalize(f"theorem {name} {m.group(1)}").replace(" ", "")
    want = _normalize(stmt).replace(" ", "")
    if got != want:
        return False, "statement changed"
    with open(path, "w") as f:
        f.write(code)
    try:
        r = subprocess.run(
            [lean, path], capture_output=True, text=True, timeout=120
        )
    except subprocess.TimeoutExpired:
        return False, "timeout"
    if r.returncode != 0:
        lines = (r.stdout + r.stderr).strip().splitlines()
        return False, " | ".join(lines[:2])[:160]
    return True, "ok"


def bench_lean(models):
    started = time.time()
    lean = shutil.which("lean")
    if not lean:
        sys.exit(
            "lean not in PATH — run inside: nix shell nixpkgs#lean4 -c llmctl bench lean"
        )
    results = {}
    print(f"\nLean: {len(LEAN_TASKS)} задач, {len(models)} моделей")
    with tempfile.TemporaryDirectory(prefix="llmctl-lean-") as tmp:
        for model in models:
            results[model] = []
            ok = 0
            print(f"\n== {model}")
            for label, stmt in LEAN_TASKS:
                prompt = LEAN_PROMPT.format(code=stmt + " := by\n  -- proof\n")
                try:
                    r = chat(
                        model,
                        [{"role": "user", "content": prompt}],
                        max_tokens=2000,
                        cache=False,
                        # Thinking has to be off: the cap is 2000 tokens and a
                        # thinking tier spends all of them on thoughts, so the
                        # reply carries no code at all (measured: 2/7 with
                        # thinking on, 7/7 off on qwen3.8-flash-next). The
                        # bench grades compiled code, not prose.
                        extra={
                            "chat_template_kwargs": {"enable_thinking": False}
                        },
                    )
                    code = _extract_code(r["content"])
                except Exception as exc:  # noqa: BLE001
                    print(f"  {label}: FAILED {exc}")
                    results[model].append(
                        {"label": label, "ok": False, "error": str(exc)}
                    )
                    continue
                path = os.path.join(tmp, f"{label.split()[0]}.lean")
                good, msg = _lean_check(lean, (label, stmt), code, path)
                ok += int(good)
                print(f"  {label:18s} {'OK ' if good else 'FAIL'}  {msg}")
                results[model].append(
                    {"label": label, "ok": good, "detail": msg}
                )
            print(f"  -> {ok}/{len(LEAN_TASKS)}")
            results[model].append({"total": ok, "of": len(LEAN_TASKS)})
    _save_results("lean", models, started, results)
    return results


# -------------------------------------------------------------------- fp bench

# A build-system planning task, the one an FP/olympiad round would pose: given
# a task graph, current file hashes, the previous manifest and the hashes a
# rebuild would produce, emit the rebuild plan. The hard part is early cut-off:
# a task that reruns but produces the same hash must not wake its dependents.
# `sameOutput` lists exactly those tasks, so the answer is a JSON object that
# grades exactly — no model-written code is ever executed.
FP_RULES = """Ты — планировщик инкрементальной сборки. Отвечай ТОЛЬКО одним JSON-объектом, без markdown и пояснений.

Входные данные:
- roots: цели. Планируются только задачи, достижимые из roots по входам-задачам.
- tasks: [{"id":..., "inputs":[...]}] — вход это имя файла ИЛИ id задачи; порядок входов значим.
- hashes: файл -> хэш; значение null значит, что файл удалён.
- prev: id -> {"out": хэш, "inputs": [хэши входов прошлой сборки]}.
- newOut: id -> хэш, который задача выдала бы, если её запустить сейчас.

Правила:
1) Задача t пересобирается тогда и только тогда, когда t отсутствует в prev ИЛИ вектор текущих хэшей её входов не равен prev[t].inputs.
2) Хэш входа-файла f = hashes[f]. Хэш входа-задачи d = prev[d].out, если d не пересобирается, иначе newOut[d].
3) Выход пересобранной задачи = newOut[t]; непересобранной = prev[t].out.
4) cut-off: если пересобранная t даёт newOut[t] == prev[t].out, её зависимые видят прежний хэш и, если больше ничего не изменилось, не пересобираются. Сама такая t попадает в sameOutput.
5) waves: wave(t) = 0, если среди зависимостей нет пересобираемых, иначе 1 + max(wave(d)) по пересобираемым зависимостям.
6) rebuilt, sameOutput, gc — отсортированные по id массивы; out — объект id -> итоговый хэш, только для достижимых задач.
7) Ошибки: цикл -> {"error":"cycle","cycle":[ids]} (начинать с лексикографически минимального id цикла); повтор входа -> {"error":"duplicate_input","task":id,"input":name}; вход, который не является ни задачей, ни ключом hashes -> {"error":"unknown_input","task":id,"input":name}.
8) gc — отсортированный список задач, недостижимых из roots.

Формат успешного ответа: {"rebuilt":[...],"waves":[[...]],"sameOutput":[...],"out":{...},"gc":[...]}"""

FP_CASES = [
    (
        "F1 cut-off",
        {
            "roots": ["app"],
            "tasks": [
                {"id": "gen", "inputs": ["tools/gen@v3"]},
                {"id": "lib", "inputs": ["src/lib.c"]},
                {"id": "app", "inputs": ["gen", "lib", "src/main.c"]},
            ],
            "hashes": {
                "tools/gen@v3": "t3",
                "src/lib.c": "f1",
                "src/main.c": "f0",
            },
            "prev": {
                "gen": {"out": "G1", "inputs": ["t3"]},
                "lib": {"out": "L1", "inputs": ["f0"]},
                "app": {"out": "A1", "inputs": ["G1", "L1", "f0"]},
            },
            "newOut": {"gen": "G1", "lib": "L1", "app": "A9"},
        },
        {
            "rebuilt": ["lib"],
            "waves": [["lib"]],
            "sameOutput": ["lib"],
            "out": {"app": "A1", "gen": "G1", "lib": "L1"},
            "gc": [],
        },
    ),
    (
        "F2 propagate",
        {
            "roots": ["app"],
            "tasks": [
                {"id": "gen", "inputs": ["tools/gen@v3"]},
                {"id": "lib", "inputs": ["src/lib.c"]},
                {"id": "app", "inputs": ["gen", "lib", "src/main.c"]},
            ],
            "hashes": {
                "tools/gen@v3": "t3",
                "src/lib.c": "f1",
                "src/main.c": "f0",
            },
            "prev": {
                "gen": {"out": "G1", "inputs": ["t3"]},
                "lib": {"out": "L1", "inputs": ["f0"]},
                "app": {"out": "A1", "inputs": ["G1", "L1", "f0"]},
            },
            "newOut": {"gen": "G1", "lib": "L2", "app": "A9"},
        },
        {
            "rebuilt": ["app", "lib"],
            "waves": [["lib"], ["app"]],
            "sameOutput": [],
            "out": {"app": "A9", "gen": "G1", "lib": "L2"},
            "gc": [],
        },
    ),
    (
        "F3 new+gc",
        {
            "roots": ["hook"],
            "tasks": [
                {"id": "base", "inputs": []},
                {"id": "lib", "inputs": ["base", "src/lib.c"]},
                {"id": "cli", "inputs": ["lib"]},
                {"id": "docs", "inputs": ["README.md"]},
                {"id": "hook", "inputs": ["cli", "docs"]},
                {"id": "old", "inputs": ["lib"]},
            ],
            "hashes": {"src/lib.c": "f1", "README.md": "r1"},
            "prev": {
                "base": {"out": "B1", "inputs": []},
                "lib": {"out": "L1", "inputs": ["B1", "f0"]},
                "cli": {"out": "C1", "inputs": ["L1"]},
                "hook": {"out": "H1", "inputs": ["C1", "R0"]},
            },
            "newOut": {
                "base": "B1",
                "lib": "L2",
                "cli": "C2",
                "docs": "D1",
                "hook": "H2",
            },
        },
        {
            "rebuilt": ["cli", "docs", "hook", "lib"],
            "waves": [["docs", "lib"], ["cli"], ["hook"]],
            "sameOutput": [],
            "out": {
                "base": "B1",
                "cli": "C2",
                "docs": "D1",
                "hook": "H2",
                "lib": "L2",
            },
            "gc": ["old"],
        },
    ),
    (
        "F4 deleted",
        {
            "roots": ["app"],
            "tasks": [
                {"id": "gen", "inputs": ["tools/gen@v3"]},
                {"id": "lib", "inputs": ["src/lib.c"]},
                {"id": "app", "inputs": ["gen", "lib", "src/main.c"]},
            ],
            "hashes": {
                "tools/gen@v3": "t3",
                "src/lib.c": "f0",
                "src/main.c": None,
            },
            "prev": {
                "gen": {"out": "G1", "inputs": ["t3"]},
                "lib": {"out": "L1", "inputs": ["f0"]},
                "app": {"out": "A1", "inputs": ["G1", "L1", "f0"]},
            },
            "newOut": {"gen": "G1", "lib": "L1", "app": "A9"},
        },
        {
            "rebuilt": ["app"],
            "waves": [["app"]],
            "sameOutput": [],
            "out": {"app": "A9", "gen": "G1", "lib": "L1"},
            "gc": [],
        },
    ),
    (
        "F5 cycle",
        {
            "roots": ["a"],
            "tasks": [
                {"id": "a", "inputs": ["b"]},
                {"id": "b", "inputs": ["c"]},
                {"id": "c", "inputs": ["a"]},
            ],
            "hashes": {},
            "prev": {},
            "newOut": {},
        },
        {"error": "cycle", "cycle": ["a", "b", "c"]},
    ),
    (
        # The cut-off sits in the middle of a chain here, not at its head: the
        # rebuilt task keeps the old hash, so the task above it must neither
        # rerun nor change its output. Models that conflate "reran" with
        # "changed" rebuild `top` and report T9.
        "F6 mid-chain",
        {
            "roots": ["top"],
            "tasks": [
                {"id": "gen", "inputs": ["src.c"]},
                {"id": "mid", "inputs": ["gen"]},
                {"id": "top", "inputs": ["mid"]},
            ],
            "hashes": {"src.c": "f1"},
            "prev": {
                "gen": {"out": "G1", "inputs": ["f0"]},
                "mid": {"out": "M1", "inputs": ["G1"]},
                "top": {"out": "T1", "inputs": ["M1"]},
            },
            "newOut": {"gen": "G2", "mid": "M1", "top": "T9"},
        },
        {
            "rebuilt": ["gen", "mid"],
            "waves": [["gen"], ["mid"]],
            "sameOutput": ["mid"],
            "out": {"gen": "G2", "mid": "M1", "top": "T1"},
            "gc": [],
        },
    ),
]

FP_WEIGHTS = [
    ("rebuilt", 0.4),
    ("waves", 0.2),
    ("sameOutput", 0.2),
    ("out", 0.1),
    ("gc", 0.1),
]


def _fp_json(text):
    """Pull the first complete JSON object out of a reply.

    Models fence it, prefix it with prose, or answer twice; taking the first
    balanced object is the least surprising rule and keeps grading exact.
    """
    text = re.sub(r"```(?:json)?", "", text or "")
    start = depth = 0
    for i, ch in enumerate(text):
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start is not None:
                try:
                    return json.loads(text[start : i + 1])
                except ValueError:
                    start = None
    return None


def _fp_grade(expected, got):
    if got is None:
        return 0.0, "no-json"
    if "error" in expected:
        if got.get("error") != expected["error"]:
            return 0.0, f"want error {expected['error']}"
        if expected.get("cycle") and got.get("cycle") != expected["cycle"]:
            return 0.0, "cycle wrong"
        return 1.0, "ok"
    score, missed = 0.0, []
    for field, weight in FP_WEIGHTS:
        if got.get(field) == expected[field]:
            score += weight
        else:
            missed.append(field)
    return round(score, 2), "ok" if not missed else "miss:" + ",".join(missed)


def bench_fp(models, thinking=False):
    """Build-planning bench: six cases, exact JSON, partial credit per field.

    Thinking is off per request by default (`enable_thinking`): the task tests
    the algorithm, and a 4096-token think on every case adds minutes per case.
    `thinking=True` leaves the tier's own config alone, which is the only way
    to measure what the thoughts are worth — on the cut-off cases they flip a
    0.5 into a 1.0.
    """
    started = time.time()
    results = {}
    print(f"\nFP-планировщик: {len(FP_CASES)} задач, {len(models)} моделей")
    for model in models:
        results[model] = []
        total = 0.0
        print(f"\n== {model}")
        for label, spec, expected in FP_CASES:
            messages = [
                {"role": "system", "content": FP_RULES},
                {"role": "user", "content": "Вход:\n" + json.dumps(spec)},
            ]
            try:
                extra = (
                    None
                    if thinking
                    else {"chat_template_kwargs": {"enable_thinking": False}}
                )
                r = chat(
                    model,
                    messages,
                    max_tokens=9000 if thinking else 6000,
                    cache=False,
                    extra=extra,
                )
                got = _fp_json(r["content"]) or _fp_json(r["reasoning"])
            except Exception as exc:  # noqa: BLE001
                print(f"  {label:14s} FAILED {exc}")
                results[model].append(
                    {"label": label, "error": str(exc), "score": 0.0}
                )
                continue
            score, note = _fp_grade(expected, got)
            total += score
            print(
                f"  {label:14s} {score:4.2f}  {note:24s} " f"{r['wall']:5.0f}s"
            )
            results[model].append(
                {
                    "label": label,
                    "score": score,
                    "note": note,
                    "wall": r["wall"],
                    "got": got,
                }
            )
        results[model].append({"total": round(total, 2), "of": len(FP_CASES)})
        print(f"  -> {total:.2f}/{len(FP_CASES)}")
    _save_results("fp", models, started, results)
    return results


# ---------------------------------------------------------------- commit bench

# Real commits from this repository, one per shape a daily change takes: a
# one-file package patch, a subtle Nix setting, a two-file alias fix, a shell
# script, a config-only addition, a Justfile repair, a layout checker, a
# multi-file feature and a 32-bit packaging change. The model sees `git show`
# without the message; grading compares the reply with the commit that was
# actually made. Fixed hashes keep runs comparable across days and fleet
# changes, unlike sampling the tail of the log.
COMMIT_CASES = [
    ("aurora-ffmpeg", "04b8bbe5f"),
    ("nixpkgs-registry", "b90ad5965"),
    ("btm-alias", "6df32eab5"),
    ("rollout-ansi", "4fa96cb0b"),
    ("gtk4-schemas", "9adb15bad"),
    ("clean-caches", "f96d81b29"),
    ("pleamar-geometry", "3714ea7e5"),
    ("samba-shares", "c42f4e55e"),
    ("rct32-repro", "859a320f6"),
]

# The default commit-writer set, measured 2026-11-09 and re-run 2026-11-11 (9
# real diffs; totals of 90 under the 0-10 rubric): qwen3.8-27b 81.2,
# qwen3.8-4b 76.9, qwen3-vl-8b 73.9, gemma4 70.8. The 27B is the quality tier
# and stays the pick when it is already resident; the 4B is the dedicated
# writer (COMMIT_DEFAULT_MODEL, `commit` alias) and the 8B vision model left
# this lane with the 2026-11-11 change — it is the image tier only now.
# devstral left the fleet on 2026-11-11 with its weights; its 76.5 stands as
# the recorded score, the remaining three keep the comparison.
COMMIT_MODELS = [
    "qwen3.8-4b",
    "gemma4-26b-abliterated",
    "qwen3.8-27b-abliterated",
]

COMMIT_SCOPES_IN_PROMPT = 30
COMMIT_DIFF_CHARS = 24000
COMMIT_MAX_TOKENS = 400
# `--split` costs one extra model call (the plan) plus one per group, so its
# planning prompt gets a smaller budget than a single message: grouping needs
# the shape of each change, not every line of it.
COMMIT_PLAN_CHARS = 12000
COMMIT_PLAN_FILE_CHARS = 1200
COMMIT_PLAN_MAX_TOKENS = 700
# More groups than this means the model is cutting a change into pieces that
# cannot be reviewed or reverted on their own; such a plan is rejected.
COMMIT_PLAN_MAX_GROUPS = 8

COMMIT_RULES = """You write git commit messages for a NixOS configuration repository.

The repository's conventions:
- First line: `[scope] Imperative subject`, at most 72 characters, no
  trailing period. `scope` names the area of the change: usually a path area
  ([servers/samba], [gui/theme], [cli]) and sometimes a thematic one
  ([media/audio], [hardware/audio]). Pick one from the scope list below.
- Then one blank line and a body of 2-5 sentences: what changed and why,
  naming the concrete mechanisms, options or tradeoffs visible in the diff.
  Describe the effect of the change, not a file-by-file walkthrough.
- English only, plain text: no markdown fences, no bullet lists, no quotes
  around the message. Do not mention file line numbers. Do not invent reasons
  or details that the diff does not support.

Return only the commit message."""

COMMIT_PLAN_RULES = """You split one pending change of a NixOS configuration
repository into the commits it should become.

Return JSON only: an array of groups with the changed paths, no prose and no
code fences:
[{"files": ["path/one.nix", "path/two.nix"]}, {"files": ["other.nix"]}]

Rules:
- Every changed file appears in exactly one group.
- A group is one logical change: files that belong in the same review and can
  be reverted together. Files under one directory, and a file with the test or
  documentation that explains it, usually belong together.
- Use the fewest groups, but never fewer than the number of unrelated
  changes: two files that change different mechanisms are two commits even
  when they live in the same directory. A shared directory is not a reason
  to merge, and never split a single mechanism across commits.
- Put the self-contained change first (locks, formatting, tests before
  behaviour) so the later commits build on it.
- Copy the paths exactly as they are given."""

# One example of the target shape, unrelated to the bench's cases so a small
# model can copy the structure without copying its content.
COMMIT_EXAMPLE = """Example of the expected shape:
[services/backup] Stop the timer from waking a sleeping host

The nightly snapshot timer fires at 03:00 and wakes the machine, but the
backup itself only runs when the host is already awake, so the missed runs
leave gaps in the archive. Move the timer to boot and stamp each run, so a
skipped night is caught up on the next start instead of being lost."""

# The bench strips the subject scope before matching content words, so the
# scope vocabulary can be graded separately from how well the subject names
# the change.
COMMIT_STOP = set(
    """the a an and or but if then than that this these those with without
    for from into onto via when where while what which who whom whose is are
    was were be been being has have had do does did not no to of in on at by
    as it its their there here also only just more most less least very can
    should would could will may might must about after before under over
    between within each other such like using used use make makes made add
    adds added fix fixes fixed change changes changed keep keeps kept new old
    one two three all any some same way still even back out up down off so why
    how because since now per instead rather through against
    """.split()
)

_COMMIT_PATH_RE = re.compile(
    r"[A-Za-z0-9_.@+/-]+\.(?:nix|sh|py|lua|rs|md|json|toml|lock|js|ts|c|h|"
    r"svg|desktop|service|timer|conf|ya?ml|xml|patch)"
)


def _git(repo, *args):
    return subprocess.run(
        ["git", "-C", repo, *args], capture_output=True, text=True
    )


def _commit_default_repo():
    env = os.environ.get("LLMCTL_REPO")
    if env:
        return env
    if os.path.isdir("/etc/nixos/.git"):
        return "/etc/nixos"
    return os.getcwd()


def _commit_tokens(text):
    return {
        w
        for w in re.findall(r"[a-z0-9][a-z0-9_.+/-]{2,}", text.lower())
        if w not in COMMIT_STOP and not w.isdigit()
    }


def _commit_scopes(repo, limit=400):
    """Return (top scopes for the prompt, all scopes accepted by grading).

    The repository uses a small scope vocabulary; showing its most frequent
    entries is worth a few hundred prompt tokens because a small model then
    picks `[servers/samba]` instead of inventing `[config]`. Any scope seen in
    the recent log is accepted by the grader, even if it did not make the
    prompt list.
    """
    r = _git(repo, "log", f"-n{limit}", "--format=%s")
    counts = {}
    for line in r.stdout.splitlines():
        m = re.match(r"^\[([^\]\s][^\]]*)\]", line)
        if m:
            scope = m.group(1).strip().lower()
            counts[scope] = counts.get(scope, 0) + 1
    ordered = sorted(counts, key=lambda s: (-counts[s], s))
    return ordered[:COMMIT_SCOPES_IN_PROMPT], set(ordered)


_COMMIT_FILE_STAT_RE = re.compile(r"^(.*) \(\+\d+/-\d+\)$")


def _commit_path_scopes(repo, files):
    """Scopes of recent commits that touched the changed paths, best first.

    The vocabulary says which scopes exist, not which one this diff belongs
    to, and small tiers pick the most salient entry (a crawl4ai unit came back
    as `[llm]`). The per-path history is the missing signal: the commit that
    introduced the file names its area. Grading is untouched — the bench feeds
    fixed diffs through `_commit_prompt` without this hint.
    """
    counts = {}
    for item in files:
        m = _COMMIT_FILE_STAT_RE.match(item)
        path = m.group(1) if m else item
        log = _git(repo, "log", "-5", "--format=%s", "--", path)
        for subject in log.stdout.splitlines():
            sm = re.match(r"^\[([^\]]+)\]", subject)
            if sm:
                scope = sm.group(1).strip().lower()
                counts[scope] = counts.get(scope, 0) + 1
    ordered = sorted(counts, key=lambda s: (-counts[s], s))
    return ordered[:3]


def _commit_load(repo):
    """Load the fixed cases once; missing history is a hard error, not a skip.

    A silently smaller case set would change the denominator and make two runs
    incomparable, so a rewritten history fails loudly and the case list moves
    with it.
    """
    if _git(repo, "rev-parse", "--git-dir").returncode:
        sys.exit(f"not a git repository: {repo}")
    cases = []
    for label, sha in COMMIT_CASES:
        patch = _git(repo, "show", "--format=", "--patch", sha)
        msg = _git(repo, "log", "-1", "--format=%s%n%n%b", sha)
        if patch.returncode or msg.returncode or not patch.stdout.strip():
            sys.exit(f"commit case missing: {label} {sha} in {repo}")
        subject, _, body = msg.stdout.partition("\n")
        diff = patch.stdout
        if len(diff) > COMMIT_DIFF_CHARS:
            diff = diff[:COMMIT_DIFF_CHARS] + "\n... [diff truncated]\n"
        stat = _git(repo, "show", "--format=", "--numstat", sha)
        files = []
        for line in stat.stdout.strip().splitlines():
            add, dele, path = line.split("\t", 2)
            files.append(f"{path} (+{add}/-{dele})")
        cases.append(
            {
                "label": label,
                "sha": sha,
                "diff": diff,
                "files": files,
                "gold_subject": subject.strip(),
                "gold_body": body.strip(),
            }
        )
    return cases


def _commit_prompt(
    case, scopes, with_example=False, scopes_mode="freq", path_scopes=None
):
    """Build the chat messages; `scopes_mode` controls the vocabulary hint.

    Frequency order primed small models to reuse the first entry: three
    different tiers wrote `[gui/pleamar]` for the GTK4 theme case, which is
    the most frequent scope in the log but absent from that diff. `alpha`
    keeps the vocabulary without the salience, `none` drops it entirely.

    `path_scopes` is the daily-use hint from `_commit_path_scopes`; the bench
    leaves it None so its measured prompts stay reproducible.
    """
    lines = [
        "Repository: NixOS configuration on trantor "
        "(Nix modules, shell scripts, Justfile).",
        "",
    ]
    if scopes_mode != "none":
        ordered = sorted(scopes) if scopes_mode == "alpha" else scopes
        lines.append(
            "Scopes used in this repository (vocabulary, not a suggestion — "
            "pick the one that describes the changed files): "
            + ", ".join(f"[{s}]" for s in ordered)
        )
        lines.append("")
    if path_scopes:
        lines.append(
            "Commits that touched the changed files used these scopes — "
            "prefer the closest one: "
            + ", ".join(f"[{s}]" for s in path_scopes)
        )
        lines.append("")
    lines.append("Changed files:")
    lines += ["  " + f for f in case["files"]]
    lines += ["", "Diff:", case["diff"]]
    user = "\n".join(lines)
    system = COMMIT_RULES + ("\n\n" + COMMIT_EXAMPLE if with_example else "")
    return [
        {"role": "system", "content": system},
        {"role": "user", "content": user},
    ]


_PLAN_STAT_RE = re.compile(r"\s*\(\+\d+/-\d+\)\s*$")


def _commit_plan_slices(repo, paths):
    """Return ([(path, patch), ...], omitted paths) under the plan budget.

    Grouping needs the shape of each change, so every file gets a slice of its
    patch; whatever does not fit is still listed by name in the prompt, because
    an unassigned file would make the plan invalid and the message of that
    group is written later from its own full diff.
    """
    slices, omitted, used = [], [], 0
    for path in paths:
        room = min(COMMIT_PLAN_FILE_CHARS, COMMIT_PLAN_CHARS - used)
        if room < 200:
            omitted.append(path)
            continue
        patch = _git(repo, "diff", "HEAD", "--", path).stdout
        if not patch.strip():
            omitted.append(path)
            continue
        if len(patch) > room:
            patch = patch[:room] + "\n... [truncated]\n"
        used += len(patch)
        slices.append((path, patch))
    return slices, omitted


def _commit_plan_prompt(paths, slices, omitted):
    """Ask for the grouping; the plan carries paths only, messages come later.

    Grouping needs to know which files moved together, and each group's message
    is written afterwards from that group's own diff, so this call skips the
    scope vocabulary and the examples that the message prompt carries.
    """
    lines = [
        "Repository: NixOS configuration on trantor "
        "(Nix modules, shell scripts, Justfile).",
        "",
        f"Changed files ({len(paths)}):",
    ]
    lines += ["  " + p for p in paths]
    if slices:
        lines += ["", "Per-file diffs:"]
        for path, patch in slices:
            lines += [f"=== {path} ===", patch]
    if omitted:
        lines += ["", "Diffs not shown (judge by path): " + ", ".join(omitted)]
    return [
        {"role": "system", "content": COMMIT_PLAN_RULES},
        {"role": "user", "content": "\n".join(lines)},
    ]


def _plan_resolve(raw_path, allowed):
    """Map a model-written path onto a changed path, or None if ambiguous.

    Small tiers repeat the ` (+3/-1)` stat suffix and sometimes drop leading
    directories, so both are forgiven; a bare filename is accepted only when
    exactly one changed path ends with it, otherwise the plan is rejected
    instead of guessing which file was meant.
    """
    path = _PLAN_STAT_RE.sub("", raw_path.strip().strip("\"'`")).strip()
    while path.startswith("./"):
        path = path[2:]
    if path in allowed:
        return path
    hits = [p for p in allowed if p.endswith("/" + path)]
    return hits[0] if len(hits) == 1 else None


def _json_plan_value(text, start):
    """Return (value, appended) for the first JSON value starting at `start`.

    `appended` counts the closers the reply never wrote; it is None when the
    reply stops inside a string. Small tiers close every object but forget the
    array bracket — the 4B writer does it every time — and such a reply is a
    complete plan in everything the caller can check, so the missing closers
    are appended instead of costing a repair round. A repair round is useless
    here anyway: asked to fix the JSON, the same model repeats the same
    unterminated reply. A reply that stops inside a string is cut mid-token,
    where appending would fabricate a path, so that one is refused.
    """
    stack, in_string, escaped = [], False, False
    for i in range(start, len(text)):
        ch = text[i]
        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            continue
        if ch == '"':
            in_string = True
        elif ch in "[{":
            stack.append("]" if ch == "[" else "}")
        elif ch in "]}":
            # A closer past its opener is a real syntax error; hand the slice
            # to json.loads so the problem message names the offset.
            if not stack or stack.pop() != ch:
                return text[start : i + 1], 0
            if not stack:
                return text[start : i + 1], 0
    if in_string:
        return None
    return text[start:] + "".join(reversed(stack)), len(stack)


def _commit_plan_parse(text, allowed):
    """Return (groups, problems, notes) for a planning reply.

    The plan drives `git add` paths, so validation is strict: an invented,
    dropped or repeated path would either stage the wrong content or leave a
    change behind, and both failures must abort before the first commit rather
    than surface as a half-split history. The *envelope* is tolerated down to
    a missing closing bracket (`_json_plan_value`): the path checks are what
    make a plan safe, so a forgotten `]` must not abort the split.
    """
    raw = text.strip()
    # Both bracket kinds: a plan may arrive as an array of groups or as an
    # object that wraps one. A JSON value cannot start earlier than the first
    # bracket, so the slice from the first opener to the last closer parses
    # even when the model wraps the JSON in prose.
    start = min(
        (i for i in (raw.find("["), raw.find("{")) if i >= 0), default=-1
    )
    if start < 0:
        return [], ["the reply has no JSON array"], []
    got = _json_plan_value(raw, start)
    if got is None:
        return [], ["the reply stops inside a JSON string (cut off)"], []
    payload, appended = got
    notes = []
    if appended:
        notes.append(
            f"note: the plan reply left {appended} bracket(s) unclosed; "
            "closed them before parsing"
        )
    try:
        data = json.loads(payload)
    except json.JSONDecodeError as exc:
        return [], [f"invalid JSON at offset {exc.pos}: {exc.msg}"], notes
    if isinstance(data, dict):
        # A wrapped answer (`{"groups": [...]}`) or a single group object is
        # the same plan; neither is worth a repair round.
        wrapped = next(
            (
                data[key]
                for key in ("groups", "commits", "plan")
                if isinstance(data.get(key), list)
            ),
            None,
        )
        data = wrapped if wrapped is not None else [data]
    if isinstance(data, list) and any(isinstance(x, str) for x in data):
        # A flat path list says nothing about the groups; one repair round with
        # the shape spelled out beats guessing a split.
        return [], ["each group must be an object with a files list"], notes
    if not isinstance(data, list) or not data:
        return [], ["the reply is not a non-empty array of groups"], notes
    groups, problems, seen = [], [], {}
    for idx, item in enumerate(data, 1):
        if isinstance(item, dict):
            files = item.get("files") or item.get("paths") or item.get("path")
        else:
            files = item
        if isinstance(files, str):
            files = [files]
        if not isinstance(files, list) or not files:
            problems.append(f"group {idx} has no files")
            continue
        resolved = []
        for raw_path in files:
            if not isinstance(raw_path, str):
                problems.append(
                    f"group {idx} has a non-string path: {raw_path}"
                )
                continue
            path = _plan_resolve(raw_path, allowed)
            if path is None:
                problems.append(
                    f"group {idx} names a file that did not change: {raw_path}"
                )
            elif path in seen:
                problems.append(f"{path} is in groups {seen[path]} and {idx}")
            else:
                seen[path] = idx
                resolved.append(path)
        groups.append({"files": resolved})
    missing = sorted(allowed - set(seen))
    if missing:
        problems.append("files in no group: " + ", ".join(missing))
    if len(groups) > COMMIT_PLAN_MAX_GROUPS:
        problems.append(
            f"{len(groups)} groups is more than the {COMMIT_PLAN_MAX_GROUPS} allowed"
        )
    return groups, problems, notes


class _PlanRejected(Exception):
    """The model's split plan failed validation twice."""


def _commit_plan(model, messages, allowed):
    """Ask for the split plan, with one repair round on a bad reply.

    Local tiers answer free-form or drop a file the first time, so the broken
    rule goes back into the same conversation instead of re-planning from
    scratch. Nothing is staged yet, so a rejected plan costs model time only.
    The repair round doubles the token budget: a reply cut at the cap is the
    one failure the model cannot fix by rewording, only by having more room.
    A plan that still fails raises `_PlanRejected`; only the caller knows
    whether a split was demanded or merely the default.
    """
    budget = COMMIT_PLAN_MAX_TOKENS
    for attempt in (1, 2):
        try:
            r = chat(
                model,
                messages,
                max_tokens=budget,
                cache=True,
                extra={"chat_template_kwargs": {"enable_thinking": False}},
            )
        except Exception as exc:  # noqa: BLE001
            sys.exit(f"model request failed: {exc}")
        text = _commit_clean(r["content"])
        groups, problems, notes = _commit_plan_parse(text, allowed)
        for note in notes:
            print(note, file=sys.stderr)
        if not problems:
            return groups
        if r["finish"] == "length":
            problems.append(
                f"the reply was cut at the {budget}-token cap, mid-answer"
            )
            budget *= 2
        if attempt == 2:
            print(text, file=sys.stderr)
            raise _PlanRejected("\n  ".join(problems))
        print(
            "note: repairing the split plan: " + problems[0], file=sys.stderr
        )
        messages = messages + [
            {"role": "assistant", "content": text},
            {
                "role": "user",
                "content": "That reply breaks the rules:\n- "
                + "\n- ".join(problems)
                + "\n\nReturn the corrected JSON array only.",
            },
        ]
    sys.exit("unreachable")


def _commit_clean(text):
    t = (text or "").strip()
    t = re.sub(r"^```[A-Za-z0-9_-]*\s*\n", "", t)
    t = re.sub(r"\n```\s*$", "", t)
    t = re.sub(r"^(?:commit message|message)\s*:\s*", "", t, flags=re.I)
    if len(t) >= 2 and t[0] == t[-1] and t[0] in "\"'":
        t = t[1:-1].strip()
    return t.strip()


def _commit_parse(text):
    lines = text.splitlines()
    subject = next((ln.strip() for ln in lines if ln.strip()), "")
    m = re.match(r"^\[([^\]]+)\]\s+(.+)$", subject)
    scope = m.group(1).strip().lower() if m else None
    rest = m.group(2).strip() if m else subject
    idx = next((i for i, ln in enumerate(lines) if ln.strip() == subject), -1)
    body = "\n".join(lines[idx + 1 :]).strip() if idx >= 0 else ""
    return subject, scope, rest, body


def _commit_shorten(model, messages, text, subject, max_tokens):
    """One repair round when the subject breaks the 72-character rule.

    The 8B tier overshoots by a few characters on multi-topic diffs (74 for
    the crawl4ai split proxy) even though the rule is in the system prompt;
    feeding the draft back with the measured length is cheaper than making
    every caller re-read and edit the subject.
    """
    ask = (
        messages[1]["content"]
        + "\n\nYour draft:\n"
        + text
        + f"\n\nThe first line is {len(subject)} characters long; the rule is "
        "at most 72. Rewrite the whole message with the same scope and meaning, "
        "a shorter first line, and a 2-5 sentence body. Return only the message."
    )
    r = chat(
        model,
        [messages[0], {"role": "user", "content": ask}],
        max_tokens=max_tokens,
        cache=True,
        extra={"chat_template_kwargs": {"enable_thinking": False}},
    )
    return _commit_clean(r["content"])


def _commit_condense(model, messages, text, max_tokens):
    """One repair round when the reply ran into the token cap.

    Observed 2026-11-11 with the 4B writer on a diff that is mostly
    documentation: it copied the new prose into the body instead of
    summarising it, hit COMMIT_MAX_TOKENS mid-sentence and lost the closing
    paragraph. The cap is the detectable half of the failure, and feeding the
    draft back with the length rule is cheaper than a longer budget that would
    only buy more copied prose.
    """
    ask = (
        messages[1]["content"]
        + "\n\nYour draft:\n"
        + text
        + "\n\nThat reply was cut off: the body is longer than the 2-5 "
        "sentences the rules allow. Rewrite the whole message with the same "
        "scope and subject, and a body of at most four sentences that "
        "summarises the change in your own words instead of quoting the new "
        "text. Return only the message."
    )
    r = chat(
        model,
        [messages[0], {"role": "user", "content": ask}],
        max_tokens=max_tokens,
        cache=True,
        extra={"chat_template_kwargs": {"enable_thinking": False}},
    )
    return _commit_clean(r["content"])


def _commit_grade(case, text, all_scopes):
    """Score one reply 0-10 against the real commit and the diff.

    The rubric is deliberately mechanical: a small model's message is judged
    on conventions (format, scope), on capturing the actual subject, on a body
    grounded in identifiers the diff added, and on not inventing paths. The
    full reply is kept in the results file so a human (or a judge run) can
    overrule the rubric on the cases where wording differs from history.
    """
    subject, scope, rest, body = _commit_parse(text)
    notes = []
    points = 0.0

    fmt = 0.0
    if scope:
        fmt += 1.0
    else:
        notes.append("no-scope")
    if subject and len(subject) <= 72:
        fmt += 0.5
    elif subject:
        notes.append("long-subject")
    if subject and not subject.endswith("."):
        fmt += 0.5
    else:
        notes.append("subject-period")
    if "```" in text or (text and text[:1] in "\"'" and text[-1:] == text[:1]):
        fmt = max(0.0, fmt - 0.5)
        notes.append("markdown-wrapped")
    points += fmt

    gold_subject = case["gold_subject"]
    _, gold_scope, gold_rest, _ = _commit_parse(gold_subject)
    if scope and gold_scope and scope == gold_scope:
        points += 2.0
    elif (
        scope
        and gold_scope
        and (
            scope.endswith("/" + gold_scope)
            or gold_scope.endswith("/" + scope)
            or scope.split("/")[-1] == gold_scope.split("/")[-1]
        )
    ):
        points += 1.5
        notes.append("scope-related")
    elif scope and scope in all_scopes:
        points += 1.0
        notes.append("scope-known")
    elif scope:
        notes.append("scope-unknown")

    gold_tokens = _commit_tokens(gold_rest)
    subj_tokens = _commit_tokens(rest)
    subj_recall = len(gold_tokens & subj_tokens) / max(1, len(gold_tokens))
    points += 2.0 * min(1.0, subj_recall / 0.6)
    if subj_recall < 0.3:
        notes.append("subject-off")

    body_tokens = _commit_tokens(body)
    gold_body_tokens = _commit_tokens(case["gold_body"])
    body_recall = len(gold_body_tokens & body_tokens) / max(
        1, len(gold_body_tokens)
    )
    if body:
        points += 0.5
        points += 1.0 * min(1.0, body_recall / 0.25)
    else:
        notes.append("no-body")
    diff_tokens = _commit_tokens(
        "\n".join(
            ln[1:]
            for ln in case["diff"].splitlines()
            if ln.startswith("+") and not ln.startswith("+++")
        )
    )
    grounded = body_tokens & diff_tokens
    if len(grounded) >= 2:
        points += 0.5
    else:
        notes.append("body-thin")

    mentioned = set(_COMMIT_PATH_RE.findall(text))
    invented = {p for p in mentioned if p not in case["diff"]}
    if invented:
        notes.append("invented-path:" + ",".join(sorted(invented)[:2]))
    else:
        points += 1.0
    overlap = len(subj_tokens & body_tokens) / max(
        1, len(subj_tokens | body_tokens)
    )
    if body and overlap <= 0.8:
        points += 1.0
    else:
        notes.append("body-restates-subject")

    return {
        "score": round(points, 2),
        "notes": notes,
        "scope": scope,
        "subject": subject,
        "body": body,
        "subject_recall": round(subj_recall, 2),
        "body_recall": round(body_recall, 2),
    }


def bench_commit(
    models, repo=None, with_example=False, show=False, scopes_mode="freq"
):
    """Generate a commit message for nine real diffs and grade each reply.

    `cache_prompt` stays off, matching the other benches: a warm prefix moves
    the trajectory and makes repeated runs incomparable.
    """
    started = time.time()
    repo = repo or _commit_default_repo()
    cases = _commit_load(repo)
    prompt_scopes, all_scopes = _commit_scopes(repo)
    results = {}
    print(
        f"\nCommit: {len(cases)} диффов, {len(models)} моделей, repo={repo}"
        + (" (с example)" if with_example else "")
    )
    for model in models:
        results[model] = []
        total = 0.0
        print(f"\n== {model}")
        for case in cases:
            messages = _commit_prompt(
                case, prompt_scopes, with_example, scopes_mode
            )
            try:
                r = chat(
                    model,
                    messages,
                    max_tokens=COMMIT_MAX_TOKENS,
                    cache=False,
                    extra={"chat_template_kwargs": {"enable_thinking": False}},
                )
            except Exception as exc:  # noqa: BLE001
                print(f"  {case['label']:16s} FAILED {exc}")
                results[model].append(
                    {"label": case["label"], "error": str(exc), "score": 0.0}
                )
                continue
            text = _commit_clean(r["content"])
            g = _commit_grade(case, text, all_scopes)
            total += g["score"]
            t = r["timings"]
            tps = t.get("predicted_per_second") or 0.0
            print(
                f"  {case['label']:16s} {g['score']:4.1f}  "
                f"{r['wall']:5.1f}s {tps:5.1f}t/s  "
                f"{g['subject'][:56]}"
            )
            if show:
                print(f"    gold: {case['gold_subject']}")
                print("    " + text.replace("\n", "\n    "))
                print(f"    notes: {', '.join(g['notes']) or '—'}")
            results[model].append(
                {
                    "label": case["label"],
                    "sha": case["sha"],
                    "score": g["score"],
                    "notes": g["notes"],
                    "scope": g["scope"],
                    "subject": g["subject"],
                    "body": g["body"],
                    "subject_recall": g["subject_recall"],
                    "body_recall": g["body_recall"],
                    "wall": round(r["wall"], 2),
                    "prompt_n": t.get("prompt_n"),
                    "predicted_n": t.get("predicted_n"),
                    "predicted_per_second": round(tps, 1),
                    "finish": r["finish"],
                }
            )
        results[model].append(
            {"total": round(total, 2), "of": len(cases) * 10}
        )
        print(f"  -> {total:.1f}/{len(cases) * 10}")
    _save_results(
        "commit",
        models,
        started,
        results,
        extra={
            "repo": repo,
            "example": with_example,
            "scopes": scopes_mode,
        },
    )
    return results


# ------------------------------------------------------------- commit command

# The dedicated writer: a 4B distill of the Qwen3.8 teacher (see the
# `qwen3.8-4b` slot). It beats the 8B vision tier this lane used to fall back
# to and costs a third of the VRAM, so a cold fleet loads it instead of the
# quality tier — `llmctl bench commit` is what put it here.
COMMIT_DEFAULT_MODEL = "qwen3.8-4b"

# `--model auto` reuses the resident tier only from this set: the same card
# also serves OCR, GUI-agent and k8s specialists, and handing one of those a
# diff produces a message-shaped non-answer while evicting a model that could
# have written it. Everything else swaps in COMMIT_DEFAULT_MODEL.
COMMIT_REUSE = {
    "qwen3.8-4b",
    "qwen3.8-27b-abliterated",
    "qwen3.8-27b-bartowski",
    "qwen3.8-27b-unsloth",
    "qwen3.8-flash-next-abliterated",
    "gemma4-26b-abliterated",
}


def _commit_diff(repo, staged):
    """Return (diff, files) for the message request; staged-only or HEAD."""
    base = ["--cached"] if staged else ["HEAD"]
    diff = _git(repo, "diff", *base)
    if not diff.stdout.strip():
        mode = "staged" if staged else "working tree"
        sys.exit(f"no {mode} changes to describe (git add first)")
    stat = _git(repo, "diff", "--numstat", *base)
    files = []
    for line in stat.stdout.strip().splitlines():
        add, dele, path = line.split("\t", 2)
        files.append(f"{path} (+{add}/-{dele})")
    untracked = _git(repo, "ls-files", "--others", "--exclude-standard")
    if untracked.stdout.strip():
        print(
            "note: untracked files are not in the diff: "
            + ", ".join(untracked.stdout.split()[:5]),
            file=sys.stderr,
        )
    return diff.stdout, files


def _commit_message(args, repo, model, case, scopes):
    """Ask for one commit message and repair a cut-off or over-long subject.

    Shared by the single-commit path and every group of `--split`, so both get
    the same prompt, the same examples, the same token-cap condense round and
    the same 72-character repair round.
    """
    messages = _commit_prompt(
        case,
        scopes,
        args.example,
        args.scopes,
        _commit_path_scopes(repo, case["files"]),
    )
    try:
        r = chat(
            model,
            messages,
            max_tokens=args.max,
            cache=True,
            extra={"chat_template_kwargs": {"enable_thinking": False}},
        )
    except Exception as exc:  # noqa: BLE001
        sys.exit(f"model request failed: {exc}")
    text = _commit_clean(r["content"])
    if r["finish"] == "length":
        try:
            condensed = _commit_condense(model, messages, text, args.max)
        except Exception as exc:  # noqa: BLE001
            print(f"note: condense retry failed: {exc}", file=sys.stderr)
        else:
            if _commit_parse(condensed)[0]:
                text = condensed
                print(
                    "note: reply hit the token cap, asked for a shorter body",
                    file=sys.stderr,
                )
    subject = _commit_parse(text)[0]
    if len(subject) > 72:
        try:
            fixed = _commit_shorten(model, messages, text, subject, args.max)
        except Exception as exc:  # noqa: BLE001
            print(f"note: shorten retry failed: {exc}", file=sys.stderr)
        else:
            fixed_subject = _commit_parse(fixed)[0]
            if fixed_subject and len(fixed_subject) <= 72:
                text = fixed
            else:
                print(
                    f"note: subject still {len(fixed_subject)} chars "
                    "(rule: at most 72)",
                    file=sys.stderr,
                )
    if args.verbose:
        t = r["timings"]
        print(
            f"({model}: {r['wall']:.1f}s, {t.get('prompt_n')} prompt, "
            f"{t.get('predicted_n')} out, "
            f"{t.get('predicted_per_second') or 0:.1f} tok/s)",
            file=sys.stderr,
        )
    return text


def _commit_reset(repo, paths):
    """Drop the intent-to-add entries `--all` created; no-op without them."""
    if paths:
        subprocess.run(
            ["git", "-C", repo, "reset", "-q", "--", *paths], check=False
        )


def _commit_head_paths(repo):
    """Paths changed against HEAD: staged and working tree, not untracked.

    Rename detection is off on purpose: with it on `--name-only` reports only
    the new half, and the deletion then either rides into whichever commit
    happens first or is left behind. Both halves are listed instead, and
    `_commit_plan_merge_renames` keeps the pair in one group so git still
    records a rename.
    """
    out = _git(repo, "diff", "--name-only", "--no-renames", "HEAD").stdout
    return [p for p in out.splitlines() if p]


def _commit_group_case(repo, paths):
    """Diff and numstat of one planned group, capped like a single commit."""
    diff = _git(repo, "diff", "HEAD", "--", *paths).stdout
    if len(diff) > COMMIT_DIFF_CHARS:
        diff = diff[:COMMIT_DIFF_CHARS] + "\n... [diff truncated]\n"
    stat = _git(repo, "diff", "--numstat", "HEAD", "--", *paths).stdout
    files = []
    for line in stat.strip().splitlines():
        add, dele, path = line.split("\t", 2)
        files.append(f"{path} (+{add}/-{dele})")
    return {"diff": diff, "files": files}


def _commit_rename_pairs(repo, paths):
    """Return (old, new) pairs with identical content, i.e. renames.

    With rename detection off, a rename arrives as a deletion plus an addition
    of the same bytes; matching them by blob hash is what lets the plan keep
    the pair together without asking the model to guess.
    """
    head = set(
        _git(repo, "ls-tree", "-r", "--name-only", "HEAD").stdout.splitlines()
    )
    added = [p for p in paths if p not in head]
    pairs = []
    for old in (p for p in paths if p in head):
        if os.path.exists(os.path.join(repo, old)):
            continue
        old_blob = _git(repo, "rev-parse", f"HEAD:{old}").stdout.strip()
        if not old_blob:
            continue
        for new in added:
            blob = _git(repo, "hash-object", "--", new).stdout.strip()
            if blob and blob == old_blob:
                pairs.append((old, new))
                break
    return pairs


def _commit_plan_merge_renames(repo, groups, paths):
    """Move both halves of a rename into one group, in place.

    The plan is already validated, so this only changes membership; a split
    rename would leave a deletion whose replacement commits later, or - when a
    half is dropped - a file that looks deleted for good.
    """
    where = {p: i for i, g in enumerate(groups) for p in g["files"]}
    for old, new in _commit_rename_pairs(repo, paths):
        src, dst = where.get(old), where.get(new)
        if src is None or dst is None or src == dst:
            continue
        groups[src]["files"].remove(old)
        groups[dst]["files"].append(old)
        where[old] = dst
        print(
            f"note: kept the rename {old} -> {new} in one commit",
            file=sys.stderr,
        )
    # A group can lose its only file to the merge; an empty group must not
    # reach the staging loop, where a bare `git add -A --` would stage the
    # whole tree.
    return [g for g in groups if g["files"]]


def _commit_staged_paths(repo):
    """Paths staged against HEAD."""
    return {
        p
        for p in _git(
            repo, "diff", "--cached", "--name-only", "--no-renames", "HEAD"
        ).stdout.splitlines()
        if p
    }


def _commit_partially_staged(repo):
    """Paths staged yet changed again since, i.e. a hand-picked hunk set.

    A path that is merely staged (all of it) or merely dirty carries no
    decision a reset would throw away; one that is both was selected by hand
    with `git add -p`, and such a selection cannot be regrouped by file.
    """
    staged = _commit_staged_paths(repo)
    if not staged:
        return []
    return sorted(
        staged
        & {
            p
            for p in _git(repo, "diff", "--name-only").stdout.splitlines()
            if p
        }
    )


def _commit_unstage(repo):
    """Clear the index so the split stages each group from the worktree.

    The split commits whole files, so an index that mirrors the worktree holds
    nothing the split would not stage itself. An index that does *not* mirror
    it is the user's decision (a `git add -p` selection) and resetting it would
    silently change what gets committed, so that case aborts with the fix in
    the message instead.
    """
    renames = []
    for line in _git(
        repo, "diff", "--cached", "--name-status", "-M", "HEAD"
    ).stdout.splitlines():
        parts = line.split("\t")
        if len(parts) > 2 and parts[0].startswith("R"):
            renames.append(parts[2])
    if renames:
        # git keeps both halves of a rename in the index, so unstaging it would
        # leave the new path untracked and turn the commit into a bare deletion
        # of the old one. The remedy keeps the pair together under --all.
        sys.exit(
            "--split cannot split a staged rename: unstaging it would leave "
            "the new path untracked ("
            + ", ".join(renames)
            + "). Run `git reset` and then --all, or commit it "
            "with --staged and --no-split."
        )
    both = _commit_partially_staged(repo)
    if both:
        sys.exit(
            "the split commits whole files from the working tree, but these "
            "files are staged and changed again since (a partially staged "
            "file): "
            + ", ".join(both)
            + ". Run `git reset` first, or commit them with --staged and "
            "--no-split."
        )
    if not _commit_staged_paths(repo):
        return
    reset = _git(repo, "reset", "-q")
    if reset.returncode:
        sys.exit(f"git reset failed: {reset.stderr.strip()}")
    print(
        "note: unstaged the index; the split stages every group itself",
        file=sys.stderr,
    )


def _commit_paths(files):
    """Strip the ` (+3/-1)` stat suffix that `case["files"]` carries.

    The suffix is appended by this module, so the last ` (` is the split point;
    a binary file reads ` (+-/-)` and must survive the same way as a text one.
    """
    out = []
    for item in files:
        path, sep, stat = item.rpartition(" (")
        out.append(path if sep and stat.endswith(")") else item)
    return out


def _pid_alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _commit_unlock(path):
    try:
        os.unlink(path)
    except OSError:
        pass


def _commit_lock(repo):
    """Take the per-repository commit lock; exit naming the other run.

    Every commit path reads and writes the index, and `--split` keeps it
    staged across the pre-commit hook, which runs the whole lint devshell and
    takes tens of seconds, so two runs overlap for whole seconds. Overlap
    corrupts: one run's `git reset` clears the index while the other sits in
    `git commit`, and git then records an *empty* commit with the right
    message and leaves the change in the worktree. Reproduced on this
    repository on 2026-11-12 — an empty `[cli/broot]` commit with two files
    still modified. The pid in the file keeps a crash from wedging the
    repository: a lock whose process is gone is taken over, not honoured.
    """
    gitdir = _git(repo, "rev-parse", "--absolute-git-dir").stdout.strip()
    path = os.path.join(gitdir, "llmctl-commit.lock")
    for _ in range(2):
        try:
            fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
        except FileExistsError:
            try:
                with open(path) as handle:
                    pid = int(handle.read().split()[0])
            except (OSError, ValueError, IndexError):
                pid = 0
            if pid and _pid_alive(pid):
                sys.exit(
                    f"another llmctl commit is running in {repo} (pid {pid}); "
                    f"wait for it, or remove {path} if that process is gone"
                )
            os.unlink(path)
            continue
        with os.fdopen(fd, "w") as handle:
            handle.write(f"{os.getpid()}\n")
        atexit.register(_commit_unlock, path)
        return path
    sys.exit(f"could not take the commit lock {path}")


def _commit_verify(repo, files, label):
    """Abort when HEAD does not hold exactly the files just committed.

    A zero exit from `git commit` is not proof of content: the pre-commit hook
    runs for tens of seconds, and anything that touches the index in that
    window makes git record an empty or shifted commit under the intended
    message. Checking the recorded tree turns that silent drop into a stop
    right after the first bad commit, while the message is still on screen.
    Renames are listed as both halves, matching how the plan builds groups.
    """
    out = _git(
        repo,
        "diff-tree",
        "--no-commit-id",
        "-r",
        "--name-only",
        "--no-renames",
        "HEAD",
    )
    got = {p for p in out.stdout.splitlines() if p}
    missing = sorted(set(files) - got)
    extra = sorted(got - set(files))
    if not missing and not extra:
        return
    detail = []
    if missing:
        detail.append("missing " + ", ".join(missing))
    if extra:
        detail.append("unexpected " + ", ".join(extra))
    sys.exit(
        f"{label}: HEAD does not match the files of this commit "
        f"({'; '.join(detail) or 'empty commit'}); the message above describes "
        "a tree that is not in history — inspect `git log -1 --stat` and the "
        "working tree before continuing"
    )


def _commit_split(args, repo, model, scopes, new_files):
    """Make the several commits the model groups the pending change into.

    Only whole files are grouped: a path with two unrelated edits stays one
    commit, because committing a subset of a file's hunks needs `git add -p`
    state that llmctl does not own. The plan is validated before anything is
    staged, so a rejected plan leaves the repository untouched; a failing
    commit stops the run instead of re-planning against a half-split history.
    """
    paths = _commit_head_paths(repo)
    if not paths:
        _commit_reset(repo, new_files)
        sys.exit("no working tree changes to split")
    if not args.all:
        untracked = _git(repo, "ls-files", "--others", "--exclude-standard")
        if untracked.stdout.strip():
            print(
                "note: untracked files are not in the split "
                "(--all adds them): "
                + ", ".join(untracked.stdout.split()[:5]),
                file=sys.stderr,
            )
    if len(paths) == 1:
        groups = [{"files": paths}]
    else:
        slices, omitted = _commit_plan_slices(repo, paths)
        messages = _commit_plan_prompt(paths, slices, omitted)
        groups = _commit_plan(model, messages, set(paths))
    groups = _commit_plan_merge_renames(repo, groups, paths)
    if not groups:
        _commit_reset(repo, new_files)
        sys.exit("the split plan has no groups; nothing committed")
    total = len(groups)
    print(
        f"split plan: {total} commit(s) over {len(paths)} file(s)",
        file=sys.stderr,
    )
    for i, group in enumerate(groups, 1):
        print(f"  {i}. {', '.join(group['files'])}", file=sys.stderr)
    done = 0
    for i, group in enumerate(groups, 1):
        files = group["files"]
        case = _commit_group_case(repo, files)
        if not case["diff"].strip():
            print(
                f"note: group {i} has no pending diff left; skipped",
                file=sys.stderr,
            )
            continue
        text = _commit_message(args, repo, model, case, scopes)
        if not text.strip():
            sys.exit(f"empty message for group {i}/{total}; nothing committed")
        print(f"--- {i}/{total}: {', '.join(files)}", flush=True)
        print(text, flush=True)
        if args.dry_run:
            done += 1
            continue
        add = subprocess.run(
            ["git", "-C", repo, "add", "-A", "--", *files],
            capture_output=True,
            text=True,
        )
        if add.returncode:
            sys.exit(
                f"git add failed for group {i}/{total}: {add.stderr.strip()}"
            )
        staged = {
            p
            for p in _git(
                repo, "diff", "--cached", "--name-only", "--no-renames", "HEAD"
            ).stdout.splitlines()
            if p
        }
        if staged != set(files):
            # A message must never describe a tree the commit does not contain.
            sys.exit(
                f"group {i}/{total} staged the wrong files "
                f"(staged: {', '.join(sorted(staged)) or '-'}); nothing committed"
            )
        proc = subprocess.run(
            ["git", "-C", repo, "commit", "-F", "-"], input=text, text=True
        )
        if proc.returncode:
            sys.exit(
                f"git commit failed for group {i}/{total}: {done} earlier "
                f"commit(s) kept; {total - i} group(s) still pending"
            )
        _commit_verify(repo, files, f"group {i}/{total}")
        done += 1
    if args.dry_run:
        _commit_reset(repo, new_files)
        print(
            f"note: dry run, {done} commit(s) planned, nothing committed",
            file=sys.stderr,
        )
        return
    print(f"committed {done} of {total} planned commit(s)", file=sys.stderr)


def _commit_mode(args, repo):
    """Return (split, required) for this run.

    Splitting is the default because several unrelated changes are the daily
    case, and one message stretched over all of them is exactly what reads as
    wrong: the model groups the files and every group gets its own message.
    The two modes that cannot be regrouped stay a single commit — `--staged`
    commits the index as it is, and a hand-picked hunk set (`git add -p`, a
    file staged and edited again) would lose its selection to the per-file
    staging — and the default says so on stderr instead of changing what gets
    committed silently. `--split` states the intent, so a rejected plan is an
    error there; `--no-split` asks for one commit and never plans.
    """
    if args.split is True:
        if args.staged:
            sys.exit(
                "--split cannot describe the index: each group is staged and "
                "committed by path, and such a commit takes the working tree "
                "version of the file. Run --split without --staged."
            )
        return True, True
    if args.split is False or args.staged:
        return False, False
    both = _commit_partially_staged(repo)
    if both:
        print(
            "note: these files are staged and changed again since, so the "
            "hunks were picked by hand and cannot be regrouped; committing "
            "the working tree as one change: " + ", ".join(both),
            file=sys.stderr,
        )
        return False, False
    return True, False


def cmd_commit(args):
    repo = args.repo or os.getcwd()
    if _git(repo, "rev-parse", "--git-dir").returncode:
        sys.exit(f"not a git repository: {repo}")
    if args.all and args.staged:
        sys.exit("--all and --staged are mutually exclusive")
    if args.apply:
        print(
            "note: committing is the default now; --apply is redundant",
            file=sys.stderr,
        )
    split, split_required = _commit_mode(args, repo)
    # `auto` keeps a resident text tier, so a commit message does not evict the
    # model the user is actually working with; anything that is not a writer
    # (vision, OCR, GUI agent, k8s specialist) is the wrong tool even warm, so
    # a cold or busy fleet falls back to the dedicated 4B writer.
    if args.model == "auto":
        live = running()
        resident = live[0]["model"] if live else None
        model = resident if resident in COMMIT_REUSE else COMMIT_DEFAULT_MODEL
    else:
        model = resolve(args.model) or args.model
    # Everything from here on mutates the index; a second run in the same
    # repository must not interleave with it (see _commit_lock).
    _commit_lock(repo)
    if split:
        # The split commits whole files from the working tree, so a staged
        # index adds nothing it would not stage itself — and a leftover entry
        # would be swept into the first group. Cleared here, while that is
        # lossless (a partially staged file never reaches this point: the
        # default falls back on it and `--split` aborts, see _commit_unstage).
        _commit_unstage(repo)
    new_files = []
    if args.all:
        # `git diff HEAD` cannot see untracked files: intent-to-add puts them
        # in the index with an empty blob so the message describes them too.
        # The real staging happens right before the commit; --dry-run restores
        # the files to untracked instead of leaving the index touched.
        raw = _git(
            repo, "ls-files", "-z", "--others", "--exclude-standard"
        ).stdout
        new_files = [p for p in raw.split("\0") if p]
        if new_files:
            add = subprocess.run(
                ["git", "-C", repo, "add", "-N", "--", *new_files],
                capture_output=True,
                text=True,
            )
            if add.returncode:
                sys.exit(f"git add -N failed: {add.stderr.strip()}")
    scopes, _ = _commit_scopes(repo)
    if split:
        try:
            _commit_split(args, repo, model, scopes, new_files)
            return
        except _PlanRejected as exc:
            if split_required:
                sys.exit("split plan rejected:\n  " + str(exc))
            print(
                "note: the model could not group this change ("
                + str(exc).replace("\n", "; ")
                + "); committing it as one",
                file=sys.stderr,
            )
    diff, files = _commit_diff(repo, args.staged)
    if len(diff) > COMMIT_DIFF_CHARS:
        diff = diff[:COMMIT_DIFF_CHARS] + "\n... [diff truncated]\n"
    case = {"diff": diff, "files": files}
    text = _commit_message(args, repo, model, case, scopes)
    print(text, flush=True)
    if args.dry_run:
        _commit_reset(repo, new_files)
        return
    # The message describes `git diff HEAD` (or the index with --staged), so
    # stage exactly the tracked working-tree changes it describes. Untracked
    # files are reported by _commit_diff and never swept in by `git add -u`;
    # --all adds them explicitly with `git add -A`.
    if args.staged:
        if _git(repo, "diff", "--cached", "--quiet").returncode == 0:
            sys.exit("nothing staged; git add the files to commit first")
    else:
        stage = ["add", "-A"] if args.all else ["add", "-u"]
        add = subprocess.run(
            ["git", "-C", repo, *stage],
            capture_output=True,
            text=True,
        )
        if add.returncode:
            sys.exit(f"git {stage[0]} failed: {add.stderr.strip()}")
    proc = subprocess.run(
        ["git", "-C", repo, "commit", "-F", "-"],
        input=text,
        text=True,
    )
    if proc.returncode:
        sys.exit(proc.returncode)
    _commit_verify(repo, _commit_paths(files), "commit")


# ----------------------------------------------------------------------- menu


def pick_model(prompt="Модель: "):
    names = list(CATALOG)
    if not shutil.which("fzf"):
        for i, n in enumerate(names, 1):
            print(f"{i}) {n}")
        try:
            return names[int(input("номер> ")) - 1]
        except (ValueError, IndexError):
            return None
    sel = subprocess.run(
        ["fzf", "--prompt", prompt],
        input="\n".join(names),
        capture_output=True,
        text=True,
    )
    return sel.stdout.strip() or None


def cmd_menu(_args):
    actions = [
        "status",
        "models",
        "use model…",
        "unload",
        "bench chem",
        "bench lean",
        "bench fp",
        "bench commit",
    ]
    if not shutil.which("fzf"):
        sys.exit("fzf not installed")
    sel = subprocess.run(
        ["fzf", "--prompt", "llmctl> "],
        input="\n".join(actions),
        capture_output=True,
        text=True,
    ).stdout.strip()
    if not sel:
        return
    if sel == "status":
        print_status()
    elif sel == "models":
        print_models()
    elif sel == "use model…":
        cmd_use(argparse.Namespace(name=pick_model()))
    elif sel == "unload":
        cmd_unload(None)
    elif sel == "bench chem":
        bench_chem(select_models(None))
    elif sel == "bench lean":
        bench_lean(select_models(None))
    elif sel == "bench fp":
        bench_fp(select_models(None))
    elif sel == "bench commit":
        bench_commit(
            [m for m in COMMIT_MODELS if m in model_names()],
            show=True,
        )


def select_models(spec):
    if spec:
        out = [resolve(x.strip()) for x in spec.split(",")]
        bad = [x for x in out if not x]
        if bad:
            sys.exit(f"unknown models: {bad}")
        return out
    return [m for m in CATALOG if m in model_names()]


# ----------------------------------------------------------------------- main


def main():
    p = argparse.ArgumentParser(
        prog="llmctl",
        description="Управление локальным llama-swap флотом и бенчмарки.",
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("status", help="что запущено, VRAM, модели")
    sub.add_parser("models", help="каталог моделей и результаты")
    s = sub.add_parser("use", help="загрузить модель (или выбрать в fzf)")
    s.add_argument("name", nargs="?")
    sub.add_parser("unload", help="выгрузить текущую модель")
    s = sub.add_parser(
        "prewarm", help="прогреть page cache модели, не трогая GPU"
    )
    s.add_argument("model", nargs="?", default="vision")
    s.add_argument(
        "--check",
        action="store_true",
        help="только показать, сколько уже в памяти",
    )
    s = sub.add_parser("ask", help="один вопрос модели")
    s.add_argument("model")
    s.add_argument("text")
    s.add_argument(
        "--chem", action="store_true", help="включить химический system prompt"
    )
    # The thinking tiers serve with a reasoning budget, so the cap has to leave
    # room for thoughts plus the answer; a 1024 default would cut every hard
    # question off mid-thinking and return an empty `content`.
    s.add_argument("--max", type=int, default=8192)
    s.add_argument("--temp", type=float, default=0.0)
    s = sub.add_parser("commit", help="commit message по git diff и коммит")
    s.add_argument(
        "--staged", action="store_true", help="описывать только индекс"
    )
    s.add_argument(
        "--all",
        action="store_true",
        help="включить новые (untracked) файлы, как git commit -a + новые",
    )
    s.add_argument(
        "--split",
        action=argparse.BooleanOptionalAction,
        default=None,
        help="разбить изменение на логические коммиты; по умолчанию — авто "
        "(несколько несвязанных изменений дают несколько коммитов), "
        "--no-split — один коммит на всё",
    )
    s.add_argument(
        "--model",
        default="auto",
        help="модель; auto = резидент-писатель, иначе qwen3.8-4b (commit)",
    )
    s.add_argument("--repo", help="репозиторий (по умолчанию cwd)")
    s.add_argument(
        "--dry-run",
        action="store_true",
        help="только напечатать сообщение, ничего не коммитить",
    )
    s.add_argument(
        "--apply",
        action="store_true",
        help="устарело: коммит теперь по умолчанию",
    )
    # The example is on by default: without it the small tiers dropped the
    # body or glued it to the subject, and it was worth ~3 points on the 8B
    # (`.agent/notes/2026-11-09-commit-bench.md`). It costs ~120 prompt tokens.
    s.add_argument(
        "--example",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="one-shot пример в system prompt (--no-example, чтобы убрать)",
    )
    s.add_argument("--max", type=int, default=COMMIT_MAX_TOKENS)
    s.add_argument("--verbose", action="store_true", help="тайминги в stderr")
    s.add_argument(
        "--scopes",
        choices=["freq", "alpha", "none"],
        default="freq",
        help="порядок списка scopes (freq/alpha) или без него",
    )
    s = sub.add_parser("bench", help="бенчмарки")
    s.add_argument("kind", choices=["chem", "lean", "fp", "commit", "all"])
    s.add_argument("--models", help="список через запятую (имя или alias)")
    s.add_argument(
        "--prompt", action="store_true", help="chem: с system prompt"
    )
    s.add_argument(
        "--thinking",
        action="store_true",
        help="fp: оставить раздумья модели (медленно, но честно)",
    )
    s.add_argument(
        "--repo",
        help="commit: git-репозиторий с историей (по умолчанию /etc/nixos)",
    )
    s.add_argument(
        "--example",
        action="store_true",
        help="commit: добавить one-shot пример в system prompt",
    )
    s.add_argument(
        "--show",
        action="store_true",
        help="commit: печатать ответ, gold и заметки",
    )
    s.add_argument(
        "--scopes",
        choices=["freq", "alpha", "none"],
        default="freq",
        help="commit: порядок списка scopes (freq/alpha) или без него",
    )
    sub.add_parser("menu", help="интерактивное меню (fzf)")

    args = p.parse_args()
    if args.cmd == "status":
        print_status()
    elif args.cmd == "models":
        print_models()
    elif args.cmd == "use":
        cmd_use(args)
    elif args.cmd == "unload":
        cmd_unload(args)
    elif args.cmd == "prewarm":
        cmd_prewarm(args)
    elif args.cmd == "ask":
        cmd_ask(args)
    elif args.cmd == "commit":
        cmd_commit(args)
    elif args.cmd == "menu":
        cmd_menu(args)
    elif args.cmd == "bench":
        if args.kind == "commit" and not args.models:
            models = [m for m in COMMIT_MODELS if m in model_names()]
        else:
            models = select_models(args.models)
        if args.kind in ("chem", "all"):
            bench_chem(models, use_prompt=args.prompt)
        if args.kind in ("lean", "all"):
            bench_lean(models)
        if args.kind in ("fp", "all"):
            bench_fp(models, thinking=args.thinking)
        if args.kind == "commit":
            bench_commit(
                models,
                repo=args.repo,
                with_example=args.example,
                show=args.show,
                scopes_mode=args.scopes,
            )


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""llmctl — one entry point for the local llama-swap fleet.

Subcommands cover the daily loop: see what is loaded, switch models, ask a
one-shot question, and run the chemistry/Lean benchmarks. The model catalog
carries the measured scores so `llmctl models` answers "which one for what".
"""

import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

BASE = os.environ.get("LLMCTL_URL", "http://127.0.0.1:9292")
STATE = os.path.expanduser("~/.local/state/llmctl")

# Measured on trantor 2026-11-05: chem = six olympiad problems (13 values),
# lean = seven core-Lean theorems (7 tasks).
CATALOG = {
    "gpt-oss-20b-abliterated": {
        "aliases": ["gpt-oss", "gpt-oss-20b", "uncensored"],
        "role": "tools / reasoning / Lean",
        "ctx": "64k",
        "size": "12 GB",
        "chem": "7/13",
        "lean": "6/7",
    },
    "gemma4-26b-abliterated": {
        "aliases": ["gemma4", "gemma4-26b"],
        "role": "26B-A4B MoE, creative",
        "ctx": "32k",
        "size": "12 GB",
        "chem": "12/13",
        "lean": "2/7",
    },
    "qwen3.6-35b-abliterated": {
        "aliases": ["strong", "qwen3.6"],
        "role": "strong general / chemistry",
        "ctx": "64k",
        "size": "12 GB",
        "chem": "13/13",
        "lean": "1/7",
    },
    "qwen3-vl-8b-abliterated": {
        "aliases": ["vision", "vision-8b", "qwen3-vl-8b"],
        "role": "fast / vision / chemistry",
        "ctx": "32k",
        "size": "5 GB",
        "chem": "13/13",
        "lean": "0/7",
    },
    "qwen3.8-27b-abliterated": {
        "aliases": ["qwen3.8", "ru"],
        "role": "dense 27B quality",
        "ctx": "24k",
        "size": "11 GB",
        "chem": "12/13",
        "lean": "4/7",
    },
    "qwen3.5-4b-abliterated": {
        "aliases": ["qwen3.5", "quick"],
        "role": "dense 4B Q8, long ctx",
        "ctx": "256k",
        "size": "12 GB",
        "chem": "4/13",
        "lean": "0/7",
    },
    "tiny": {
        "aliases": ["cheap", "spark-cpu"],
        "role": "CPU-only fallback",
        "ctx": "64k",
        "size": "2.6 GB",
        "chem": "-",
        "lean": "-",
    },
    "gpt-oss-120b-abliterated": {
        "aliases": ["gpt-oss-120", "big"],
        "role": "120B-A5B MoE, RAM tier",
        "ctx": "16k",
        "size": "63 GB",
        "chem": "-",
        "lean": "-",
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


def api(path, payload=None, timeout=900):
    url = BASE + path
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        url, data=data, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read()
    return json.loads(raw) if raw else {}


def chat(model, messages, max_tokens=1024, temperature=0, cache=True):
    body = {
        "model": model,
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": temperature,
    }
    if not cache:
        body["cache_prompt"] = False
    t0 = time.perf_counter()
    d = api("/v1/chat/completions", body)
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
        dev, total = card
        try:
            used = int(
                open(os.path.join(dev, "mem_info_vram_used")).read().strip()
            )
            print(f"VRAM        {fmt_gib(used)} / {fmt_gib(total)} GiB")
        except OSError:
            pass
    try:
        live = model_names()
        print(f"models      {len(live)}: " + ", ".join(live))
    except Exception:
        print("models      unavailable")


def print_models():
    live = set(model_names())
    print(
        f"{'NAME':32s} {'ROLE':28s} {'CTX':>4s} {'VRAM':>6s} {'CHEM':>6s} {'LEAN':>5s}  ALIASES"
    )
    for name, meta in CATALOG.items():
        mark = "*" if name in live else " "
        print(
            f"{mark}{name:31s} {meta['role']:28s} {meta['ctx']:>4s} "
            f"{meta['size']:>6s} {meta['chem']:>6s} {meta['lean']:>5s}  "
            f"{', '.join(meta['aliases'])}"
        )
    print(
        "\n* = present in the live catalog. Scores are measured on trantor; "
        "chem = 6 olympiad problems, lean = 7 core-Lean theorems."
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


def cmd_unload(_args):
    # llama-swap answers /unload with the plain text "OK", not JSON, so this
    # bypasses api(); POST is rejected with 405, GET is the form the game
    # guard uses too.
    try:
        with urllib.request.urlopen(BASE + "/unload", timeout=15) as resp:
            resp.read()
    except Exception as exc:  # noqa: BLE001
        sys.exit(f"unload failed: {exc}")
    time.sleep(1)
    print("unloaded")
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


def bench_chem(models, use_prompt=False):
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
    os.makedirs(STATE, exist_ok=True)
    path = os.path.join(STATE, f"chem-{int(time.time())}.json")
    with open(path, "w") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    print(f"\nsaved {path}")
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
    os.makedirs(STATE, exist_ok=True)
    path = os.path.join(STATE, f"lean-{int(time.time())}.json")
    with open(path, "w") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    print(f"\nsaved {path}")
    return results


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
    s = sub.add_parser("ask", help="один вопрос модели")
    s.add_argument("model")
    s.add_argument("text")
    s.add_argument(
        "--chem", action="store_true", help="включить химический system prompt"
    )
    s.add_argument("--max", type=int, default=1024)
    s.add_argument("--temp", type=float, default=0.0)
    s = sub.add_parser("bench", help="бенчмарки")
    s.add_argument("kind", choices=["chem", "lean", "all"])
    s.add_argument("--models", help="список через запятую (имя или alias)")
    s.add_argument(
        "--prompt", action="store_true", help="chem: с system prompt"
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
    elif args.cmd == "ask":
        cmd_ask(args)
    elif args.cmd == "menu":
        cmd_menu(args)
    elif args.cmd == "bench":
        models = select_models(args.models)
        if args.kind in ("chem", "all"):
            bench_chem(models, use_prompt=args.prompt)
        if args.kind in ("lean", "all"):
            bench_lean(models)


if __name__ == "__main__":
    main()

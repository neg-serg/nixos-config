#!/usr/bin/env python3
"""Audit a UI colour palette for readability and colour-perception quality.

Standard library only. The tool answers three questions about a palette:

1. Can each foreground be read on each surface it is painted on? (WCAG 2.1 contrast.)
2. Are two colours that mean different things actually different *perceptually*?
   (Euclidean distance in OKLab and CIEDE2000 in CIELAB.)
3. Does the palette survive colour-vision deficiency? (Machado 2009 matrices,
   severity 1.0, applied in linear light, contrast and distance recomputed.)

Usage:

    python3 theme_audit.py tokens.json [--pairs pairs.json] [--md report.md]
                            [--json out.json] [--top N] [--selftest]

`tokens.json` is a flat object of names to hex colours, optionally nested one level
(`{"surface": {"bg": "#000000"}, ...}` flattens to `surface.bg`). Both `#rrggbb` and
`#rrggbbaa` are accepted; alpha is composited over the `--bg` token (default: the first
token whose name contains "bg").

Exit status: 0 when every constraint holds, 1 when a pair with an explicit `min`
requirement is violated, 2 on a usage/parse error.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass
from typing import Iterable, Sequence

# --------------------------------------------------------------------------- sRGB

# All colour maths below works on linear-light channel triples in 0..1. sRGB is only
# used at the boundaries (parsing hex, printing hex, simulating CVD), because every
# perceptual model here is defined on linear light.


def srgb_decode(c: float) -> float:
    """sRGB transfer function, encoded -> linear."""
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


def srgb_encode(c: float) -> float:
    """Linear -> sRGB encoded, clamped to the representable range."""
    c = min(max(c, 0.0), 1.0)
    if c <= 0.0031308:
        return c * 12.92
    return 1.055 * (c ** (1.0 / 2.4)) - 0.055


def hex_to_rgb(text: str) -> tuple[float, float, float]:
    """`#rgb`, `#rrggbb` or `#rrggbbaa` -> sRGB floats in 0..1 (alpha dropped)."""
    s = text.strip().lstrip("#")
    if len(s) == 3:
        s = "".join(ch * 2 for ch in s)
    if len(s) not in (6, 8):
        raise ValueError(f"not a hex colour: {text!r}")
    r, g, b = (int(s[i : i + 2], 16) / 255.0 for i in (0, 2, 4))
    return (r, g, b)


def rgb_to_hex(rgb: Sequence[float]) -> str:
    return "#" + "".join(f"{round(min(max(c, 0.0), 1.0) * 255):02x}" for c in rgb[:3])


def to_linear(rgb: Sequence[float]) -> tuple[float, float, float]:
    return (srgb_decode(rgb[0]), srgb_decode(rgb[1]), srgb_decode(rgb[2]))


def from_linear(lin: Sequence[float]) -> tuple[float, float, float]:
    return (srgb_encode(lin[0]), srgb_encode(lin[1]), srgb_encode(lin[2]))


# --------------------------------------------------------------------------- luminance


def relative_luminance(rgb: Sequence[float]) -> float:
    """WCAG 2.1 relative luminance of an sRGB colour."""
    r, g, b = to_linear(rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast_ratio(fg: Sequence[float], bg: Sequence[float]) -> float:
    """WCAG 2.1 contrast ratio, always >= 1, order-independent."""
    l1 = relative_luminance(fg)
    l2 = relative_luminance(bg)
    hi, lo = max(l1, l2), min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


# --------------------------------------------------------------------------- CIELAB

_XYZ_D65 = (
    (0.4124564, 0.3575761, 0.1804375),
    (0.2126729, 0.7151522, 0.0721750),
    (0.0193339, 0.1191920, 0.9503041),
)
_WHITE_D65 = (0.95047, 1.0, 1.08883)
_LAB_KNEE = (6.0 / 29.0) ** 3


def _lab_f(t: float) -> float:
    if t > _LAB_KNEE:
        return t ** (1.0 / 3.0)
    return t / (3.0 * (6.0 / 29.0) ** 2) + 4.0 / 29.0


def linear_to_xyz(lin: Sequence[float]) -> tuple[float, float, float]:
    r, g, b = lin
    return tuple(
        _XYZ_D65[i][0] * r + _XYZ_D65[i][1] * g + _XYZ_D65[i][2] * b for i in range(3)
    )  # type: ignore[return-value]


def to_lab(rgb: Sequence[float]) -> tuple[float, float, float]:
    """sRGB -> CIELAB with a D65 white point."""
    x, y, z = linear_to_xyz(to_linear(rgb))
    fx, fy, fz = (_lab_f(x / _WHITE_D65[0]), _lab_f(y / _WHITE_D65[1]), _lab_f(z / _WHITE_D65[2]))
    return (116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


# --------------------------------------------------------------------------- OKLab

_OK_M1 = (
    (0.4122214708, 0.5363325363, 0.0514459929),
    (0.2119034982, 0.6806995451, 0.1073969566),
    (0.0883024619, 0.2817188376, 0.6299787005),
)
_OK_M2 = (
    (0.2104542553, 0.7936177850, -0.0040720468),
    (1.9779984951, -2.4285922050, 0.4505937099),
    (0.0259040371, 0.7827717662, -0.8086757660),
)


def to_oklab(rgb: Sequence[float]) -> tuple[float, float, float]:
    """sRGB -> OKLab (Ottosson 2020), the exact matrices, not the xyz shortcut."""
    lin = to_linear(rgb)
    lms = [
        _OK_M1[i][0] * lin[0] + _OK_M1[i][1] * lin[1] + _OK_M1[i][2] * lin[2] for i in range(3)
    ]
    lms = [math.copysign(abs(v) ** (1.0 / 3.0), v) for v in lms]
    return tuple(
        _OK_M2[i][0] * lms[0] + _OK_M2[i][1] * lms[1] + _OK_M2[i][2] * lms[2] for i in range(3)
    )  # type: ignore[return-value]


def to_oklch(rgb: Sequence[float]) -> tuple[float, float, float]:
    """OKLab -> (L, C, h) with h in degrees 0..360, the space where hue is a separate axis."""
    light, a, b = to_oklab(rgb)
    chroma = math.hypot(a, b)
    hue = math.degrees(math.atan2(b, a)) % 360.0
    return (light, chroma, hue)


# --------------------------------------------------------------------------- distances


def delta_e_ok(c1: Sequence[float], c2: Sequence[float]) -> float:
    """Euclidean distance in OKLab. ~0.02 is the just-noticeable difference for large
    patches, ~0.05 for small text; `dE2000 / 100` has roughly the same scale."""
    a = to_oklab(c1)
    b = to_oklab(c2)
    return math.dist(a, b)


def delta_e_76(c1: Sequence[float], c2: Sequence[float]) -> float:
    """Plain Euclidean distance in CIELAB. Kept because it is the classic dE and the
    number most colour literature quotes."""
    return math.dist(to_lab(c1), to_lab(c2))


def delta_e_2000(
    lab1: Sequence[float], lab2: Sequence[float], kL: float = 1.0, kC: float = 1.0, kH: float = 1.0
) -> float:
    """CIEDE2000, the Ciurea/Sharma formulation. Input is CIELAB."""
    l1, a1, b1 = lab1
    l2, a2, b2 = lab2
    c1 = math.hypot(a1, b1)
    c2 = math.hypot(a2, b2)
    c_bar = (c1 + c2) / 2.0
    c_bar7 = c_bar**7
    g = 0.5 * (1.0 - math.sqrt(c_bar7 / (c_bar7 + 25.0**7)))
    a1p = (1.0 + g) * a1
    a2p = (1.0 + g) * a2
    c1p = math.hypot(a1p, b1)
    c2p = math.hypot(a2p, b2)
    h1p = math.degrees(math.atan2(b1, a1p)) % 360.0 if (a1p or b1) else 0.0
    h2p = math.degrees(math.atan2(b2, a2p)) % 360.0 if (a2p or b2) else 0.0

    dlp = l2 - l1
    dcp = c2p - c1p
    if c1p * c2p == 0.0:
        dhp = 0.0
    else:
        diff = h2p - h1p
        if diff > 180.0:
            dhp = diff - 360.0
        elif diff < -180.0:
            dhp = diff + 360.0
        else:
            dhp = diff
    dHp = 2.0 * math.sqrt(c1p * c2p) * math.sin(math.radians(dhp / 2.0))

    l_bar_p = (l1 + l2) / 2.0
    c_bar_p = (c1p + c2p) / 2.0
    if c1p * c2p == 0.0:
        h_bar_p = h1p + h2p
    else:
        s = h1p + h2p
        if abs(h1p - h2p) > 180.0:
            h_bar_p = (s + 360.0) / 2.0 if s < 360.0 else (s - 360.0) / 2.0
        else:
            h_bar_p = s / 2.0

    t = (
        1.0
        - 0.17 * math.cos(math.radians(h_bar_p - 30.0))
        + 0.24 * math.cos(math.radians(2.0 * h_bar_p))
        + 0.32 * math.cos(math.radians(3.0 * h_bar_p + 6.0))
        - 0.20 * math.cos(math.radians(4.0 * h_bar_p - 63.0))
    )
    d_theta = 30.0 * math.exp(-(((h_bar_p - 275.0) / 25.0) ** 2))
    c_bar_p7 = c_bar_p**7
    r_c = 2.0 * math.sqrt(c_bar_p7 / (c_bar_p7 + 25.0**7))
    l_sq = (l_bar_p - 50.0) ** 2
    s_l = 1.0 + (0.015 * l_sq) / math.sqrt(20.0 + l_sq)
    s_c = 1.0 + 0.045 * c_bar_p
    s_h = 1.0 + 0.015 * c_bar_p * t
    r_t = -math.sin(math.radians(2.0 * d_theta)) * r_c

    tl = dlp / (kL * s_l)
    tc = dcp / (kC * s_c)
    th = dHp / (kH * s_h)
    return math.sqrt(tl * tl + tc * tc + th * th + r_t * tc * th)


def delta_e_2000_rgb(c1: Sequence[float], c2: Sequence[float]) -> float:
    return delta_e_2000(to_lab(c1), to_lab(c2))


# --------------------------------------------------------------------------- CVD

# Machado, Oliveira & Fernandes (2009), severity 1.0. Each matrix maps linear RGB for a
# dichromat; it is applied in linear light because that is the space the model was fit in.
CVD_MATRICES: dict[str, tuple[tuple[float, float, float], ...]] = {
    "protan": (
        (0.152286, 1.052583, -0.204868),
        (0.114503, 0.786281, 0.099216),
        (-0.003882, -0.048116, 1.051998),
    ),
    "deutan": (
        (0.367322, 0.860646, -0.227968),
        (0.280085, 0.672501, 0.047413),
        (-0.011820, 0.042940, 0.968881),
    ),
    "tritan": (
        (1.255528, -0.076749, -0.178779),
        (-0.078411, 0.930809, 0.147602),
        (0.004733, 0.691367, 0.303900),
    ),
}


def simulate_cvd(rgb: Sequence[float], kind: str) -> tuple[float, float, float]:
    """Apply one dichromacy simulation, returning an sRGB colour in 0..1."""
    m = CVD_MATRICES[kind]
    lin = to_linear(rgb)
    out = [m[i][0] * lin[0] + m[i][1] * lin[1] + m[i][2] * lin[2] for i in range(3)]
    return from_linear([min(max(v, 0.0), 1.0) for v in out])


# --------------------------------------------------------------------------- tokens


@dataclass(frozen=True)
class Token:
    """One named colour of the palette."""

    name: str
    rgb: tuple[float, float, float]
    alpha: float = 1.0

    @property
    def hex(self) -> str:
        return rgb_to_hex(self.rgb)

    @property
    def luminance(self) -> float:
        return relative_luminance(self.rgb)

    @property
    def oklab(self) -> tuple[float, float, float]:
        return to_oklab(self.rgb)

    @property
    def oklch(self) -> tuple[float, float, float]:
        return to_oklch(self.rgb)

    @property
    def lab(self) -> tuple[float, float, float]:
        return to_lab(self.rgb)


def _parse_hex_alpha(text: str) -> tuple[tuple[float, float, float], float]:
    s = text.strip().lstrip("#")
    alpha = 1.0
    if len(s) == 8:
        alpha = int(s[6:8], 16) / 255.0
        s = s[:6]
    return hex_to_rgb("#" + s), alpha


def flatten_tokens(obj: dict, prefix: str = "") -> Iterable[tuple[str, str]]:
    """Yield (name, hex) for a possibly one-level-nested token map."""
    for key, value in obj.items():
        name = f"{prefix}{key}"
        if isinstance(value, dict):
            yield from flatten_tokens(value, name + ".")
        elif isinstance(value, str):
            yield name, value
        else:
            raise ValueError(f"token {name!r} is neither a hex string nor a group")


def load_tokens(path: str, bg_name: str | None) -> dict[str, Token]:
    with open(path, encoding="utf-8") as handle:
        raw = json.load(handle)
    flat = list(flatten_tokens(raw))
    parsed: dict[str, Token] = {}
    for name, text in flat:
        rgb, alpha = _parse_hex_alpha(text)
        parsed[name] = Token(name, rgb, alpha)

    # Composite any translucent token over the background so the maths sees the colour a
    # viewer actually perceives. Without this step an `rgba(255,255,255,0.08)` border would
    # be measured as near-white and every contrast number would be nonsense.
    target = bg_name
    if target is None:
        target = next((n for n in parsed if n.lower() == "bg"), None)
    if target is None:
        target = next((n for n in parsed if "bg" in n.lower()), None)
    base = parsed.get(target) if target else None
    if base is not None:
        for name, tok in list(parsed.items()):
            if tok.alpha < 1.0:
                mixed = tuple(
                    tok.alpha * c + (1.0 - tok.alpha) * b for c, b in zip(tok.rgb, base.rgb)
                )
                parsed[name] = Token(name, mixed, 1.0)
    return parsed


# --------------------------------------------------------------------------- pairing

# Naming heuristics for the automatic pair list. The intent is to catch the usual mistake
# (a dim label painted on the lightest surface) without demanding a hand-written list.
_SURFACE_HINTS = ("bg", "surface", "panel", "pane", "well", "scrim", "backdrop", "float", "line")
_TEXT_HINTS = ("text", "fg", "ink", "accent", "link", "warn", "danger", "success", "hint")


def looks_like_surface(name: str) -> bool:
    return any(h in name.lower() for h in _SURFACE_HINTS)


def looks_like_text(name: str) -> bool:
    low = name.lower()
    return any(h in low for h in _TEXT_HINTS) and not looks_like_surface(low)


@dataclass(frozen=True)
class Pair:
    fg: str
    bg: str
    label: str
    minimum: float | None = None


def load_pairs(path: str) -> list[Pair]:
    with open(path, encoding="utf-8") as handle:
        raw = json.load(handle)
    return [
        Pair(
            fg=item["fg"],
            bg=item["bg"],
            label=item.get("label", f"{item['fg']} on {item['bg']}"),
            minimum=item.get("min"),
        )
        for item in raw
    ]


def auto_pairs(tokens: dict[str, Token]) -> list[Pair]:
    """Every text-ish token against every surface-ish token."""
    fgs = [n for n in tokens if looks_like_text(n)]
    bgs = [n for n in tokens if looks_like_surface(n)]
    return [Pair(fg=f, bg=b, label=f"{f} on {b}") for f in fgs for b in bgs]


# --------------------------------------------------------------------------- measuring


@dataclass(frozen=True)
class Measurement:
    pair: Pair
    ratio: float
    contrast_protan: float
    contrast_deutan: float
    contrast_tritan: float
    d_ok: float
    d_e2000: float
    d_ok_protan: float
    d_ok_deutan: float
    d_ok_tritan: float
    hue_delta: float

    def aa(self, threshold: float = 4.5) -> bool:
        return self.ratio >= threshold


def _hue_delta(c1: Sequence[float], c2: Sequence[float]) -> float:
    _, _, h1 = to_oklch(c1)
    _, _, h2 = to_oklch(c2)
    d = abs(h1 - h2) % 360.0
    return min(d, 360.0 - d)


def measure(pair: Pair, tokens: dict[str, Token]) -> Measurement:
    fg = tokens[pair.fg]
    bg = tokens[pair.bg]
    return Measurement(
        pair=pair,
        ratio=contrast_ratio(fg.rgb, bg.rgb),
        contrast_protan=contrast_ratio(simulate_cvd(fg.rgb, "protan"), simulate_cvd(bg.rgb, "protan")),
        contrast_deutan=contrast_ratio(simulate_cvd(fg.rgb, "deutan"), simulate_cvd(bg.rgb, "deutan")),
        contrast_tritan=contrast_ratio(simulate_cvd(fg.rgb, "tritan"), simulate_cvd(bg.rgb, "tritan")),
        d_ok=delta_e_ok(fg.rgb, bg.rgb),
        d_e2000=delta_e_2000_rgb(fg.rgb, bg.rgb),
        d_ok_protan=delta_e_ok(simulate_cvd(fg.rgb, "protan"), simulate_cvd(bg.rgb, "protan")),
        d_ok_deutan=delta_e_ok(simulate_cvd(fg.rgb, "deutan"), simulate_cvd(bg.rgb, "deutan")),
        d_ok_tritan=delta_e_ok(simulate_cvd(fg.rgb, "tritan"), simulate_cvd(bg.rgb, "tritan")),
        hue_delta=_hue_delta(fg.rgb, bg.rgb),
    )


def min_inter_color(tokens: dict[str, Token]) -> tuple[float, str, str]:
    best = (math.inf, "", "")
    names = sorted(tokens)
    for i, a in enumerate(names):
        for b in names[i + 1 :]:
            d = delta_e_ok(tokens[a].rgb, tokens[b].rgb)
            if d < best[0]:
                best = (d, a, b)
    return best


def hue_spread(names: Sequence[str], tokens: dict[str, Token]) -> list[tuple[float, str, str]]:
    """Every accent pair sorted by hue distance in OKLCh, closest first."""
    out: list[tuple[float, str, str]] = []
    names = [n for n in names if n in tokens]
    for i, a in enumerate(names):
        for b in names[i + 1 :]:
            out.append((_hue_delta(tokens[a].rgb, tokens[b].rgb), a, b))
    out.sort()
    return out


def luminance_ladder(tokens: dict[str, Token], names: Sequence[str] | None = None) -> list[Token]:
    pool = [tokens[n] for n in (names or tokens)]
    return sorted(pool, key=lambda t: t.oklab[0])


# --------------------------------------------------------------------------- reporting


def markdown_report(
    tokens: dict[str, Token],
    measurements: Sequence[Measurement],
    hue_names: Sequence[str],
    top: int = 8,
) -> str:
    lines: list[str] = []
    add = lines.append
    add("# Palette audit")
    add("")
    add(
        "Every foreground/surface pair is checked three ways: WCAG 2.1 contrast, Euclidean "
        "distance in OKLab (perceptual difference), and the same two measures again after "
        "simulating protanopia, deuteranopia and tritanopia at severity 1.0."
    )
    add("")
    add("Scale reminder: `dOK` is a Euclidean distance in OKLab, where 0.02 is a "
        "just-noticeable difference and 0.05 is a clear one; `dE2000` is CIEDE2000, where "
        "2.3 is the classic JND and 5 is obvious.")
    add("")

    add(f"## Tokens ({len(tokens)})")
    add("")
    add("| token | hex | L* | L(OKLab) | C | h | relative luminance |")
    add("|---|---|---|---|---|---|---|")
    for name in sorted(tokens):
        tok = tokens[name]
        light, chroma, hue = tok.oklch
        add(
            f"| `{name}` | {tok.hex} | {tok.lab[0]:.1f} | {light:.3f} | {chroma:.3f} | "
            f"{hue:.0f}° | {tok.luminance:.4f} |"
        )
    add("")

    add("## Pairs")
    add("")
    add(
        "| pair | fg | bg | contrast | AA 4.5 | AA 3.0 | dOK | dE2000 | protan | deutan | tritan |"
    )
    add("|---|---|---|---|---|---|---|---|---|---|---|")
    for m in measurements:
        add(
            f"| {m.pair.label} | {tokens[m.pair.fg].hex} | {tokens[m.pair.bg].hex} | "
            f"{m.ratio:.2f} | {'pass' if m.ratio >= 4.5 else 'FAIL'} | "
            f"{'pass' if m.ratio >= 3.0 else 'FAIL'} | {m.d_ok:.3f} | {m.d_e2000:.1f} | "
            f"{m.contrast_protan:.2f} | {m.contrast_deutan:.2f} | {m.contrast_tritan:.2f} |"
        )
    add("")

    worst = sorted(measurements, key=lambda m: m.ratio)[:top]
    add(f"## Lowest contrast ({min(top, len(worst))} of {len(measurements)})")
    add("")
    for m in worst:
        verdict = "AA" if m.ratio >= 4.5 else ("AA-large" if m.ratio >= 3.0 else "below 3.0")
        add(f"- **{m.ratio:.2f}:1** {m.pair.label} ({verdict})")
    add("")

    collapsing = [m for m in measurements if m.d_ok >= 0.05 and min(
        m.d_ok_protan, m.d_ok_deutan, m.d_ok_tritan) < 0.05]
    add("## Pairs that collapse under simulated dichromacy")
    add("")
    if not collapsing:
        add("- none: every pair keeps a perceptual distance of at least 0.05 in OKLab "
            "under protanopia, deuteranopia and tritanopia.")
    else:
        for m in collapsing:
            add(
                f"- {m.pair.label}: dOK {m.d_ok:.3f} → protan {m.d_ok_protan:.3f}, "
                f"deutan {m.d_ok_deutan:.3f}, tritan {m.d_ok_tritan:.3f}"
            )
    add("")

    identical = [m for m in measurements if m.d_ok < 0.02]
    add("## Pairs that are perceptually identical (dOK < 0.02)")
    add("")
    if not identical:
        add("- none")
    else:
        for m in identical:
            add(f"- {m.pair.label}: dOK {m.d_ok:.4f}")
    add("")

    hue_pairs = hue_spread(hue_names, tokens)
    add("## Hue separation (accent vocabulary)")
    add("")
    if not hue_pairs:
        add("- no accent tokens were named for the hue check")
    else:
        add("For a dichromat hue is the only remaining channel, so two accents closer in hue "
            "than about 25° are effectively one colour.")
        add("")
        for dist, a, b in hue_pairs[:top]:
            flag = " **<- too close**" if dist < 25.0 else ""
            add(f"- `{a}` vs `{b}`: {dist:.0f}°{flag}")
    add("")

    add("## Tonal ladder (every token, darkest first)")
    add("")
    ladder = luminance_ladder(tokens)
    previous: Token | None = None
    add("| token | hex | L(OKLab) | step dOK |")
    add("|---|---|---|---|")
    for tok in ladder:
        step = "" if previous is None else f"{delta_e_ok(previous.rgb, tok.rgb):.3f}"
        add(f"| `{tok.name}` | {tok.hex} | {tok.oklab[0]:.3f} | {step} |")
        previous = tok
    add("")

    d, a, b = min_inter_color(tokens)
    add("## Closest two tokens in the whole set")
    add("")
    add(f"- `{a}` vs `{b}`: dOK {d:.4f} (dE2000 {delta_e_2000_rgb(tokens[a].rgb, tokens[b].rgb):.1f})")
    add("")
    return "\n".join(lines)


# --------------------------------------------------------------------------- self-test


def selftest() -> bool:
    failures: list[str] = []
    checks = 0

    def check(name: str, got: float, want: float, tol: float) -> None:
        nonlocal checks
        checks += 1
        if abs(got - want) > tol:
            failures.append(f"{name}: got {got!r}, want {want!r} (tol {tol})")

    def check_true(name: str, cond: bool) -> None:
        nonlocal checks
        checks += 1
        if not cond:
            failures.append(name)

    # sRGB round trip
    for value in (0.0, 0.5, 1.0, 0.0123, 0.777):
        check(f"srgb roundtrip {value}", srgb_encode(srgb_decode(value)), value, 1e-9)

    # WCAG reference values
    check("contrast black/white", contrast_ratio((0, 0, 0), (1, 1, 1)), 21.0, 1e-9)
    check("contrast #777 on #fff", contrast_ratio(hex_to_rgb("#777777"), (1, 1, 1)), 4.478, 0.01)
    check("contrast #000 on #808080", contrast_ratio(hex_to_rgb("#000000"), hex_to_rgb("#808080")), 5.319, 0.02)

    # OKLab reference points
    white = to_oklab((1.0, 1.0, 1.0))
    check("oklab white L", white[0], 1.0, 2e-3)
    check("oklab white a", white[1], 0.0, 2e-3)
    check("oklab white b", white[2], 0.0, 2e-3)
    black = to_oklab((0.0, 0.0, 0.0))
    check("oklab black L", black[0], 0.0, 2e-3)
    red = to_oklab(hex_to_rgb("#ff0000"))
    check("oklab red L", red[0], 0.6279, 2e-3)
    check("oklab red a", red[1], 0.2249, 2e-3)
    check("oklab red b", red[2], 0.1258, 2e-3)
    blue = to_oklab(hex_to_rgb("#0000ff"))
    check("oklab blue L", blue[0], 0.4520, 2e-3)
    check("oklab blue a", blue[1], -0.0324, 2e-3)
    check("oklab blue b", blue[2], -0.3115, 2e-3)
    green = to_oklab(hex_to_rgb("#00ff00"))
    check("oklab green L", green[0], 0.8664, 2e-3)
    check("oklab green a", green[1], -0.2339, 2e-3)
    check("oklab green b", green[2], 0.1795, 2e-3)

    # CIEDE2000, Sharma et al. reference pairs
    sharma = [
        ((50.0, 2.6772, -79.7751), (50.0, 0.0, -82.7485), 2.0425),
        ((50.0, 3.1571, -77.2803), (50.0, 0.0, -82.7485), 2.8615),
        ((50.0, 2.8361, -74.0200), (50.0, 0.0, -82.7485), 3.4412),
        ((50.0, -1.3802, -84.2814), (50.0, 0.0, -82.7485), 1.0000),
        ((50.0, -1.1848, -84.8006), (50.0, 0.0, -82.7485), 1.0000),
        ((50.0, -0.9009, -85.5211), (50.0, 0.0, -82.7485), 1.0000),
        ((50.0, 0.0, 0.0), (50.0, -1.0, 2.0), 2.3669),
        ((50.0, -1.0, 2.0), (50.0, 0.0, 0.0), 2.3669),
        ((50.0, 2.4900, -0.0010), (50.0, -2.4900, 0.0009), 7.1792),
        ((50.0, 2.4900, -0.0010), (50.0, -2.4900, 0.0010), 7.1792),
        ((50.0, 2.4900, -0.0010), (50.0, -2.4900, 0.0011), 7.2195),
        ((50.0, 2.4900, -0.0010), (50.0, -2.4900, 0.0012), 7.2195),
        ((50.0, -0.0010, 2.4900), (50.0, 0.0009, -2.4900), 4.8045),
        ((50.0, 2.5, 0.0), (50.0, 0.0, -2.5), 4.3065),
        ((50.0, 2.5, 0.0), (73.0, 25.0, -18.0), 27.1492),
        ((50.0, 2.5, 0.0), (61.0, -5.0, 29.0), 22.8977),
        ((50.0, 2.5, 0.0), (56.0, -27.0, -3.0), 31.9030),
        ((50.0, 2.5, 0.0), (58.0, 24.0, 15.0), 19.4535),
        ((50.0, 2.5, 0.0), (50.0, 3.1736, 0.5854), 1.0000),
        ((50.0, 2.5, 0.0), (50.0, 3.2972, 0.0000), 1.0000),
        ((50.0, 2.5, 0.0), (50.0, 1.8634, 0.5757), 1.0000),
        ((50.0, 2.5, 0.0), (50.0, 3.2592, 0.3350), 1.0000),
        ((60.2574, -34.0099, 36.2677), (60.4626, -34.1751, 39.4387), 1.2644),
        ((63.0109, -31.0961, -5.8663), (62.8187, -29.7946, -4.0864), 1.2630),
        ((61.2901, 3.7196, -5.3901), (61.4292, 2.2480, -4.9620), 1.8731),
        ((35.0831, -44.1164, 3.7933), (35.0232, -40.0716, 1.5901), 1.8645),
        ((22.7233, 20.0904, -46.6940), (23.0331, 14.9730, -42.5619), 2.0373),
        ((36.4612, 47.8580, 18.3852), (36.2715, 50.5065, 21.2231), 1.4146),
        ((90.8027, -2.0831, 1.4410), (91.1528, -1.6435, 0.0447), 1.4441),
        ((90.9257, -0.5406, -0.9208), (88.6381, -0.8985, -0.7239), 1.5381),
        ((6.7747, -0.2908, -2.4247), (5.8714, -0.0985, -2.2286), 0.6377),
        ((2.0776, 0.0795, -1.1350), (0.9033, -0.0636, -0.5514), 0.9082),
    ]
    for i, (lab1, lab2, want) in enumerate(sharma):
        check(f"ciede2000 sharma #{i + 1}", delta_e_2000(lab1, lab2), want, 1e-4)

    # CVD: neutral greys must survive, a red/green pair must collapse
    grey = simulate_cvd(hex_to_rgb("#808080"), "deutan")
    check_true(
        f"deutan keeps grey grey ({rgb_to_hex(grey)})",
        delta_e_ok(grey, hex_to_rgb("#808080")) < 0.02,
    )
    red_c = hex_to_rgb("#e00000")
    green_c = hex_to_rgb("#00a000")
    base = delta_e_ok(red_c, green_c)
    sim = delta_e_ok(simulate_cvd(red_c, "deutan"), simulate_cvd(green_c, "deutan"))
    check_true(f"deutan collapses red/green ({base:.3f} -> {sim:.3f})", sim < base * 0.6)

    for name in ("protan", "deutan", "tritan"):
        matrix = CVD_MATRICES[name]
        check_true(f"{name} matrix shape", len(matrix) == 3 and all(len(r) == 3 for r in matrix))

    print(f"selftest: {checks} checks, {len(failures)} failures")
    for failure in failures:
        print("  FAIL", failure)
    print("PASS" if not failures else "FAIL")
    return not failures


# --------------------------------------------------------------------------- main


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Audit a UI palette for contrast and colour perception")
    parser.add_argument("tokens", nargs="?", help="JSON file with the palette")
    parser.add_argument("--pairs", help="JSON file with the pairs to check")
    parser.add_argument("--md", help="write the markdown report here")
    parser.add_argument("--json", help="write the measurements as JSON here")
    parser.add_argument("--bg", help="token name to composite translucent colours over")
    parser.add_argument("--hues", help="comma-separated token names taking part in the hue check")
    parser.add_argument("--top", type=int, default=8, help="rows in the short lists (default 8)")
    parser.add_argument("--selftest", action="store_true", help="run the built-in math self-test")
    args = parser.parse_args(argv)

    if args.selftest:
        return 0 if selftest() else 1
    if not args.tokens:
        parser.error("a tokens JSON file is required unless --selftest is given")

    tokens = load_tokens(args.tokens, args.bg)
    pairs = load_pairs(args.pairs) if args.pairs else auto_pairs(tokens)
    for pair in pairs:
        for side in (pair.fg, pair.bg):
            if side not in tokens:
                print(f"error: pair references unknown token {side!r}", file=sys.stderr)
                return 2

    measurements = [measure(p, tokens) for p in pairs]
    hue_names = (
        [n.strip() for n in args.hues.split(",") if n.strip()]
        if args.hues
        else [n for n in tokens if looks_like_text(n)]
    )

    report = markdown_report(tokens, measurements, hue_names, args.top)
    if args.md:
        with open(args.md, "w", encoding="utf-8") as handle:
            handle.write(report + "\n")
    print(report)

    if args.json:
        payload = [
            {
                "fg": m.pair.fg,
                "bg": m.pair.bg,
                "label": m.pair.label,
                "contrast": round(m.ratio, 4),
                "contrast_protan": round(m.contrast_protan, 4),
                "contrast_deutan": round(m.contrast_deutan, 4),
                "contrast_tritan": round(m.contrast_tritan, 4),
                "d_ok": round(m.d_ok, 4),
                "d_e2000": round(m.d_e2000, 4),
                "hue_delta": round(m.hue_delta, 2),
            }
            for m in measurements
        ]
        with open(args.json, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2)

    violations = [
        m for m in measurements if m.pair.minimum is not None and m.ratio < m.pair.minimum
    ]
    for m in violations:
        print(
            f"VIOLATION: {m.pair.label} is {m.ratio:.2f}:1, needs {m.pair.minimum:.2f}:1",
            file=sys.stderr,
        )
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())

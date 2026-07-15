#!/usr/bin/env python3
"""Compare upstream vs slim benchmark CSVs and produce a formatted comparison table."""

import csv
import os
import sys
from datetime import datetime
from pathlib import Path

# Paths
UPSTREAM_CSV = Path("/tmp/bench-upstream.csv")
SLIM_CSV = Path("/tmp/bench-slim.csv")
EVIDENCE_DIR = Path(__file__).resolve().parent.parent / "evidence"
EVIDENCE_MD = EVIDENCE_DIR / "bench-results.md"

# Metrics in display order: (column_name, display_label, fmt_type)
METRICS = [
    ("cpu_time", "cpu_time (s)", "time"),
    ("wall_time", "wall_time (s)", "time"),
    ("values", "values", "int"),
    ("thunks", "thunks", "int"),
    ("sets_bytes", "sets_bytes", "bytes"),
    ("gc_time", "gc_time (s)", "time"),
    ("gc_fraction", "gc_fraction", "frac"),
    ("nrAvoided", "nrAvoided", "int"),
    ("nrLookups", "nrLookups", "int"),
]


def fmt_num(value: float, fmt_type: str) -> str:
    """Format a number for display."""
    if fmt_type == "time":
        return f"{value:.2f}"
    elif fmt_type == "int":
        return f"{int(value):,}"
    elif fmt_type == "bytes":
        abs_val = abs(value)
        sign = "-" if value < 0 else ""
        if abs_val >= 1_073_741_824:
            return f"{sign}{abs_val / 1_073_741_824:.2f} GB"
        elif abs_val >= 1_048_576:
            return f"{sign}{abs_val / 1_048_576:.2f} MB"
        else:
            return f"{sign}{abs_val / 1024:.2f} KB"
    elif fmt_type == "frac":
        return f"{value:.4f}"
    return str(value)


def load_csv(path: Path):
    """Load a benchmark CSV and return list of rows as dicts."""
    if not path.exists():
        return None
    rows = []
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)
    return rows


def mean_of(rows, column: str) -> float:
    """Compute mean of a numeric column across rows."""
    values = [float(row[column]) for row in rows]
    return sum(values) / len(values)


def compute_means(rows):
    """Compute mean of warm runs for every metric. Returns dict of column->mean or None."""
    if rows is None:
        return None
    warm_rows = [r for r in rows if r["run_type"] == "warm"]
    if not warm_rows:
        return None
    return {col: mean_of(warm_rows, col) for col, _, _ in METRICS}


def build_table(upstream_means, slim_means):
    """Build list of (label, up_val, slim_val, delta, delta_pct, fmt_type) rows."""
    table = []
    for col, label, fmt_type in METRICS:
        up = upstream_means.get(col) if upstream_means else None
        sl = slim_means.get(col) if slim_means else None
        if up is not None and sl is not None:
            delta = sl - up
            delta_pct = (delta / up) * 100 if up != 0 else 0.0
        else:
            delta = None
            delta_pct = None
        table.append((label, up, sl, delta, delta_pct, fmt_type))
    return table


def fmt_na(val, fmt_type: str) -> str:
    """Format a value or return 'N/A'."""
    if val is None:
        return "N/A"
    return fmt_num(val, fmt_type)


def fmt_delta(delta, delta_pct, fmt_type: str) -> str:
    """Format delta and delta% into a single cell string."""
    if delta is None:
        return "N/A"
    d = fmt_num(delta, fmt_type)
    if delta_pct is not None:
        sign = "+" if delta_pct > 0 else ""
        return f"{d} ({sign}{delta_pct:.2f}%)"
    return d


def print_terminal_table(table, upstream_label, slim_label, source_notes):
    """Print a formatted terminal table."""
    header = ["Metric", upstream_label, slim_label, "Delta (Δ%)"]

    str_rows = []
    for label, up, sl, delta, delta_pct, fmt_type in table:
        up_str = fmt_na(up, fmt_type)
        sl_str = fmt_na(sl, fmt_type)
        delta_str = fmt_delta(delta, delta_pct, fmt_type)
        str_rows.append([label, up_str, sl_str, delta_str])

    ncols = 4
    widths = [0] * ncols
    for ci in range(ncols):
        vals = [header[ci]]
        for r in str_rows:
            vals.append(r[ci])
        widths[ci] = max(len(v) for v in vals)

    sep = " | "

    def mkline(cells):
        parts = []
        for ci, c in enumerate(cells):
            if ci == 0:
                parts.append(c.ljust(widths[ci]))
            else:
                parts.append(c.rjust(widths[ci]))
        return sep.join(parts)

    total_width = sum(widths) + len(sep) * (ncols - 1)
    print("=" * total_width)
    print(mkline(header))
    print("-" * total_width)
    for row in str_rows:
        print(mkline(row))
    print("=" * total_width)

    if source_notes:
        for note in source_notes:
            print(f"\n{note}")

    # Summary
    summary_parts = []
    for label, up, sl, delta, delta_pct, fmt_type in table:
        if delta is not None and delta_pct is not None:
            direction = "reduced" if delta < 0 else "increased"
            summary_parts.append(f"{label} {direction} by {abs(delta_pct):.1f}%")
    if summary_parts:
        print(f"\nSummary: {summary_parts[0]}" + "".join(f", {g}" for g in summary_parts[1:]))


def build_markdown(table, upstream_label, slim_label, source_notes):
    """Build markdown table content."""
    lines = []
    lines.append("# Benchmark Comparison\n")
    lines.append(f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
    lines.append(f"**Comparing:** {upstream_label} vs {slim_label}\n")

    if source_notes:
        for note in source_notes:
            lines.append(f"**Note:** {note}\n")

    # Markdown table
    col_sep = "|--------|" + "-" * 19 + "|" + "-" * 19 + "|------|"
    lines.append(f"| Metric | {upstream_label} | {slim_label} | Δ% |")
    lines.append(col_sep)
    for label, up, sl, delta, delta_pct, fmt_type in table:
        up_str = fmt_na(up, fmt_type)
        sl_str = fmt_na(sl, fmt_type)
        if delta is not None and delta_pct is not None:
            sign = "+" if delta_pct > 0 else ""
            delta_str = f"{sign}{delta_pct:.2f}%"
        else:
            delta_str = "N/A"
        lines.append(f"| {label} | {up_str} | {sl_str} | {delta_str} |")

    lines.append("")
    bullets = []
    for label, up, sl, delta, delta_pct, fmt_type in table:
        if delta is not None and delta_pct is not None:
            direction = "reduced" if delta < 0 else "increased"
            bullets.append(
                f"- **{label}**: {direction} by {abs(delta_pct):.1f}% "
                f"({fmt_na(up, fmt_type)} → {fmt_na(sl, fmt_type)})"
            )
    if bullets:
        lines.append("### Key Changes\n")
        lines.extend(bullets)
        lines.append("")

    return "\n".join(lines)


def main():
    upstream_rows = load_csv(UPSTREAM_CSV)
    slim_rows = load_csv(SLIM_CSV)

    source_notes = []
    if upstream_rows is None:
        source_notes.append("Upstream benchmark CSV not found (eval may have crashed earlier).")
    if slim_rows is None:
        source_notes.append("Slim benchmark CSV not found.")

    col_up = "Upstream"
    col_sl = "Slim"

    upstream_means = compute_means(upstream_rows)
    slim_means = compute_means(slim_rows)

    table = build_table(upstream_means, slim_means)

    # Terminal output
    print_terminal_table(table, col_up, col_sl, source_notes)

    # Markdown output
    EVIDENCE_DIR.mkdir(parents=True, exist_ok=True)
    md = build_markdown(table, col_up, col_sl, source_notes)
    EVIDENCE_MD.write_text(md)
    print(f"\nMarkdown results written to {EVIDENCE_MD}")


if __name__ == "__main__":
    main()

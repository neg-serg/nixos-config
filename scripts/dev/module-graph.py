#!/usr/bin/env python3
"""
NixOS module dependency graph generator.

Parses the module import tree, builds a dependency graph,
detects orphan modules, and outputs an interactive HTML report
with mermaid.js.

Usage:
    python3 scripts/dev/module-graph.py
    # or via justfile:
    just module-graph
"""

import re
import os
import sys
import json
from pathlib import Path
from collections import defaultdict

REPO_ROOT = Path(__file__).resolve().parents[2]
MODULES_DIR = REPO_ROOT / "modules"
FLAT_NIX = MODULES_DIR / "flat.nix"
OUTPUT_HTML = REPO_ROOT / "module-graph.html"


def parse_imports(nix_file):
    """Extract all import paths from a Nix file."""
    text = nix_file.read_text()
    imports = []

    # Match: ./some/path
    for m in re.finditer(r'\./([^\s"\']+)', text):
        path_str = m.group(1).strip()
        # Normalize: remove trailing quotes, comments
        path_str = re.sub(r'["\';,].*$', "", path_str).strip()
        if path_str:
            imports.append(path_str)

    # Match: ./some/path/default.nix (already includes .nix)
    # Match: ./some/path (without .nix — could be a directory)
    return [p for p in imports if p != "."]


def resolve_import(base_dir, import_path):
    """Resolve a relative import path to an actual file."""
    if import_path.endswith(".nix"):
        return (base_dir / import_path).resolve()
    else:
        # Could be a directory with default.nix
        dir_path = base_dir / import_path
        if dir_path.is_dir():
            return dir_path / "default.nix"
        f = dir_path.with_suffix(".nix")
        if f.exists():
            return f
        return dir_path


def collect_all_nix_files():
    """Find every .nix file under modules/."""
    files = {}
    for f in sorted(MODULES_DIR.rglob("*.nix")):
        rel = f.relative_to(REPO_ROOT)
        files[str(rel)] = f
    return files


def build_import_graph(flat_nix):
    """Build the import graph starting from flat.nix."""
    graph = {}  # file -> [dependencies]
    visited = set()
    queue = [flat_nix.resolve()]

    while queue:
        current = queue.pop(0)
        if current in visited:
            continue
        visited.add(current)

        if not current.exists():
            continue

        try:
            deps = parse_imports(current)
        except Exception:
            continue

        resolved_deps = []
        for dep in deps:
            resolved = resolve_import(current.parent, dep)
            if resolved and resolved.exists():
                resolved_deps.append(str(resolved))
                if resolved not in visited and resolved not in queue:
                    queue.append(resolved)

        graph[str(current)] = resolved_deps

    return graph, visited


def detect_orphans(all_files, imported_files):
    """Find .nix files that are NOT imported by anything."""
    imported_set = set(str(p) for p in imported_files)
    orphans = []

    for rel_path, abs_path in all_files.items():
        # Skip files that are explicitly imported
        if str(abs_path) in imported_set:
            continue

        # Skip flat.nix itself and the top-level default.nix (deleted now but handle missing)
        basename = abs_path.name
        if rel_path == "modules/flat.nix":
            continue
        if basename == "README.md":
            continue

        # Some files might be data, not modules
        # Check if they're referenced implicitly
        orphans.append(rel_path)

    return orphans


def domain_from_path(rel_path):
    """Extract domain/category from path."""
    parts = rel_path.split("/")
    if len(parts) >= 2:
        return parts[1]  # e.g., 'cli', 'gui', 'system'
    return "root"


def color_for_domain(domain):
    """Assign a color to each domain."""
    colors = {
        "cli": "#4A90D9",
        "dev": "#7B61FF",
        "system": "#E8634A",
        "gui": "#2ECC71",
        "features": "#F39C12",
        "hardware": "#1ABC9C",
        "media": "#E91E63",
        "security": "#34495E",
        "user": "#8E44AD",
        "servers": "#2980B9",
        "web": "#16A085",
        "shell": "#95A5A6",
        "core": "#F1C40F",
        "profiles": "#E67E22",
        "games": "#FF6B6B",
        "monitoring": "#636E72",
        "fun": "#FD79A8",
        "tools": "#00B894",
        "nix": "#0984E3",
        "text": "#6C5CE7",
        "torrent": "#00CEC9",
        "db": "#A29BFE",
        "emulators": "#FDCB6E",
        "appimage": "#E17055",
        "llm": "#D63031",
        "documentation": "#74B9FF",
        "fonts": "#55EFC4",
        "finance": "#FFEAA7",
        "secrets": "#B2BEC3",
        "roles": "#DFE6E9",
        "root": "#636E72",
    }
    return colors.get(domain, "#636E72")


def generate_html(graph, all_files, orphans):
    """Generate interactive HTML with mermaid.js."""
    # Build mermaid graph
    mermaid_lines = ["graph TD"]

    # Node IDs — use short hashes
    node_id_map = {}
    for i, (f, _) in enumerate(sorted(graph.items())):
        short = f"m{i}"
        rel = Path(f).relative_to(REPO_ROOT)
        domain = domain_from_path(str(rel))
        color = color_for_domain(domain)
        name = str(rel)
        node_id_map[f] = short
        mermaid_lines.append(f'    {short}["{name}"]')

    # Edges
    for source, deps in graph.items():
        if source in node_id_map:
            for dep in deps:
                if dep in node_id_map:
                    mermaid_lines.append(
                        f"    {node_id_map[source]} --> {node_id_map[dep]}"
                    )

    mermaid_code = "\n".join(mermaid_lines)

    # Orphans section
    orphans_html = ""
    if orphans:
        orphans_by_domain = defaultdict(list)
        for o in orphans:
            d = domain_from_path(o)
            orphans_by_domain[d].append(o)

        for domain, files in sorted(orphans_by_domain.items()):
            file_list = "\n".join(
                f'<li><code>{f}</code> <span class="badge">{domain}</span></li>'
                for f in sorted(files)
            )
            orphans_html += (
                f"<h3>{domain} ({len(files)})</h3><ul>{file_list}</ul>"
            )
    else:
        orphans_html = "<p class='clean'>✅ No orphan modules found.</p>"

    # Stats
    domains = defaultdict(int)
    for f in graph:
        rel = Path(f).relative_to(REPO_ROOT)
        d = domain_from_path(str(rel))
        domains[d] += 1

    stats_rows = "".join(
        f'<tr><td>{d}</td><td style="color:{color_for_domain(d)}">{c}</td></tr>'
        for d, c in sorted(domains.items(), key=lambda x: -x[1])
    )

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>NixOS Module Dependency Graph</title>
<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
<style>
  * {{ margin: 0; padding: 0; box-sizing: border-box; }}
  body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #1a1a2e; color: #e0e0e0; }}
  .container {{ max-width: 1400px; margin: 0 auto; padding: 20px; }}
  h1 {{ color: #00d9ff; margin-bottom: 10px; }}
  h2 {{ color: #ff6b35; margin: 20px 0 10px; }}
  h3 {{ color: #e0e0e0; margin: 10px 0 5px; }}
  .stats {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 10px; margin: 20px 0; }}
  .stat-card {{ background: #16213e; padding: 15px; border-radius: 8px; text-align: center; }}
  .stat-card .num {{ font-size: 2em; font-weight: bold; color: #00d9ff; }}
  .stat-card .label {{ color: #888; font-size: 0.9em; }}
  .orphan-list {{ background: #16213e; padding: 20px; border-radius: 8px; margin: 20px 0; }}
  .orphan-list ul {{ list-style: none; padding: 0; }}
  .orphan-list li {{ padding: 4px 0; }}
  .orphan-list .badge {{ background: #e74c3c; color: white; padding: 1px 6px; border-radius: 3px; font-size: 0.8em; }}
  .orphan-list .clean {{ color: #2ecc71; font-size: 1.2em; }}
  #graph-container {{ background: #16213e; padding: 20px; border-radius: 8px; overflow: auto; min-height: 600px; }}
  .tabs {{ display: flex; gap: 10px; margin: 10px 0; }}
  .tab-btn {{ background: #16213e; color: #e0e0e0; border: none; padding: 8px 16px; border-radius: 4px; cursor: pointer; }}
  .tab-btn.active {{ background: #00d9ff; color: #000; }}
  .tab-content {{ display: none; }}
  .tab-content.active {{ display: block; }}
  footer {{ text-align: center; color: #555; margin-top: 40px; font-size: 0.9em; }}
  .zoom-controls {{ position: sticky; top: 10px; text-align: right; }}
  .zoom-controls button {{ background: #0f3460; color: #e0e0e0; border: none; padding: 5px 10px; cursor: pointer; border-radius: 3px; }}
</style>
</head>
<body>
<div class="container">
  <h1>🧩 NixOS Module Dependency Graph</h1>
  <p>Modules: {len(graph)} | Orphans: {len(orphans)}</p>
  
  <div class="stats">
    <div class="stat-card"><div class="num">{len(graph)}</div><div class="label">Modules</div></div>
    <div class="stat-card"><div class="num">{len(orphans)}</div><div class="label">Orphans</div></div>
    <div class="stat-card"><div class="num">{sum(len(d) for d in graph.values())}</div><div class="label">Import edges</div></div>
    <div class="stat-card"><div class="num">{len(all_files)}</div><div class="label">Total .nix files</div></div>
  </div>
  
  <table class="stats" style="width:100%">{stats_rows}</table>
  
  <div class="tabs">
    <button class="tab-btn active" onclick="switchTab('graph')">Graph</button>
    <button class="tab-btn" onclick="switchTab('orphans')">Orphans ({len(orphans)})</button>
    <button class="tab-btn" onclick="switchTab('domains')">By domain</button>
  </div>
  
  <div id="tab-graph" class="tab-content active">
    <div class="zoom-controls">
      <button onclick="zoomIn()">🔍+</button>
      <button onclick="zoomOut()">🔍−</button>
      <button onclick="resetZoom()">⟲</button>
    </div>
    <div id="graph-container">
      <pre class="mermaid" id="mermaid-graph">
{mermaid_code}
      </pre>
    </div>
  </div>
  
  <div id="tab-orphans" class="tab-content">
    <div class="orphan-list">
      <h2>Orphan modules</h2>
      <p>Files in <code>modules/</code> not reachable from <code>flat.nix</code>:</p>
      {orphans_html}
    </div>
  </div>
  
  <div id="tab-domains" class="tab-content">
    <h2>By domain</h2>
    <table style="width:100%">
      <tr><th>Domain</th><th>Count</th></tr>
      {stats_rows}
    </table>
  </div>
  
  <footer>
    Generated by module-graph.py on {__import__('datetime').datetime.now().strftime('%Y-%m-%d %H:%M')}
  </footer>
</div>

<script>
mermaid.initialize({{ startOnLoad: true, theme: 'dark', securityLevel: 'loose', maxEdges: 500 }});

function switchTab(name) {{
  document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
  document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
  document.getElementById('tab-' + name).classList.add('active');
  event.target.classList.add('active');
}}

function zoomIn() {{
  const svg = document.querySelector('#graph-container svg');
  if (svg) {{
    const w = parseFloat(svg.getAttribute('width')) || svg.clientWidth;
    svg.style.width = (w * 1.2) + 'px';
  }}
}}

function zoomOut() {{
  const svg = document.querySelector('#graph-container svg');
  if (svg) {{
    const w = parseFloat(svg.getAttribute('width')) || svg.clientWidth;
    svg.style.width = (w * 0.8) + 'px';
  }}
}}

function resetZoom() {{
  const svg = document.querySelector('#graph-container svg');
  if (svg) svg.style.width = '';
}}
</script>
</body>
</html>"""

    OUTPUT_HTML.write_text(html)
    print(f"✅ Module graph written to {OUTPUT_HTML}")
    print(
        f"   Modules: {len(graph)}, Orphans: {len(orphans)}, Edges: {sum(len(d) for d in graph.values())}"
    )


def main():
    if not FLAT_NIX.exists():
        print(f"❌ Not a NixOS config repo: {FLAT_NIX} not found")
        sys.exit(1)

    print("🔍 Parsing module imports...")
    graph, imported = build_import_graph(FLAT_NIX)

    print(f"   {len(graph)} modules imported from flat.nix")

    print("🔍 Collecting all .nix files...")
    all_files = collect_all_nix_files()
    print(f"   {len(all_files)} .nix files under modules/")

    print("🔍 Detecting orphan modules...")
    orphans = detect_orphans(all_files, imported)
    print(f"   {len(orphans)} orphan files found")

    print("📊 Generating HTML report...")
    generate_html(graph, all_files, orphans)

    print(f"✅ Done! Open file://{OUTPUT_HTML} in your browser.")


if __name__ == "__main__":
    main()

#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3
"""
Analyze NixOS module import graph.
Usage: python3 scripts/dev/analyze-imports.py [--unused] [--circular] [--flat]
"""
import os, re, sys, json
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

def find_nix_files(root):
    for dirpath, _, filenames in os.walk(root):
        for f in filenames:
            if f.endswith('.nix') and not dirpath.startswith(os.path.join(root, '.git')):
                yield os.path.relpath(os.path.join(dirpath, f), root)

def extract_imports(filepath):
    """Extract local imports (./...) from a Nix file."""
    imports = []
    try:
        with open(filepath) as f:
            content = f.read()
        # Match: imports = [ ./foo.nix ./bar.nix ];
        # Also match: imports = [ (./foo.nix) ];
        block_match = re.search(r'imports\s*=\s*\[(.*?)\];', content, re.DOTALL)
        if block_match:
            block = block_match.group(1)
            # Find all ./... or ../... paths
            for m in re.finditer(r'["\x27]?(\.\.?/[^"\x27\s,]+\.nix)["\x27]?', block):
                path = m.group(1)
                if path.startswith('.'):
                    resolved = os.path.normpath(os.path.join(os.path.dirname(filepath), path))
                    imports.append(resolved)
    except Exception as e:
        pass
    return imports

def build_graph(modules_root):
    graph = defaultdict(list)
    reverse = defaultdict(list)
    all_files = list(find_nix_files(modules_root))
    
    for f in all_files:
        full = os.path.join(modules_root, f)
        graph[f] = extract_imports(full)
        for imp in graph[f]:
            reverse[imp].append(f)
    
    return dict(graph), dict(reverse), all_files

def detect_unused(graph, reverse, all_files):
    imported = set()
    for imports in graph.values():
        imported.update(imports)
    unused = [f for f in all_files if f not in imported and any(graph.get(f, []))]
    # Files with imports but never imported by others
    return unused

def detect_circular(graph):
    """DFS-based cycle detection."""
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {}
    
    def dfs(node, path):
        color[node] = GRAY
        for neighbor in graph.get(node, []):
            if color.get(neighbor) == GRAY:
                cycle_start = path.index(neighbor)
                return path[cycle_start:] + [neighbor]
            if color.get(neighbor, WHITE) == WHITE:
                result = dfs(neighbor, path + [neighbor])
                if result:
                    return result
        color[node] = BLACK
        return None
    
    for node in graph:
        color.setdefault(node, WHITE)
    
    cycles = []
    for node in graph:
        if color.get(node, WHITE) == WHITE:
            cycle = dfs(node, [node])
            if cycle:
                cycles.append(cycle)
    return cycles

def flatten_deps(graph, start_files):
    """Topological sort of all reachable dependencies."""
    visited = set()
    order = []
    
    def visit(f):
        if f in visited:
            return
        visited.add(f)
        for dep in graph.get(f, []):
            if dep not in visited:
                visit(dep)
        order.append(f)
    
    for f in sorted(start_files):
        visit(f)
    return order

def main():
    modules_root = os.path.join(ROOT, 'modules')
    graph, reverse, all_files = build_graph(modules_root)
    
    flags = set(sys.argv[1:])
    show_all = not flags or '--all' in flags
    
    if '--unused' in flags or show_all:
        unused = detect_unused(graph, reverse, all_files)
        print(f"\n=== Unused modules ({len(unused)}) ===\n")
        print("These have imports but are never imported by others:")
        for f in unused[:20]:
            print(f"  {f}")
        if len(unused) > 20:
            print(f"  ... and {len(unused)-20} more")
    
    if '--circular' in flags or show_all:
        cycles = detect_circular(graph)
        print(f"\n=== Circular dependencies ({len(cycles)}) ===\n")
        if cycles:
            for c in cycles:
                print("  → ".join(c))
        else:
            print("  None found ✓")
    
    if '--flat' in flags or show_all:
        start_files = [f for f in all_files if not reverse.get(f)]
        if not start_files:
            start_files = all_files[:1]
        flat = flatten_deps(graph, start_files)
        print(f"\n=== Flattened import order ({len(flat)} of {len(all_files)} files) ===\n")
        for f in flat[:15]:
            deps = graph.get(f, [])
            print(f"  {f}  (imports: {len(deps)})")
        if len(flat) > 15:
            print(f"  ... and {len(flat)-15} more")
    
    if '--json' in flags:
        print(json.dumps({
            'total_files': len(all_files),
            'with_imports': sum(1 for i in graph.values() if i),
            'unused': len(detect_unused(graph, reverse, all_files)),
            'circular': len(detect_circular(graph)),
            'root_importers': len([f for f in all_files if not reverse.get(f)]),
        }, indent=2))

if __name__ == '__main__':
    main()

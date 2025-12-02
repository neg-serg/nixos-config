import argparse
import os
import sys
from typing import List, Tuple


def parse_cpuset(s: str):
    cpus = set()
    for part in s.split(','):
        part = part.strip()
        if not part:
            continue
        if '-' in part:
            a, b = part.split('-', 1)
            cpus.update(range(int(a), int(b) + 1))
        else:
            cpus.add(int(part))
    return sorted(cpus)


def parse_size(sz: str) -> int:
    sz = sz.strip().upper()
    if not sz:
        return 0
    try:
        if sz.endswith('K'):
            return int(float(sz[:-1]) * 1024)
        if sz.endswith('M'):
            return int(float(sz[:-1]) * 1024 * 1024)
        if sz.endswith('G'):
            return int(float(sz[:-1]) * 1024 * 1024 * 1024)
        return int(sz)
    except Exception:
        return 0


def l3_groups() -> List[Tuple[int, List[int]]]:
    """Return list of (size_bytes, cpus[]) unique L3 groups."""
    groups = {}
    sysfs = '/sys/devices/system/cpu'
    try:
        for name in os.listdir(sysfs):
            if not name.startswith('cpu'):
                continue
            # Ensure the suffix after 'cpu' is numeric
            if not name[3:].isdigit():
                continue
            base = os.path.join(sysfs, name, 'cache', 'index3')
            size_p = os.path.join(base, 'size')
            share_p = os.path.join(base, 'shared_cpu_list')
            try:
                with open(size_p, 'r') as f:
                    size = parse_size(f.read())
                with open(share_p, 'r') as f:
                    shared = f.read().strip()
            except Exception:
                continue
            cpus = tuple(parse_cpuset(shared))
            if not cpus:
                continue
            # Use the CPU set as the key to dedupe
            if cpus not in groups:
                groups[cpus] = size
    except Exception:
        pass
    # Return as list of (size, cpus_list)
    return [(sz, list(cps)) for cps, sz in groups.items()]


def auto_cpuset() -> List[int]:
    """Pick CPUs from the largest L3 group (V-Cache CCD on X3D)."""
    groups = l3_groups()
    if not groups:
        # Fallback to all online CPUs
        try:
            with open('/sys/devices/system/cpu/online', 'r') as f:
                return parse_cpuset(f.read().strip())
        except Exception:
            return []
    # Pick group with largest L3.
    # Tie: prefer more CPUs, then higher min index.
    groups.sort(key=lambda g: (g[0], len(g[1]), min(g[1]) if g[1] else -1))
    size, cpus = groups[-1]
    # Optional limit via env var (e.g., 8)
    try:
        lim = int(os.environ.get('GAME_PIN_AUTO_LIMIT', '0'))
    except Exception:
        lim = 0
    if lim and lim > 0:
        return cpus[:lim]
    return cpus


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    # Note: The default value for --cpus is injected by Nix wrapper or passed via env
    # We'll handle the default logic in the main block if needed, but here we assume
    # the wrapper passes it or we read env.
    ap.add_argument(
        '--cpus',
        default=os.environ.get('GAME_PIN_CPUSET', 'auto'),
    )
    ap.add_argument('cmd', nargs=argparse.REMAINDER)
    args = ap.parse_args()

    if not args.cmd or args.cmd[0] != '--':
        print(
            'Usage: game-affinity-exec --cpus <set|auto> -- <command> [args...]',
            file=sys.stderr,
        )
        sys.exit(2)
    cmd = args.cmd[1:]

    if str(args.cpus).strip().lower() == 'auto':
        cpus = auto_cpuset()
    else:
        cpus = parse_cpuset(args.cpus)

    try:
        if cpus:
            os.sched_setaffinity(0, cpus)
    except Exception as e:
        print(f'Warning: failed to set CPU affinity: {e}', file=sys.stderr)

    use_gamemode = os.environ.get('GAME_RUN_USE_GAMEMODE', '1') not in (
        '0', 'false', 'no'
    )
    if use_gamemode:
        cmd = ['gamemoderun'] + cmd

    os.execvp(cmd[0], cmd)

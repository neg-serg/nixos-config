# Draft: nixpkgs-slim-optimize-round2

## State
- intent: clear
- review_required: false
- status: plan-ready
- pending: await user decision — start work or high-accuracy review

## Metis gaps resolved
15 gaps found, all fixed. Key changes:
- GAP-1: Dropped Wave 5 (pathExists — already mkIf-wrapped, near-zero impact)
- GAP-2: Dropped Wave 1 profiling (disconnected from downstream waves)
- GAP-3: `nix flake lock` scoped to `--update-input nixpkgs`
- GAP-4: Final wave checkboxes `[x]` → `[ ]`
- GAP-7: Success criterion relaxed from ≥15% to ≥10%
- Folded single real pathExists fix (hostExtras) into Wave 3

## Components
| ID | Component | Wave | Status |
|----|-----------|------|--------|
| C1 | B: Shadow ×55 fix | 1 | pending |
| C2 | D: Additional disabledModules | 1 | pending |
| C3 | A: Fork cleanup (web-apps + cascade) | 2 | pending |
| C4 | C: Domain filter tighten | 3 | pending |
| C5 | E: hostExtras pathExists fix | 3 | pending |
| C6 | Final benchmark + cumulative report | 4 | pending |

## Final plan: 4 waves, 8 tasks
`.omo/plans/nixpkgs-slim-optimize-round2.md`

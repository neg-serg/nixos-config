# Draft: Nix eval speedup (4.3s → ~2s)

- **intent**: CLEAR
- **review_required**: false
- **slug**: eval-speedup
- **status**: awaiting-approval
- **test_configs_decision**: move to checks
- **plan_path**: .omo/plans/eval-speedup.md

## Approval gate

Plan written. 12 todos across 3 waves:

| Wave | Todos | Target savings | Risk |
|------|-------|---------------|------|
| 1 — Structural | T1–T3 (lazy per-system, test→checks, split devShells) | ~1.5s | Medium — flake restructuring |
| 2 — Consolidation | T4–T7 (merge wrappers, features-data, drop empty) | ~0.5s | Low — mechanical |
| 3 — Feature flags | T8–T9 (assertions→CI, flatten options) | ~0.2s | Low |
| Verify | T10–T12 (timing, regressions) | — | — |

**User action**: approve to proceed, or raise concerns.

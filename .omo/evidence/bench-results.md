# Benchmark Comparison

**Generated:** 2026-07-15 07:34:20

**Comparing:** Upstream vs Slim

| Metric | Upstream | Slim | Δ% | |--------|-------------------|-------------------|------| |
cpu_time (s) | 5.49 | 4.78 | -13.09% | | wall_time (s) | 5.97 | 5.13 | -14.08% | | values |
15,448,292 | 11,175,376 | -27.66% | | thunks | 8,534,017 | 7,072,131 | -17.13% | | sets_bytes |
507.69 MB | 326.89 MB | -35.61% | | gc_time (s) | 0.04 | 0.03 | -29.91% | | gc_fraction | 0.0071 |
0.0057 | -19.37% | | nrAvoided | 8,004,825 | 6,699,836 | -16.30% | | nrLookups | 2,781,759 |
2,267,779 | -18.48% |

### Key Changes

- **cpu_time (s)**: reduced by 13.1% (5.49 → 4.78)
- **wall_time (s)**: reduced by 14.1% (5.97 → 5.13)
- **values**: reduced by 27.7% (15,448,292 → 11,175,376)
- **thunks**: reduced by 17.1% (8,534,017 → 7,072,131)
- **sets_bytes**: reduced by 35.6% (507.69 MB → 326.89 MB)
- **gc_time (s)**: reduced by 29.9% (0.04 → 0.03)
- **gc_fraction**: reduced by 19.4% (0.0071 → 0.0057)
- **nrAvoided**: reduced by 16.3% (8,004,825 → 6,699,836)
- **nrLookups**: reduced by 18.5% (2,781,759 → 2,267,779)

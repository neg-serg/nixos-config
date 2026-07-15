---
slug: zen-to-vivaldi-profile-migration
status: drafting
intent: clear
pending-action: write .omo/plans/zen-to-vivaldi-profile-migration.md
approach: Expand modules/user/nix-maid/web/zen-migrate.nix with a new zen-profile-migrate script that orchestrates full Zen→Vivaldi migration: bookmarks (existing), passwords/history/autofill (Vivaldi built-in import), cookies (direct SQLite migration via Python), plus post-migration report.
review_required: true
review_status: complete
momus: APPROVE (all 5 standards met — clarity, verifiability, completeness, consistency, testability)
oracle: APPROVE (all 8 previously identified issues resolved — SameSite, Zen check, master password, OSCrypt, LD_LIBRARY_PATH, backup exclusions, atomic write, creationTime)
---

# Draft: zen-to-vivaldi-profile-migration

## Components (topology ledger)
| id | outcome | status | evidence path |
| -- | ------- | ------ | ------------- |
| C1 | Main orchestration script `zen-profile-migrate` | active | modules/user/nix-maid/web/zen-migrate.nix |
| C2 | Cookie migration via Python (NSS decrypt + SQLite write) | active | modules/user/nix-maid/web/zen-migrate.nix |
| C3 | Vivaldi built-in import (passwords, history, autofill) | active | `vivaldi://settings/importData` |
| C4 | NixOS module wiring (dependencies, systemPackages) | active | modules/user/nix-maid/web/zen-migrate.nix |
| C5 | Script QA and error handling | active | .omo/evidence/ |

## Open assumptions (announced defaults)
| assumption | adopted default | rationale | reversible? |
| ---------- | --------------- | --------- | ----------- |
| Cookie migration via Python+NSS instead of FF2Chrome | Direct Python implementation | FF2Chrome repo returns 404; direct approach is more maintainable and auditable | yes |
| One-shot script, not systemd service | `writeShellApplication` exposed via `systemPackages` | Migration is a one-time operation; re-running on every rebuild is wasteful and risky | yes |
| Vivaldi must be closed during migration | Script checks for running Vivaldi, refuses to run if open | Writing to Vivaldi's profile while browser is open corrupts the database | yes |
| Zen profile auto-detection reuses existing logic | Search `~/.zen/*/` and `~/.config/zen/*/` for `places.sqlite` | Already proven in zen-migrate.nix:59-83 | yes |

## Findings (cited - path:lines)
- Existing bookmarks-only migration: `modules/user/nix-maid/web/zen-migrate.nix:1-242` — `zen-bookmarks-export` exports to Netscape HTML
- Vivaldi config: `modules/user/nix-maid/web/vivaldi.nix:1-88` — Wayland, chromium policies, fonts
- Host: `hosts/odin/default.nix:27-28` — Vivaldi is default, `features.web.vivaldi.enable = true`
- Zen profile paths: `~/.zen/*/` and `~/.config/zen/*/` (zen-migrate.nix:59-60)
- Vivaldi profile path: `~/.config/vivaldi/Default/` (Chromium standard)
- Firefox cookie format: `cookies.sqlite` (encrypted via NSS `key4.db`) vs Chromium `Cookies` (SQLite, own format)
- FF2Chrome: not found (github.com/nickoppen/ff2chrome → 404)
- NSS libraries available in nixpkgs: `pkgs.nss` provides `libnss3.so`, `pkgs.sqlite` provides `sqlite3`
- Python3 with `sqlite3` module available in nixpkgs
- Module import: `modules/user/nix-maid/default.nix:64` imports zen-migrate.nix

## Decisions (with rationale)
1. **Cookie migration: Python + sqlite3 + NSS** — FF2Chrome not found. Python is already in nixpkgs, `sqlite3` is stdlib, and `pkgs.nss` provides `libnss3.so` for NSS decryption. The script reads Firefox's `cookies.sqlite` and `key4.db` (NSS cert8.db format), decrypts cookie values, and writes them to Chromium's `Cookies` SQLite database.
2. **Bookmarks stay with existing `zen-bookmarks-export`** — It works, no need to duplicate. The new script calls it internally.
3. **Passwords/history/autofill: Vivaldi's built-in import** — Vivaldi at `vivaldi://settings/importData` directly reads Firefox profiles. The script launches Vivaldi with the import dialog pre-targeted, or provides clear GUI instructions. No CLI automation for this part (Vivaldi doesn't expose import via CLI flags).
4. **Profile backup before any write** — Script creates a tarball of `~/.config/vivaldi/Default/` before modifying anything, so migration is reversible.

## Scope IN
- New `zen-profile-migrate` script in `zen-migrate.nix`
- Python cookie migration script (Firefox → Chromium)
- Backup creation for Vivaldi profile
- Post-migration report (what was done, what needs manual steps)
- NixOS module wiring (dependencies: python3, sqlite, nss)

## Scope OUT (Must NOT have)
- Extension migration (Firefox addons ≠ Chromium extensions)
- Settings/preferences migration
- Automated GUI interaction (no `xdotool`/`ydotool` — Vivaldi import is manual step)
- systemd service/timer (one-shot operation)
- Modifications to `vivaldi.nix` or any other existing module

## Open questions
(none)

## Approval gate
status: awaiting-approval

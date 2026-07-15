# Draft: cht-cache-hyprfocus-rust

## Meta
- **intent**: CLEAR
- **review_required**: false
- **status**: awaiting-approval
- **slug**: cht-cache-hyprfocus-rust

## Decisions

| # | Decision | Rationale | Reversible? |
|---|----------|-----------|-------------|
| D1 | cht: local file cache at `~/.cache/cht/` | Simplest, fastest — no server needed. Network fallback on cache miss. | Yes |
| D2 | cht: cache key = URL-encoded query as filename | Deterministic, no collision risk for cheat.sh topics | Yes |
| D3 | cht: TTL = 7 days, force refresh with `cht --refresh` | Cheatsheets rarely change; user controls freshness | Yes |
| D4 | hypr-focus: Rust crate `hyprland = "0.4.0-beta.3"` (sync API) | Best-maintained, covers all needed IPC. Sync for daemon simplicity. | Yes, but would need code changes |
| D5 | hypr-focus: single binary, two modes (daemon + commands) | Same binary handles daemon AND one-shot commands; user doesn't manage two binaries | No — user explicitly asked for expanded functionality |
| D6 | hypr-focus: package at `packages/hypr-focus/` with `rustPlatform.buildRustPackage` | Follows existing repo patterns (pwroute, sqlit, etc.) | No |
| D7 | hypr-focus: wired via `tools.nix` overlay as `pkgs.neg.hypr-focus` | Standard overlay pattern for user-facing Rust tools | No |
| D8 | hypr-focus: replace Python script symlink in `local-bin.nix` | Seamless upgrade: `hypr-focus-hist` command now runs Rust binary | No |
| D9 | hypr-focus: communication via state file (daemon) + direct IPC (commands) | Daemon writes state for persistence; commands read state and dispatch directly | Yes |
| D10 | Graphical/display scripts (screenrec, screenshot, swayimg-actions, etc.) NOT touched | User explicitly said "не трогать" | N/A |

## Open Questions (resolved)

1. **Which Rust crate for Hyprland IPC?** → `hyprland` (hyprland-rs) v0.4.0-beta.3 — covers events + dispatch + keyword + ctl
2. **How are Rust packages built?** → `rustPlatform.buildRustPackage` with `src = ./.;` and `cargoLock.lockFile = ./Cargo.lock;`
3. **How are packages wired?** → `packages/overlays/tools.nix` via `callPkg`, exposed as `pkgs.neg.<name>`
4. **How does local-bin install work?** → `modules/user/nix-maid/cli/local-bin.nix` reads files from `packages/local-bin/bin/`, creates home.file entries at `~/.local/bin/<name>`
5. **What Hyprland features are unused but useful?** → No togglefloating keybind (only in special submap), no layout switching keybind, no pin keybind, no window-attach-to-workspace keybind

## Feature set for hypr-focus (derived from user request + gap analysis)

From user: "attach to workspace, attach window, various tiling options, and more"

Expanded:
1. **Focus history** (preserve existing): cycle back through previously focused windows
2. **Workspace jump**: focus workspace by number/name
3. **Window to workspace**: move focused window to a specific workspace (and optionally follow)
4. **Toggle floating**: quick toggle without submap
5. **Toggle fullscreen**: quick toggle
6. **Toggle pin**: pin/unpin window across all workspaces
7. **Layout toggle**: switch master ↔ dwindle (with direct jump to either)
8. **Master orientation**: flip master left/right/top/bottom
9. **Master ratio (mfact)**: adjust ±0.1 or set exact value (0.3–0.9)
10. **Master add/remove**: add/remove master windows
11. **Window swap**: swap focused window with master
12. **Dwindle split**: toggle horizontal ↔ vertical
13. **Dwindle preselect**: preselect l/r/u/d before opening new window
14. **Daemon mode**: background focus history tracking (existing functionality)

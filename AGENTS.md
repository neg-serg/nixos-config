# AGENTS usage for this repo

Communication language (hard rule)

- The user (neg) cannot read Chinese at all. NEVER write Chinese in chat replies, commit
  messages, UI copy, or any file they read. Upstream dsh bundles may contain Chinese strings we
  did not write; do not copy them into replies.
- The user's language is Russian. Chat replies are Russian; documentation and code comments are
  English only. Do NOT create `*.ru.md` / `*.ru.mdown` / `*.ru.markdown` files, do NOT write
  documentation prose in Russian in any file, and do NOT translate English docs into Russian. When
  in doubt: Russian for chat, English for docs.
- Code comments (Nix, Lua, Bash, Rust, ...) and commit messages are English only: an English
  imperative subject and an English body.
- `just lint` runs `scripts/dev/check-markdown-language.sh` over git-visible `*.md` and rejects CJK
  and Cyrillic; three glyph-example files are allowlisted. Keep docs English.

Scope

- Applies to the entire `/etc/nixos` tree. Prefer the existing structure (`modules/`, `hosts/`,
  `modules/user/nix-maid/`) and the surrounding style.
- Nested `AGENTS.md` files exist under `modules/`, `packages/`, `scripts/`, `secrets/`,
  `secrets/home/`, `hosts/`. Read the nearest one before touching that subtree; nested rules win
  where they conflict with this file.

Quick Commands

- Format: `just fmt`. Lint: `just lint` (shell, Markdown and syntax gates). Flake checks:
  `just check` (`nix flake check -L --option substitute false`).
- Build only:
  `rom build .#nixosConfigurations.trantor.config.system.build.toplevel -- --out-link result`
  (substitution on; use `--option substitute false` only for a one-off debug build or while
  `sing-box-proxy` is down).
- Update inputs: `just update`; own repositories: `just bump-own` (the weekly timer does this on
  trantor).
- Seed a blocked fixed-output source: `just seed`.
- GC: `sudo nix-collect-garbage -d && nix-collect-garbage -d` — destructive, ask first.
- Never `sudo nixos-rebuild switch`: its build runs as root, which cannot fetch the private
  `aurora` `git+ssh` input (`error: Failed to fetch git repository ...`). Use the rollout paths
  below.

Automatic rollout (hard fact)

- `features.system.rolloutWatch` is enabled on trantor (`hosts/trantor/default.nix`): every two
  minutes `nixos-rollout-watch.timer` takes a clean `main`, runs `just check`, builds the
  toplevel and starts `nixos-agent-rollout.service` with the verified store path. A commit on
  `main` is a deploy request.
- Changes under `secrets/`, `modules/system/net/vpn/`, `modules/security/` and the watcher itself
  are only reported, never auto-deployed; those need `just switch-sudo`.
- `flake-bump-own.timer` commits `flake.lock` weekly (Sunday 04:00) and the watcher deploys it.
- Details, journal commands and the pause switch: `.agent/workflows/rebuild.md`.

Rollout

- Agent (no password): `just agent-switch "$(readlink -f result)"`. It writes the verified
  toplevel to `.agent/switch-request` and starts the root-owned `nixos-agent-rollout.service`
  (the old `nixos-agent-switch.service` name is a one-generation bootstrap alias). The unit
  re-builds the flake as the main user, refuses when the tree now builds a different toplevel,
  activates only the verified path as root, and logs HEAD, the dirty-file list and the artifact to
  the journal (`journalctl -u nixos-agent-rollout`; the work unit is
  `nixos-agent-rollout-work`).
- Human: `just switch-sudo` builds with the invoking user's credentials and gives root only
  `nix-env --set` plus `switch-to-configuration`. `just deploy` adds `pleamar-sync`,
  `check-eval` and `hooks-ensure`; it is what the `rebuild` scratchpad (`Super+Shift+N`) runs.
- Agent order: clean/intentional `git status` (the tree is what gets activated) → `just fmt` →
  `just lint` → build the closure → verify what `result` contains →
  `just agent-switch "$(readlink -f result)"`.
- The mechanism is deliberate: the removed `nixos-rebuild` NOPASSWD entry was passwordless
  arbitrary root whose target lives in the user-writable `/etc/nixos`. The polkit rule allows only
  `start` of that one unit. The tradeoff is known: whoever can write the flake can request a
  switch. Never ask for the password.
- `features.security.tpmSudo` is off (the flag is commented in `hosts/trantor/default.nix`);
  `/dev/tpmrm0` now exists, so enabling it is a real option.

Project Structure

- `flake.nix` — entry point (NixOS + the nix-maid user layer); `flake/` — helpers (`nixos.nix`
  with `trantorDomains`, `checks.nix`).
- `modules/` — system modules by domain; feature flags in `modules/features/<domain>.nix`.
- `hosts/trantor/` — host glue: `hardware.nix`, `networking.nix`, `services/`, the
  notify/telegram units and `unbound-hosts.nix`.
- `packages/` — overlays and local packages (`local-bin/`); `lib/` — shared helpers (`opts.nix`,
  `neg-helpers.nix`, `systemd-user.nix`, ...); `secrets/` — SOPS; `files/` — config files.
- `scripts/dev/` — utility scripts; `.agent/workflows/` — step-by-step procedures (no overviews
  or generated maps); `.githooks/` — hooks (`just hooks-enable`, currently enabled).
- `result`, `nix/` and `viz/` are gitignored build/local outputs — never commit them.
- The pleamar shell is its own repo, consumed as a `git+file:` input on
  `~/src/nix/pleamar-config`: scene links are live, module/worker code needs a commit plus
  `just pleamar-sync` (`just deploy` runs it).
- The dsh plugins live in `github:neg-serg/dsh-plugins` (30 packages); the host keeps the roster
  and the two third-party forks (`dsh-plugin-recall`, `dsh-plugin-vetting`).
- Neovim config is `github:neg-serg/nvim-config` at `~/src/nix/nvim-config`, linked live into
  `~/.config/nvim`; deliberately not a flake input.
- More packages live outside this tree (rust-pkgs, nix-optimized, llm-proxy, aurora*, nixos-music,
  dsh-app, nightjob, music-ai-libs): see `packages/AGENTS.md`; do not copy them back.

Feature Flags

- Declare flags in `modules/features/<domain>.nix`; read one with
  `just flag features.cli.yazi.enable`.
- trantor uses `trantorDomains` (`flake/nixos.nix`). The only excluded domain is `appimage`;
  `llm` is active. Warn the user before touching `appimage`.

Nix style: `pkgs.*` lists

- Every non-obvious `pkgs.<name>` in a package list gets a short comment about its role, not
  marketing copy:
  - `pkgs.supercollider # SuperCollider IDE and audio engine`
- Keep changes minimal and focused; avoid drive-by refactors and mention unrelated issues
  separately.

General guidance

- Document behavior where it lives: module header comments, `mkOption` descriptions, and comments
  next to non-obvious code (the why, invariants, gotchas) in English. `.agent/workflows/` holds
  procedures only; fold single-module knowledge into the code.
- Before committing: `just fmt`, `just lint`, `just check`; never commit unformatted or failing
  changes. The `commit-msg` hook enforces an ASCII subject with a `[scope] ` prefix.
- For WireGuard/VPN host-vs-user patterns, see `git log` and the comments in
  `modules/system/net/vpn/`.
- Lookup discipline: start from the error or output that names the failure, then query narrowly
  (`... | rg -A3 '<key>'`); a full docs dump costs more than the fix it was meant to make safe.
- AGENTS.md is the contract. README and `.agent/workflows/` must not contradict it; when a command
  or path changes, update all three. Installed skills are pointers, not overrides: if one
  contradicts this file, this file wins.

Debugging and answers

- No fixes without a root cause: reproduce the exact symptom and build a tight red/green command
  before reading code or proposing a fix. See `.agent/workflows/debugging.md`; verify by
  execution, never by inspection.
- Every sentence is a fact, a decision, or a risk; assume a technical reader and state uncertainty
  and tradeoffs. For a change or judgment call use: Problem — what is wrong; Decision — action and
  why; Check — what can break and how it is verified; Next — concrete action.
- Default to action and resolve ambiguity from repo conventions. Ask only for materially different
  tradeoffs. Always ask before touching `secrets/`, destructive/irreversible operations (GC,
  deleting generations, removing modules/packages), and network/VPN/WireGuard changes.

Research and secrets

- Prefer primary sources and cite the URL where the claim is used; do not search for content you
  can read directly (known repos, official docs, arXiv pages).
- Never print tokens, keys, passwords or decrypted SOPS values; mask them (`sk-***abcd`). Plaintext
  never enters the repo or chat. Read `secrets/AGENTS.md` before touching that subtree.

Tooling

- Prefer `rg`, `fd`, `bat`, `jq`, `eza`, `delta`, `sd`, `hyperfine` over legacy coreutils; use the
  DSH-native `read`/`rg`/`glob` tools before shelling out. Details: skill `golden-tools`.

Desktop automation (hard rules)

- The browser tool is not used; GUI work goes through the `desktop` tool. Headless chromium and
  dsh-browser were removed. The one CDP exception on this host is the rutracker workflow's live
  Vivaldi session (skill `rutracker`); do not build new CDP automation.
- Never drive the pointer with raw `ydotool`/uinput: clicks, drags and scrolls go through the
  `desktop` tool. A hand-rolled `ydotool click 0x40` is button-down only and can leave the left
  button stuck; release it with `ydotool click 0x80` or
  `systemctl --user restart ydotoold.service`.
- Screenshots stay local (qwen2.5vl). Downscale 4K captures before vision:
  `magick shot.png -resize 1280x small.png`.

Builds and substitution

- `cache.nixos.org` is unreliable directly and answers through the sing-box SOCKS5 proxy, which
  `nix-daemon` uses (`features.net.nixDaemonProxy`); root's `/root/.config/nix/nix.conf` is pinned
  to the same cache by tmpfiles (`modules/nix/settings.nix`). Deploy targets substitute.
- `just check` and `just flag` pass `--option substitute false`; the deploy/switch targets do not.
  Use it for one-off debugging and whenever the proxy is down (stalled lookups cost minutes).
- Sandboxed builds have no network: prefetch blocked sources with `just seed`
  (`scripts/dev/nix-seed-fods.sh`).
- In a sandboxed agent session bare `nix` works through `packages/local-bin/bin/nix` →
  `~/.local/bin/nix`, which keeps the fetcher cache writable; outside a sandbox it is a
  passthrough. Guard: `scripts/dev/check-nix-wrapper.sh` (flake check `nix-wrapper-guard`).

Privileges

- Passwordless sudo is limited to the entries in `modules/security/default.nix`: `systemctl
  start/stop xray` (with sudo's `""` exact-arguments marker), `reboot`, `poweroff`, `suspend`,
  `dmesg`, `ryzenadj`, `gpu-oc`, `glm-usbmon-priv`. Everything else prompts, `sudo -n` included.

Commit style

- Use a bracketed scope prefix consistent with history: `[media/audio] ...`, `[hosts/trantor] ...`,
  `[docs] ...`.
- Common scopes: nixpkgs, flake/*, core/*, hosts/<hostname>, dev/*, cli/*, hardware/*, media/*,
  servers/*, modules/*, packages/*, docs, ci, refactor.
- Imperative, short, specific, no trailing period.
- Examples:
  - `[media/audio] Add SuperCollider live-coding stack`
  - `[hosts/trantor] Tune cooling profile`
  - `[docs] Document audio creation stack`

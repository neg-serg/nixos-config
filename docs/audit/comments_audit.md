# Audit of Commented-out Code and Redundant Comments

This report documents blocks of code that are currently commented out, as well as comments that may be redundant, legacy, or placeholders.

## 1. Dead / Commented-out Code Blocks

These are blocks of code that define services, interfaces, or imports but are currently inactive.

| File | Context | Impact/Status |
|------|---------|---------------|
| `modules/user/nix-maid/sys/nekoray.nix` | `systemd.user.services.nekoray` | Entire local GUI proxy service commented out. |
| `modules/nix/nixindex.nix` | `systemd.services.nixindex` & timer | Periodic database updates for `nix-index` disabled. |
| `hosts/telfir/virtualisation/lxc.nix` | `systemd.services."lxc-zero-sandbox"` | LXC container management service commented out. |
| `modules/system/net/vpn/wireguard.nix` | `networking.wg-quick.interfaces.wg0` | Interface disabled due to missing keys (legacy/duplicate of SOPS setup). |
| `modules/system/virt.nix` | `imports = [ ./virt/macos-vm.nix ];` | macOS VM integration commented out. |
| `modules/web/browsers.nix` | `imports = [ ...yandex-browser... ];` | Yandex Browser module import commented out. |
| `modules/dev/editor/pkgs.nix` | `pkgs.zeal` | Zeal (offline docs) package commented out. |

## 2. TODOs and FIXMEs

Active trackers in the codebase that indicate unfinished business or required cleanup.

- **`modules/llm/codex-config.nix`**: `deepseek=your_api_key # FIXME` (Requires real API key).
- **`packages/local-bin/bin/swd`**: `# TODO: create swd for unsplash`.
- **`modules/user/nix-maid/sys/media.nix`**: (From previous audits, often has TODOs for player logic).

## 3. Placeholders

Intentional placeholders used for templates, identification, or search-and-replace during activation.

- **Vicinae Extension (`neg-hello`)**:
    - `index.js`: `// Minimal Vicinae extension placeholder.`
    - `README.md`: `This is a minimal, no-op placeholder extension...`
- **System Activation**:
    - `hosts/telfir/services.nix`: Uses `placeholder_login` and `placeholder_pass` as targets for `sed` replacement in `resilio` config.
- **SOPS**:
    - `modules/user/nix-maid/sys/vdirsyncer.nix`: `config.sops.placeholder.vdirsyncer_google_client_id` (Standard SOPS pattern).

## 4. Legacy / Compatibility Comments

Comments that explain why something is staying "old" or "weird".

- **`modules/core/neg.nix`**: `# Expose helpers under lib.neg for legacy or non-structural use.`
- **`modules/user/nix-maid/cli/envs.nix`**: `# Activation script to ensure profile links (legacy support)`.
- **`modules/user/nix-maid/sys/mail.nix`**: `# For now, matching the legacy/standard notmuch path.`
- **`packages/local-bin/bin/ren`**: `# Prefer neg_pretty_printer; fall back to legacy pretty_printer if present.`

## Recommendations

1. **Clean up `wireguard.nix`**: Once it's confirmed that `wg0` is no longer needed (replaced by SOPS `telfir-wg-quick`), the file can be deleted or the block removed.
2. **Review `nixindex.nix`**: If periodic indexing is not desired, the file should probably be removed or the options explicitly set to `enable = false`.
3. **Address `nekoray.nix`**: If `pkgs.throne` (the successor) is working well as a standalone package (it's in `systemPackages` in that file), the commented-out service can be removed or finalized.

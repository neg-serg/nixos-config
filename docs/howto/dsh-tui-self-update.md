# dsh TUI self-update on NixOS

The terminal UI (`@huiliyi37/dsh-tianshu-tui`) checks npm `latest` for itself at startup and
installs a newer release into `~/.dsh/profiles/tui` with `pnpm add`. On this host that install used
to die with `ERR_PNPM_EROFS`; this note records why, how the `self-update-park-harness` patch fixes
it, and how to verify or roll back.

## What upstream does

`runSelfUpdate()` runs in the background while the TUI paints its first frame (see
[dsh-tui-boot.md](./dsh-tui-boot.md) for the boot line). It:

1. checks `registry.npmjs.org`, then `registry.npmmirror.com` (3 s each) for the `latest` dist-tag,
   cached for 1 h in `~/.dsh-tui/update-cache.json`;
1. if the cached/`latest` version differs from the installed one, runs
   `pnpm add @huiliyi37/dsh-tianshu-tui@<latest>` in the profile dir (`pnpm`/`npm`/`yarn` is chosen
   from the lockfile; this profile is pnpm);
1. on success, notifies and — when the session is blank — restarts into the new bundle.

## Why it failed

The profile's `node_modules/@deepseek-ai` is a symlink to the harness tree in the read-only nix
store (`dshAiStore` in `dsh-market.nix`; the profile must resolve the harness's own copies so the
preset machinery sees one module instance per package). pnpm's `importPackage` writes *through* that
symlink (`mkdir node_modules/@deepseek-ai/cosmokit_tmp_…`) and the store rejects it:

```
[ERR_PNPM_EROFS] [importPackage …/node_modules/@deepseek-ai/cosmokit]
EROFS: read-only file system, mkdir '…/@deepseek-ai/cosmokit_tmp_…'
```

The TUI reported a self-update failure (`pnpm add exited 1`) and blamed the network, which made the
real cause easy to miss.

## The fix

`modules/user/nix-maid/apps/dsh-tui-ru-assets/patch.mjs` replaces `installNpmVersion` (id
`self-update-park-harness`). Around the child process it:

- **parks** `node_modules/@deepseek-ai` when the entry is a symlink (a rename of the symlink itself,
  so the store target is untouched);
- **restores** it when the child settles — `rm -rf` whatever pnpm materialized in its place, then
  rename the parked symlink back. Failures and timeouts restore too;
- on a **successful** install, runs `~/.local/bin/dsh-tui-repatch` (the same `runPatch` script as
  the login/activation services) so the freshly installed bundle is translated before the
  auto-restart loads it. Without that step the host would restart into the raw Chinese build and
  stay there until the next login or rebuild.

`dsh-tui-ru.nix` installs the helper with the rest of the home files. The fix itself reaches the
bundle through the normal patcher path: the activation script on every rebuild and the `dsh-tui-ru`
user service on every login.

## Verify

```bash
# the patch mechanics and the park/restore/re-patch contract
node modules/user/nix-maid/apps/dsh-tui-ru-assets/self-update.test.mjs
```

Live check: `~/.dsh-tui/update-cache.json` holds the cached `latest`; after a restart with a new
release installed, `node_modules/@huiliyi37/dsh-tianshu-tui/package.json` and the profile
`package.json` should both name it, and `node_modules/@deepseek-ai` must still be a symlink to the
store. The EROFS itself reproduces with a bare
`cd ~/.dsh/profiles/tui && pnpm add '@huiliyi37/dsh-tianshu-tui@latest'`; with the fix in the
bundle, the same add goes through.

## Knobs and rollback

| Knob                             | Effect                                                |
| -------------------------------- | ----------------------------------------------------- |
| `DSH_TUI_SKIP_UPDATE=1`          | Disable the startup check entirely (upstream switch). |
| `DSH_TUI_UPDATE_REGISTRY=<urls>` | Comma-separated registry override (upstream switch).  |

Roll back a bad release in the profile:

```bash
cd ~/.dsh/profiles/tui
pnpm add '@huiliyi37/dsh-tianshu-tui@0.1.2-rc.29'
```

The `dsh-tui-ensure` service only reinstalls when the version drops below its floor (`0.1.2-rc.29`),
so a manual pin is not overwritten at the same-or-newer version.

## Nuances

- The patch rewrites a whole upstream function; if upstream changes `installNpmVersion`, the fix
  logs `not present in this version (skipped)` and the EROFS failure returns. Re-anchor the `from`
  block against the new bundle.
- The translation map covers `0.1.2-rc.30` with one leftover Chinese literal (a pre-existing drift
  warning, not a regression); extend `i18n.json` when the string matters.
- The TUI's own failure text suggests the network is at fault. On this host it is almost always the
  store symlink; the same EROFS hits any manual `dsh plugin … add` in a profile, which is why the
  ensure services park the symlink by hand.

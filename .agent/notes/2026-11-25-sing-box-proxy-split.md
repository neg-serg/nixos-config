# 2026-11-25 — sing-box-proxy moved to its own flake

Status: extracted, published and wired. The gaps at the bottom are deliberate and each names how to
close it.

Repository: <https://github.com/neg-serg/sing-box-proxy> (public, branch `main`, initial import
`3c3829f`). There is no live checkout on the host: the flake input points at the repository.

## What moved out of this tree

| was here                                              | now                                                                            |
| ----------------------------------------------------- | ------------------------------------------------------------------------------ |
| `packages/sing-box-proxy/{Cargo.toml,Cargo.lock,src}` | repository root                                                                |
| `packages/sing-box-proxy/default.nix`                 | `default.nix` there (fileset source, standard `meta`, `mainProgram = "proxy"`) |
| —                                                     | `flake.nix`, `flake.lock`, `README.md`, `AGENTS.md`, `LICENSE`, `.gitignore`   |

Nothing else was host glue: the systemd user unit
(`modules/user/nix-maid/sys/user-services/media-proxy.nix`), the secrets (`/run/secrets/proxy-*`),
the AppArmor profile and the `~/.local/bin/proxy` link stay in this repository.

## How the host consumes it

- `flake.nix`: `sing-box-proxy.url = "github:neg-serg/sing-box-proxy"`,
  `inputs.nixpkgs.follows = "nixpkgs"`.
- `packages/overlays/tools.nix`: `pkgs.neg.sing-box-proxy` is the input's
  `packages.<system>.default`. The attribute name is unchanged, so
  `modules/user/nix-maid/cli/local-bin.nix` (`~/.local/bin/proxy`) and
  `ExecStartPre = "%h/.local/bin/proxy gen"` in the user unit keep working.
- `packages/overlay.nix` no longer `callPackage`s a local directory, but the name stays in
  `rustNegNames`, so `rustSlim` still applies.

## Verification done that day

- In the new repository: `nix flake lock`, `nix build` → `bin/proxy`; `nix flake check --no-build`
  evaluates (formatter + package).
- `proxy bogus` prints the usage line and exits 1, i.e. the CLI contract survived the move.
- Here: `just fmt`, `just lint` (18/18 after the README statistic update), `just check`, and the
  toplevel build that contains the new store path.

## Gaps to fix later

1. **No CI in the new repository.** `nix flake check` is only run when someone builds it. Fix: a
   GitHub workflow that runs `nix flake check` on push.
1. **No test suite.** The host dropped every local Rust test tree (including the golden fixtures
   this crate was verified against) in `d5477ecc5`; the extraction carried the crate without one and
   removed the two doc comments that still pointed at `tests/fixtures` and
   `tests/reference/README.md`. Restoring the fixtures from this repository's history would only pin
   a contract the crate no longer promises.
1. **The default `nixpkgs` pin copies this host's rev** (`2786a2a`). A consumer that does not pass
   `inputs.nixpkgs.follows` gets that snapshot; the host does pass it.
1. **The defaults are host-specific** (`$HOME/.config/sing-box-trojan`, `127.0.0.1:10808`,
   `sing-box-proxy.service`). They are overridable through `PROXY_*`, but the project is not a
   general-purpose sing-box front end.

## Commits

- `3c3829f` — initial import (crate + packaging + docs).
- This tree: the extraction commit (input, overlay entry, package removal, README statistic).

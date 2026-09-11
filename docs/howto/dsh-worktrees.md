# dsh-worktree: parallel dsh sessions in isolated git worktrees

`dsh-worktree` (in `packages/local-bin/bin/`, so it lands in `~/.local/bin`) gives every task its
own git worktree, its own branch and its own dsh session. Nothing has to be stashed and two agents
never write to the same working copy at the same time.

It is a plain POSIX `sh` script with no dependencies beyond `git` — deliberately not a wrapper
around `workmux`/`worktrunk`/`vibe-kanban`, so there is nothing extra to install or keep in sync.

## Why a worktree and not a branch

`git worktree add` creates a second check-out of the same repository that shares the object store
(the tree's `.git` is a file pointing back at the main repository). Switching branches in place
would move the working copy under a running agent; a separate directory does not.

**Trees live outside the repository**, under `$DSH_WORKTREE_ROOT` (default `~/.dsh/worktrees`),
keyed by `<repo-name>-<sha1(cwd)[0:8]>/<name>`. That is the point: an in-repo `.worktrees/` (what
Claude Code and Gemini CLI do with `.claude/`/`.gemini/`) shows up as an untracked directory in
every `git status` the agent runs. The guard test asserts the main checkout stays clean.

## Usage

```sh
dsh-worktree new <name> [--from REF] [--open auto|kitty|zellij|print]
                        [--cmd CMD] [--copy RELPATH]... [--branch BR]
dsh-worktree list
dsh-worktree path <name>
dsh-worktree rm <name> [--force]
dsh-worktree prune
```

| Command       | Behaviour                                                                                        |
| ------------- | ------------------------------------------------------------------------------------------------ |
| `new <name>`  | `git worktree add -b wt/<name> <root>/<name> <HEAD>` (or `--from REF`), then opens a pane for it |
| `list`        | trees belonging to this repository with their branch                                             |
| `path <name>` | prints the directory — use `cd "$(dsh-worktree path x)"`                                         |
| `rm <name>`   | `git worktree remove`; refuses a dirty tree, `--force` removes it anyway; the branch is kept     |
| `prune`       | `git worktree prune` for trees deleted by hand                                                   |

`new` prints the worktree path on **stdout** (diagnostics go to stderr), so
`d=$(dsh-worktree new x --open print)` is safe.

### Opening a pane

`--open auto` (the default) picks the first that works: **kitty** when `KITTY_LISTEN_ON` is set and
`kitty @ ls` answers, else **zellij** when inside a zellij session, else it just prints the command
to run. The exact invocations, verified against the installed versions:

```sh
kitty @ launch --type=tab --cwd <path> --tab-title wt:<name> -- dsh --profile tui
zellij action new-pane --cwd <path> --name wt:<name> -- dsh --profile tui
```

kitty needs `allow_remote_control yes` (already set in `files/kitty/kitty.conf`).

### Environment

| Variable                   | Effect                                                                                                              |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `DSH_WORKTREE_ROOT`        | where trees live (default `~/.dsh/worktrees`)                                                                       |
| `DSH_WORKTREE_CMD`         | what a launched pane runs (default `dsh --profile tui`; `dsh` has no default profile, it must be named explicitly)  |
| `DSH_WORKTREE_POST_CREATE` | hook run **inside** the new tree after creation, e.g. `ln -s ../../node_modules node_modules` to avoid a re-install |

Gitignored files (`.env`, local editor config) do not follow a worktree into existence: pass
`--copy .env` for the ones a task needs, or use the post-create hook.

## From inside a session: `/worktree`

The `dsh-worktree` plugin (`modules/user/nix-maid/apps/dsh-worktree`, mounted by `dsh-tui-ru.nix`)
registers the same verbs as a slash command, so a session can spawn a worker session beside itself
instead of leaving the terminal:

```text
/worktree new auth-fix --copy .env     # tree + branch + a kitty/zellij pane running dsh there
/worktree list
/worktree path auth-fix
/worktree rm auth-fix --force
/worktree                              # bare = list
```

The plugin owns no policy: it only validates the verb and forwards argv to the helper, so every rule
above (root, branch naming, launcher, `--force`) has one implementation.

One seam is worth knowing about: the harness's `ctx.subprocess` service **deliberately scrubs
`DSH_*` names** out of a child's environment (harness identity must not leak implicitly), and
`DSH_WORKTREE_*` is exactly such a name. The plugin therefore forwards those three variables
explicitly through the spawn spec's `env`, which merges after the scrub — without that, a tree
created from inside a session would land in the default root while the shell's `dsh-worktree` used
the configured one.

## Guard

`scripts/dev/check-dsh-worktree.sh` (29 assertions) creates a throwaway repository in `$TMPDIR` and
pins the contract — clean main checkout, own branch, populated tree, rejected name/branch
collisions, rejection outside a repository, `--copy` and the post-create hook, and `rm` refusing a
dirty tree. It is wired into `just check` as the `dsh-worktree-guard` flake check, so a regression
fails the gate rather than a session.

## Caveats

- `rm` deletes the tree, not the branch. Clean up with `git branch -D wt/<name>` when the work is
  merged or abandoned.
- A tree that is deleted with `rm -rf` leaves a stale `.git/worktrees/<name>` registration; run
  `dsh-worktree prune`.
- Worktrees share the object store, so `git gc`/refs are shared with the main checkout — that is
  intended, but it also means a `git worktree` cannot be moved between machines independently.

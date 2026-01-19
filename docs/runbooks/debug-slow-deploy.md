# Debugging Slow Deployment

This guide describes how to analyze why `just deploy` (via `nh`) takes ~10s even with no changes.

## 1. Isolate the Underlying Command

`nh` is a wrapper. To profile the actual work, we first need to replicate what it does using raw Nix
commands.

Run to confirm the raw Nix evaluation time:

```bash
# Clean eval cache to reproduce the "slow" run
rm -rf ~/.cache/nix/eval-cache-v*

# Measure pure evaluation time (no build, no activation)
time nix build .#nixosConfigurations.telfir.config.system.build.toplevel --dry-run
```

If this command is fast (< 1s), the bottleneck is **`nh` itself** (likely its Git operations). If
this command is slow (~10s), the bottleneck is **Nix evaluation**.

## 2. Profiling `nh` (Git/IO Bottleneck)

If raw Nix is fast, `nh` is likely spending time copying/fetching the git tree. Use `strace` to see
what `nh` is doing.

```bash
# Trace file operations and child processes
strace -f -e trace=file,process -o trace.log nh os switch . --hostname telfir --dry-run
```

Analyze `trace.log` (or Use `strace -c` for summary) to see if it's walking the entire `.git`
directory or copying thousands of files.

## 3. Profiling Nix Evaluation (CPU Bottleneck)

If raw Nix is slow, we need to profile the Nix expression evaluator.

### A. Verbose Evaluation

See which files are being loaded or copied to store.

```bash
nix build .#nixosConfigurations.telfir.config.system.build.toplevel --dry-run -vvv
```

Look for pauses in the output or repeated copying of sources to `/nix/store`.

### B. Count System Calls

Check if Nix is hammering the filesystem (e.g., reading 10k files).

```bash
strace -c nix build .#nixosConfigurations.telfir.config.system.build.toplevel --dry-run
```

### C. Valgrind / Callgrind (Deep Profiling)

To see exactly which C++ functions in Nix (or which usage of `builtins`) are consuming CPU.

**Requirements:** `valgrind`, `kcachegrind` (for visualization).

1. **Run with Callgrind:** We profile `nix-instantiate` because that's where evaluation happens.

   ```bash
   # Note: This will be VERY slow to run (10-50x slower), but precise.
   valgrind --tool=callgrind --callgrind-out-file=callgrind.nix.out \
     nix-instantiate --eval --strict --json \
     .#nixosConfigurations.telfir.config.system.build.toplevel > /dev/null
   ```

1. **Analyze Results:** Open the output file in KCachegrind:

   ```bash
   kcachegrind callgrind.nix.out
   ```

   - Look for `Nix::EvalState::forceValue` (evaluating attributes).
   - Look for `Nix::PrimOp::check` (builtins).
   - If you see excessive time in `sys_read` / `stat`, it's IO bound (too many files in imports).
   - If you see `check` or regex functions, it might be heavy logic in modules.

## 4. Common Causes in NixOS

1. **Git Input Fetching**: If using `git+file://`, Nix creates a git archive every time. Large
   `.git` folder = slow.
   - *Fix*: Use `path:.` instead of `git+file:.` (if pureness isn't strict requirement) or optimize
     git repo.
1. **Slow Imports**: Importing huge lists of packages or recursively reading dirs
   (`builtins.readDir` on large trees).
1. **IFD (Import From Derivation)**: If evaluation triggers builds (e.g., fetching a plugin via
   `fetchFromGitHub` *during eval* to get its `default.nix`).

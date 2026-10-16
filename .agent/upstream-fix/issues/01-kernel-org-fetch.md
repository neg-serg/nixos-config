# Issue draft: `builtins.fetchGit` cannot fetch from git.kernel.org

**Title:** `builtins.fetchGit` fails against git.kernel.org while `git` (and Nix) fetch the same
revision

## What happens

```console
$ fix eval --impure -E 'builtins.fetchGit {
    url = "https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git";
    rev = "4c0f3697118eb3a708ea79175f7f07c43339bfab";
    shallow = true;
  }'
error: fetching 'https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git' failed: FetchGitFailed
```

The failure is immediate (single-digit milliseconds after the fetch starts), not a timeout. `ref` +
`shallow = true` fails the same way, and so does a full (non shallow) fetch.

## What works

- The same expression against a GitHub repository succeeds (and Codeberg git inputs resolve fine in
  a flake here), so the client itself works.
- `git ls-remote https://git.kernel.org/...` works from the same machine;
  `git fetch --depth 1 origin <rev>` works too.
- Nix fetches the same tree successfully — its git fetcher shells out to `git`.

## Evidence gathered so far

- `strace -f -e trace=network`: the TCP connection to `git.kernel.org:443` **succeeds** (the IPv6
  attempt gets `ENETUNREACH`, the IPv4 one connects), so this is not DNS or connectivity.
- `curl '<url>/info/refs?service=git-upload-pack'` shows a normal advertisement: protocol v0 with
  `multi_ack thin-pack side-band side-band-64k ofs-delta shallow deepen-since …`, and protocol v2
  with `ls-refs=unborn`, `fetch=shallow wait-for-done`, `bundle-uri`.

So the connection is established and the server answers a standard advertisement, and the failure
happens afterwards, inside the client's exchange — but `FetchGitFailed` is the generic tag and no
underlying `ziggit` diagnostic is surfaced to the user.

## Requests

1. Is git.kernel.org (or this server shape: cgit in front of git-http-backend) known to be
   unsupported? If it is a bug, I am happy to help chase it.
1. Could the error path surface the underlying diagnostic (the `ziggit.Diagnostic` the transport
   already collects)? Right now the mapped error hides exactly the information needed to report
   this.
1. As a stopgap I have a patch that falls back to the system `git` when the built-in fetch fails at
   the transport level — see the draft PR. Would that be acceptable, and would you want it opt-in?

## Workaround for users today

A local mirror keeps the config buildable: `git fetch --depth 1 <url> <rev>` into a local repository
and point the expression at `file:///path` (or, in Nix, keep using Nix's fetcher, which shells out
to `git`).

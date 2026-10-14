{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchzip,
  installShellFiles,
  writeText,
  runCommand,
  zig_0_16,
}:
let
  # Upstream master, pinned. The v0.3.0 release predates the flake.lock parser
  # fix (it failed with `InvalidFlakeLock` on locks carrying follows chains,
  # e.g. this repo's), so master is the only usable base — see the patch below
  # for the two local fixes on top.
  src = fetchFromGitHub {
    owner = "psyclyx";
    repo = "fix";
    rev = "e0c1f6d699894e3fcbb480c8e7445ddd3b9467fa"; # main HEAD (no newer release)
    hash = "sha256-z5nkv0cKEebjRzgxuAJOJPVluipibhk406FT0BMtiKo=";
  };

  # `fix` resolves its zig dependencies — zurl, ziggit, and their own pins of
  # zurl/nss/public-suffix-list — over the network at configure time. The
  # upstream host (git.lilithsemi.com) serves nothing to this machine (zig
  # fetch and `git clone` both hang), and a Nix build has no network anyway,
  # so every source is fetched here and wired in as a path dependency
  # (patches/0002-vendor-zig-deps.patch + vendor/*.zon).
  zurl = fetchFromGitHub {
    owner = "LilithSemi";
    repo = "zurl";
    rev = "388fa599799cb52816036bbf5da0887a1a83e2d3"; # fix's own pin
    hash = "sha256-2TYCoDhU2He8nKHqsHFAZBhBXY8TQOG9O4X0vIV86Es=";
  };
  zurlForZiggit = fetchFromGitHub {
    owner = "LilithSemi";
    repo = "zurl";
    rev = "7a8bf3eb8c4bb79055d2a9e542ff7a4ee7dd312b"; # ziggit's pin of zurl
    hash = "sha256-Jb7dYL+H5DdrYuLVvSsNzJ7GEIPW8GoX/SQ/mZj0W4U=";
  };
  ziggit = fetchFromGitHub {
    owner = "LilithSemi";
    repo = "ziggit";
    rev = "33476955c813e3e36b0addf4a61dcedf0dfe42d6"; # fix's own pin
    hash = "sha256-tBX7TQG5EdTtznFVG7NLN0lhkkyhGVeZnYGzr5gNuWI=";
  };
  nss = fetchzip {
    # The same tag zurl's build.zig.zon pins.
    url = "https://github.com/mozilla/nss/archive/refs/tags/NSS_3_111_RTM.tar.gz";
    hash = "sha256-GFtoSvLF5nAwBIiMa9CeEl5geAOK60gG2tjuQFubgYs=";
  };
  publicSuffixList = fetchzip {
    # The same commit zurl's build.zig.zon pins.
    url = "https://github.com/publicsuffix/list/archive/3955e3ec29b94c3cca7bd4509c5f14a7c0959e26.tar.gz";
    hash = "sha256-rVuhaaUr/h4GJhHA7oG6Gkcm90yrFsZONlHpP8ldsAU=";
  };

  # Flake used by the smoke test: probes the impure constants that pure eval
  # must omit (Nix parity).
  smokeFlake = writeText "fix-smoke-flake.nix" ''
    {
      outputs = { self }: {
        hasCurrent = builtins ? currentSystem;
      };
    }
  '';
in
stdenv.mkDerivation (finalAttrs: {
  pname = "fix";
  version = "0.3.0-unstable-2026-10-14";

  inherit src;

  patches = [
    # Local fixes on top of the pin: a bare path that is a git work-tree root
    # resolves as `git+file` when the tree is written to the store (Nix
    # parity; the raw directory copy pulled repository junk into the store and
    # tripped the 128 MiB file guard), and pure eval omits
    # currentSystem/currentTime like Nix does.
    ./patches/0001-flake-git-worktree-and-pure-builtins.patch
    # Rewrite the two zig dependencies to the vendored trees (see above).
    ./patches/0002-vendor-zig-deps.patch
  ];

  postPatch = ''
    mkdir -p vendor
    cp -r ${zurl} vendor/zurl
    cp -r ${zurlForZiggit} vendor/zurl_for_ziggit
    cp -r ${ziggit} vendor/ziggit
    cp -r ${nss} vendor/nss
    cp -r ${publicSuffixList} vendor/psl

    # Store checkouts are read-only and cp keeps the source mode: the copies
    # below need the write bit before the zon rewrite can touch them.
    chmod -R u+w vendor

    # The vendored dependencies carry their own zon files; point them at the
    # sibling trees instead of the unreachable upstream URLs.
    cp ${./vendor/ziggit.zon} vendor/ziggit/build.zig.zon
    cp ${./vendor/zurl.zon} vendor/zurl/build.zig.zon
    cp ${./vendor/zurl.zon} vendor/zurl_for_ziggit/build.zig.zon
  '';

  nativeBuildInputs = [
    zig_0_16.hook
    installShellFiles
  ];

  postInstall = ''
    install -Dm444 ${src}/contrib/direnv/fix.sh $out/share/fix/direnv/fix.sh
    install -Dm444 ${src}/LICENSE $out/share/licenses/fix/LICENSE
    install -Dm444 ${src}/LICENSES/nlohmann-json-MIT.txt $out/share/licenses/fix/nlohmann-json-MIT.txt
    install -Dm444 ${src}/LICENSES/zig-MIT.txt $out/share/licenses/fix/zig-MIT.txt
  ''
  + lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd fix \
      --bash <($out/bin/fix completions bash) \
      --fish <($out/bin/fix completions fish) \
      --zsh <($out/bin/fix completions zsh)
  '';

  # Upstream wraps the binary with mercurial/openssh/gnutar from PATH for `hg:`
  # inputs, ssh-ng stores and archive extraction. Not wrapped here: those
  # closures are unbuilt in this repo's overlaid nixpkgs and would be rebuilt
  # from source (substitute = false), for features this repo does not use.
  # Put `openssh`/`gnutar`/`mercurial` on PATH if such an input ever appears.

  zigBuildFlags = [
    "--release=fast"
    "-Dcpu=baseline"
  ];
  dontSetZigCheck = true;
  dontSetZigDefaultFlags = true;

  # Upstream builds with `dontSetZigCheck`, so nothing exercises the binary in
  # a Nix build; this smoke test covers the packaged artifact end-to-end
  # without a daemon (pure eval never touches the store).
  passthru.tests.smoke = runCommand "fix-smoke" { } ''
    export HOME=$TMPDIR
    export XDG_CACHE_HOME=$TMPDIR/cache XDG_STATE_HOME=$TMPDIR/state XDG_DATA_HOME=$TMPDIR/data
    mkdir -p "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME"

    # fix colours its output; without this the sandbox sees \E[33m3\E[0m and
    # the equality checks below fail on the escape codes.
    export NO_COLOR=1

    fix=${finalAttrs.finalPackage}/bin/fix

    test "$($fix eval -E '1 + 2')" = "3"

    # Pure eval omits the impure constants (`builtins ? currentSystem` is
    # false, so flake-compat guards take the explicit-system branch);
    # `--impure` restores them.
    mkdir -p $TMPDIR/fl
    cp ${smokeFlake} $TMPDIR/fl/flake.nix
    test "$($fix eval --extra-experimental-features flakes --flake "$TMPDIR/fl#hasCurrent")" = "false"
    test "$($fix eval --extra-experimental-features flakes --impure --flake "$TMPDIR/fl#hasCurrent")" = "true"

    touch $out
  '';

  meta = lib.mkMeta {
    description = "Fast Nix language evaluator (patched master; build/switch helper)";
    homepage = "https://github.com/psyclyx/fix";
    license = lib.licenses.mit;
    mainProgram = "fix";
  };
})

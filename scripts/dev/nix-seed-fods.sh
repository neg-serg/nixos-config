#!/usr/bin/env bash
# Seed missing fixed-output derivations into the store through a SOCKS5 proxy.
#
# Why not just set https_proxy for the build: the sandbox runs every build in a
# private network namespace, so a proxy listening on the host's 127.0.0.1 is
# unreachable from inside a build (verified: the same failure with
# `--option sandbox relaxed`; `sandbox = false` is the only mode that shares the
# host network), and the `impureEnvVars` that nixpkgs' fetchurl declares
# (http_proxy, all_proxy, NIX_CURL_FLAGS, ...) are filled from the *daemon's*
# environment, not from the caller's. The sandbox-compatible way to get a
# blocked source into the store is therefore to download it client-side and let
# the fixed-output path appear on its own: `nix-prefetch-url` downloads
# in-process, honours the proxy env vars, and prints exactly the store path the
# derivation expects, because a flat FOD path is name + content hash.
#
# Usage: nix-seed-fods.sh <installable> [nix build args...]
#   nix-seed-fods.sh .#nixosConfigurations.trantor.config.system.build.toplevel
#   nix-seed-fods.sh .#somePackage --option substitute false
#
# Env:
#   NIX_SEED_PROXY    proxy for the client-side download, default
#                     socks5h://127.0.0.1:10808; empty value = direct download
#   NIX_SEED_DRY_RUN  1 = report what would be seeded, download nothing
#
# Both fixed-output modes are reproducible client-side: `flat` is the download
# itself (tarballs, patches) and is fetched as-is, while `nar` — fetchzip,
# fetchFromGitHub — is the unpacked tree, which `nix-prefetch-url --unpack`
# reproduces exactly (it strips a single top-level directory the same way
# fetchzip's default `stripRoot = true` does; verified on a GitHub tar and zip
# of the same tree, where the printed paths match the fetchzip outputs). A FOD
# that *rewrites* the download in its postFetch (fetchpatch normalization,
# decode, stripLen) still cannot be reproduced here and is reported.
#
# None of this needs the full-TUN mode (`tun on`): a TUN interface only added a
# route to hosts that are blocked for direct connections, and every fetch path
# here already goes through the SOCKS5 proxy — client-side for the seeds, the
# daemon environment for the one unsandboxed fetcher at the end.
set -euo pipefail

PROXY="${NIX_SEED_PROXY-socks5h://127.0.0.1:10808}"
DRY_RUN="${NIX_SEED_DRY_RUN:-0}"

usage() {
  cat << 'EOF'
Seed missing fixed-output derivations into the store through a SOCKS5 proxy.

Usage: nix-seed-fods.sh <installable> [nix build args...]

  Env: NIX_SEED_PROXY        proxy URL (default socks5h://127.0.0.1:10808,
                             empty = direct)
       NIX_SEED_DRY_RUN      1 = report only, download nothing
       NIX_SEED_UNSANDBOXED  0 = only report the postFetch FODs instead of
                             letting their own builder fetch them unsandboxed

Exit status: 0 when nothing is left to seed, 1 when a flat or nar FOD could not
be fetched or a derivation could not be inspected.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}
say() { printf '   %s\n' "$*" >&2; }
ok() { printf '✓  %s\n' "$*" >&2; }
warn() { printf '!  %s\n' "$*" >&2; }

case "${1-}" in
  "" | -h | --help)
    usage
    [ -n "${1-}" ] || exit 2
    exit 0
    ;;
esac

installable=$1
shift

command -v jq > /dev/null || die "jq is required"
command -v nix-prefetch-url > /dev/null || die "nix-prefetch-url is required"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

proxy_env=()
if [ -n "$PROXY" ]; then
  proxy_env=(
    "http_proxy=$PROXY"
    "https_proxy=$PROXY"
    "all_proxy=$PROXY"
    "HTTP_PROXY=$PROXY"
    "HTTPS_PROXY=$PROXY"
    "ALL_PROXY=$PROXY"
  )
fi

# 1. Derivations of the target. Instantiation is the expensive part; the eval
#    cache makes the later real build pay it only once.
mapfile -t roots < <(
  nix build --dry-run --json "$@" "$installable" \
    | jq -r '.[] | if type == "string" then . else (.drvPath // empty) end'
)
if [ "${#roots[@]}" -eq 0 ]; then
  ok "nothing to instantiate for $installable"
  exit 0
fi

# 2. Fixed-output derivations in that closure, cheap filters first: the
#    derivation closure, then a raw-text scan for the "algo/hash" output header.
mapfile -t closure < <(
  for drv in "${roots[@]}"; do nix-store -qR "$drv"; done | rg '\.drv$' | sort -u
)
[ "${#closure[@]}" -gt 0 ] || die "empty closure for $installable"
printf '%s\n' "${closure[@]}" > "$tmp/closure.txt"

xargs -a "$tmp/closure.txt" -r rg --text -l -m1 \
  ',"(md5|sha1|sha256|sha512|blake3)","[0-9a-zA-Z+/=]{16,}"' \
  > "$tmp/fods.txt" 2> /dev/null || true
say "${#closure[@]} derivations in the closure, $(wc -l < "$tmp/fods.txt") look fixed-output"

# Output paths of every FOD candidate. Only the `Derive([...])` header is read:
# the rest of the file (inputs, structured attrs) also contains store paths, and
# grabbing those would turn input sources into bogus "outputs".
xargs -a "$tmp/fods.txt" -r rg --text --with-filename -o -m1 -N \
  '^Derive\(\[[^]]*\]' > "$tmp/fod-headers.txt" 2> /dev/null || true

# A `fetchzip` / `fetchFromGitHub` is a fixed-output derivation of the *nar*
# mode, and Nix writes those attrs into the output spec instead of the env:
# `Derive([("out","/nix/store/<hash>-<name>","r:sha256","<hex>")],…)`. The text
# scan above only sees `,"sha256","…"` pairs inside structured attrs (fetchurl,
# fetchpatch), so nar FODs are found from that header: the empty algo slot means
# the hash is in the attrs (flat), and the `r:` prefix is the nar mode.
xargs -a "$tmp/closure.txt" -r rg --text --with-filename -o -m1 -N \
  'Derive\(\[\("out","/nix/store/[a-z0-9]{32}-[^"]+","(r:)?(md5|sha1|sha256|sha512)","[0-9a-f]{32,}"\)' \
  > "$tmp/hdr-fods.txt" 2> /dev/null || true

hdr_re='^Derive\(\[\("out","(/nix/store/[a-z0-9]{32}-[^"]+)","(r:)?(md5|sha1|sha256|sha512)","([0-9a-f]{32,})"\)'
while IFS= read -r line; do
  drv=${line%%:*}
  [[ $drv == *.drv ]] || continue
  header=${line#*:}
  [[ $header =~ $hdr_re ]] || continue
  mode=flat
  [ -n "${BASH_REMATCH[2]}" ] && mode=nar
  printf '%s\t%s\t%s\t%s\t%s\n' "$drv" "${BASH_REMATCH[1]}" "$mode" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}"
done < "$tmp/hdr-fods.txt" > "$tmp/hdr-map.tsv"
say "$(wc -l < "$tmp/hdr-map.tsv") carry their hash in the Derive header (nar FODs)"

mapfile -t missing < <(
  {
    while IFS= read -r line; do
      drv="${line%%.drv:*}.drv"
      header=${line#*.drv:}
      [[ $header =~ /nix/store/[a-z0-9]{32}-[A-Za-z0-9+._-]+ ]] || continue
      out=${BASH_REMATCH[0]}
      [ -n "$drv" ] || continue
      if [ -e "$out" ]; then continue; fi
      printf '%s\t%s\n' "$drv" "$out"
    done < "$tmp/fod-headers.txt"
    while IFS=$'\t' read -r drv out _; do
      [ -n "$drv" ] || continue
      if [ -e "$out" ]; then continue; fi
      printf '%s\t%s\n' "$drv" "$out"
    done < "$tmp/hdr-map.tsv"
  } | sort -u
)

if [ "${#missing[@]}" -eq 0 ]; then
  ok "every fixed-output derivation in scope is already in the store"
  exit 0
fi
say "${#missing[@]} fixed-output derivations missing from the store"

# Expand mirror:// URLs the way nixpkgs' fetchurl builder does, by sourcing the
# mirrors list the derivation itself carries.
resolve_urls() {
  local url=$1 mirror_file=$2 site rest m arr
  local -a mirrors=()
  if [[ $url != mirror://* ]]; then
    printf '%s\n' "$url"
    return
  fi
  site=${url#mirror://}
  site=${site%%/*}
  rest=${url#mirror://"$site"/}
  if [ -z "$mirror_file" ]; then
    warn "no mirrors list for $url"
    return
  fi
  # The mirrors list is an ordinary build input and may not be realised yet;
  # building it needs no network.
  if [ ! -f "$mirror_file" ]; then
    nix-store --realise "$mirror_file" > /dev/null 2>&1 || true
  fi
  if [ ! -f "$mirror_file" ]; then
    warn "cannot realise mirrors list $mirror_file for $url"
    return
  fi
  # Two list formats exist across nixpkgs revisions, both plain bash fragments:
  # `declare -a _mirror_<site>=(...)` (current) and `<site>='url1 url2'` (older).
  set +u
  # shellcheck disable=SC1090
  source "$mirror_file" || true
  arr="_mirror_${site}[@]"
  if declare -p "_mirror_${site}" > /dev/null 2>&1; then
    mirrors=("${!arr}")
  elif declare -p "$site" > /dev/null 2>&1; then
    read -r -a mirrors <<< "${!site}"
  fi

  set -u
  for m in "${mirrors[@]}"; do
    printf '%s%s\n' "$m" "$rest"
  done
}

seeded=0
skipped=0
failed=0
leftovers=()

for entry in "${missing[@]}"; do
  drv=${entry%%$'\t'*}
  expected_path=${entry#*$'\t'}
  # The store path name is the FOD output name: <32-char hash>-<name>.
  name=${expected_path##*/}
  name=${name#*-}

  attrs=$(
    nix derivation show "$drv" | jq -r '
      # Legacy derivations stringify their attrs into env, structured ones keep a
      # typed block; both may hold an empty string, which `//` would not fall
      # back on, hence first_nonempty().
      def first_nonempty($default; $values):
        ($values | map(select(. != null and . != "")) | .[0]) // $default;
      .derivations | to_entries[0].value
      | (.structuredAttrs // {}) as $s
      | [
          first_nonempty("sha256"; [$s.outputHashAlgo, .env.outputHashAlgo]),
          first_nonempty("flat"; [$s.outputHashMode, .env.outputHashMode]),
          first_nonempty(""; [$s.outputHash, .env.outputHash]),
          first_nonempty(""; [$s.mirrorsListFile, .env.mirrorsListFile,
                            $s.mirrorsFile, .env.mirrorsFile]),
          (first_nonempty([]; [$s.urls, .env.urls])
            | if type == "array" then . else (split(" ") | map(select(length > 0))) end
            | join(" ")),
          (first_nonempty("1"; [$s.stripRoot, .env.stripRoot])
            | if . == true then "1" elif . == false then "0" else tostring end),
          (first_nonempty(""; [$s.postFetch, .env.postFetch]) | length | tostring)
        ] | join("\u001f")' 2> /dev/null

  ) || attrs=""
  if [ -z "$attrs" ]; then
    warn "$name: cannot inspect $drv"
    failed=$((failed + 1))
    continue
  fi
  IFS=$'\x1f' read -r algo mode expected mirror_file urls strip_root post_fetch_len <<< "$attrs"

  # The header copy wins: a nar FOD carries no outputHash attrs at all, and a
  # flat one whose hash Nix wrote into the header has no env copy either.
  hdr=$(awk -F'\t' -v d="$drv" '$1 == d { print $3 "\t" $4 "\t" $5; exit }' "$tmp/hdr-map.tsv")
  if [ -n "$hdr" ]; then
    IFS=$'\t' read -r mode algo expected <<< "$hdr"
  fi

  # `flat` is downloaded as-is; `nar` needs the archive unpacked before hashing.
  unpack=()
  if [ "$mode" = nar ]; then
    # fetchzip's builder only strips the top level when the unpacked archive has
    # exactly one entry; with stripRoot = false the tree is kept as unpacked and
    # there is no client-side equivalent of that layout.
    if [ "$strip_root" != 1 ]; then
      warn "$name: fetchzip with stripRoot = false, cannot be reproduced here"
      leftovers+=("$drv")
      continue
    fi
    # Its postFetch *is* the unpacker (download → unpackFile → stripRoot → chmod)
    # — structured attrs put the whole extraction there, so a non-empty postFetch
    # is expected for nar and says nothing about the download being rewritten.
    unpack=(--unpack)
  elif [ "$mode" != flat ]; then
    warn "$name: fixed-output mode '$mode' cannot be seeded offline"
    leftovers+=("$drv")
    continue
  elif [ "$post_fetch_len" != 0 ]; then
    # A flat FOD's postFetch rewrites the download (fetchpatch normalization,
    # decode, stripLen), so the raw bytes are not the fixed-output content.
    warn "$name: postFetch rewrites the download, cannot be seeded offline"
    leftovers+=("$drv")
    continue
  fi
  case "$algo" in
    md5 | sha1 | sha256 | sha512) ;;
    *)
      warn "$name: unsupported hash algorithm '$algo', skipping"
      skipped=$((skipped + 1))
      continue
      ;;
  esac
  # outputHash may be SRI ("sha256-…="), base16 hex (rust tarballs) or base32,
  # while nix-prefetch-url always prints base32; compare in base32 either way.
  # A wrong --from is rejected by length, so trying the formats in order is safe.
  converted=""
  for fmt in sri base16 base32; do
    converted=$(nix hash convert --hash-algo "$algo" --from "$fmt" --to base32 "$expected" 2> /dev/null) && break
    converted=""
  done
  if [ -z "$converted" ]; then
    warn "$name: cannot convert hash $expected"
    failed=$((failed + 1))
    continue
  fi
  expected=$converted
  if [ -z "$urls" ]; then
    warn "$name: no URLs recorded in the derivation, skipping"
    skipped=$((skipped + 1))
    continue
  fi

  # https first: ftp and http mirrors are usually the slow ones.
  mapfile -t candidates < <(
    for url in $urls; do resolve_urls "$url" "$mirror_file"; done | rg '^https://' || true
  )
  if [ "${#candidates[@]}" -eq 0 ]; then
    mapfile -t candidates < <(for url in $urls; do resolve_urls "$url" "$mirror_file"; done)
  fi
  if [ "${#candidates[@]}" -eq 0 ]; then
    warn "$name: no usable URL, skipping"
    skipped=$((skipped + 1))
    continue
  fi

  if [ "$DRY_RUN" = 1 ]; then
    say "would seed $name from ${candidates[0]}"
    seeded=$((seeded + 1))
    continue
  fi

  # Two passes: through the proxy first, then direct. The direct pass keeps the
  # script usable on hosts where no socks5 proxy is running.
  done_one=0
  content_differs=0
  needs_build=0
  for pass in proxy direct; do
    fetch_env=()
    if [ "$pass" = proxy ]; then
      if [ "${#proxy_env[@]}" -eq 0 ]; then continue; fi
      fetch_env=("${proxy_env[@]}")
    else
      # No direct retry when a download already succeeded with other content:
      # the network is fine, the mirror is just stale.
      if [ "$content_differs" = 1 ]; then break; fi
      say "retrying $name without the proxy"
    fi
    for url in "${candidates[@]}"; do
      say "fetching $name"
      say "  $url"
      if [ "${#fetch_env[@]}" -gt 0 ]; then
        got=$(env "${fetch_env[@]}" nix-prefetch-url --type "$algo" --name "$name" --print-path "${unpack[@]}" "$url" 2> "$tmp/err")
      else
        got=$(nix-prefetch-url --type "$algo" --name "$name" --print-path "${unpack[@]}" "$url" 2> "$tmp/err")
      fi || {
        warn "download failed: $(tail -n 1 "$tmp/err")"
        continue
      }
      got_hash=$(sed -n 1p <<< "$got")
      got_path=$(sed -n 2p <<< "$got")
      if [ "$got_hash" != "$expected" ] || [ "$got_path" != "$expected_path" ]; then
        if [ "$mode" = nar ]; then
          # Not a stale mirror: the archive unpacked to a different tree than the
          # derivation's own unpacker produced. Nothing client-side reproduces
          # that, so hand the derivation to the unsandboxed fetch below.
          warn "$name: unpacked tree differs from the derivation ($got_path)"
          needs_build=1
          break
        fi
        warn "mirror has different content (want $expected), trying next"
        content_differs=1
        continue
      fi
      ok "$name → $got_path"
      done_one=1
      seeded=$((seeded + 1))
      break
    done
    if [ "$done_one" -eq 1 ] || [ "$needs_build" -eq 1 ]; then break; fi
  done

  if [ "$done_one" -eq 0 ]; then
    if [ "$needs_build" -eq 1 ]; then
      leftovers+=("$drv")
    else
      warn "$name: every candidate URL failed"
      failed=$((failed + 1))
    fi
  fi
done

# A fixed-output derivation that *rewrites* the download (postFetch) cannot be
# reproduced from the client side. The remaining option is to run *that one
# derivation* with the host network (`sandbox = false`) while the real build
# stays sandboxed: it is a nixpkgs fetcher, not the package being built.
# Its network access rides the same SOCKS5 proxy without any TUN: nixpkgs'
# fetchurl/fetchzip declare `impureEnvVars`, and those are taken from the
# *nix-daemon's* environment, which sets http_proxy/https_proxy/all_proxy
# (`systemd.services.nix-daemon.environment`, flag `features.net.nixDaemonProxy`).
# Verified with a probe FOD whose builder printed the daemon env: the value
# arrives with sandbox on and off, i.e. that env is the only lever.
if [ "${#leftovers[@]}" -gt 0 ]; then
  if [ "$DRY_RUN" = 1 ]; then
    say "${#leftovers[@]} derivations would be fetched with sandbox = false"
  elif [ "${NIX_SEED_UNSANDBOXED:-1}" = 1 ]; then
    say "${#leftovers[@]} derivations get their fetch built with sandbox = false"
    for drv in "${leftovers[@]}"; do
      if nix build --no-link --option sandbox false --option substitute false "$drv" > "$tmp/err" 2>&1; then
        ok "built $drv"
        seeded=$((seeded + 1))
      else
        warn "$drv: unsandboxed fetch failed"
        warn "  $(tail -n 2 "$tmp/err" | tr '\n' ' ')"
        if rg -q 'Could not resolve host|Failed to connect|Connection (refused|timed out)|curl: \(6\)|curl: \(7\)|curl: \(28\)' "$tmp/err"; then
          warn "  network error: check that the daemon proxy is live —"
          warn "    systemctl show nix-daemon -p Environment | rg -o 'https?_proxy=\S+'"
          warn "    systemctl start sing-box-proxy (user unit) when it is down"
        fi
        failed=$((failed + 1))
      fi
    done
  else
    say "${#leftovers[@]} derivations need an unsandboxed fetch (NIX_SEED_UNSANDBOXED=0)"
    skipped=$((skipped + ${#leftovers[@]}))
  fi
fi

printf '\nseeded %d, skipped %d, failed %d\n' "$seeded" "$skipped" "$failed" >&2
[ "$failed" -eq 0 ] || exit 1

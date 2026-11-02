#!/usr/bin/env bash
# Hardlink identical files across the music-AI venv tree to reclaim the space
# that duplicated wheels take.
#
# Every venv under /zero/ai/music-ai carries its own copy of the wheels it
# needs — torch alone is 6.6 GB in the ROCm venvs and 0.3–1.2 GB in the CPU and
# CUDA ones — so venvs pinned to the same build store the same bytes several
# times. This script groups regular files inside `*/lib/python*/site-packages`
# by (size, mode, sha256) and replaces every copy after the first with a
# hardlink. Every venv keeps working: each path still exists and pip/python see
# the usual tree, while the filesystem stores the bytes once (ZFS counts a
# hardlinked inode once, so the freed space is real).
#
# Safety:
#   - only regular files inside site-packages (never bin/, never model dirs);
#   - never touches __pycache__ or *.pyc;
#   - files below --min-size are skipped (metadata is not worth a link);
#   - dry run by default, --apply is required to change anything;
#   - the canonical copy keeps its inode, so deleting one venv never loses data
#     another venv still links to.
#
# Usage:
#   scripts/dev/music-ai-dedupe.sh                  # report only
#   scripts/dev/music-ai-dedupe.sh --apply          # create the hardlinks
#   scripts/dev/music-ai-dedupe.sh --root DIR --apply
#
# Writing outside the repo needs a sandbox escalation when run by an agent.
set -euo pipefail

root="/zero/ai/music-ai"
min_size=$((1024 * 1024))
apply=0

usage() {
  sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      root="${2:?--root needs a directory}"
      shift 2
      ;;
    --min-size)
      min_size="${2:?--min-size needs a byte count}"
      shift 2
      ;;
    --apply)
      apply=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[ -d "$root" ] || {
  echo "no such directory: $root" >&2
  exit 2
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# 1) Every site-packages dir under the venv root.
find "$root" -maxdepth 5 -type d -path '*/lib/python*/site-packages' \
  -print0 > "$work/site-packages"
mapfile -d '' site_packages < "$work/site-packages"
if [ "${#site_packages[@]}" -eq 0 ]; then
  echo "no venvs under $root" >&2
  exit 2
fi
echo "scanning ${#site_packages[@]} venvs under $root"

# 2) Candidate files: size, mode, inode, path. `-size +Nc` keeps the cut in
#    bytes so --min-size means what it says.
find "${site_packages[@]}" \
  -type f \
  ! -path '*/__pycache__/*' \
  ! -name '*.pyc' ! -name '*.pyo' \
  -size +"${min_size}"c \
  -printf '%s\t%m\t%i\t%p\n' > "$work/all"

# 3) Only sizes that appear more than once can hold duplicates.
awk -F'\t' '{count[$1]++} END {for (s in count) if (count[s] > 1) print s}' \
  "$work/all" | sort > "$work/sizes"
awk -F'\t' 'NR == FNR {want[$1]; next} ($1 in want)' \
  "$work/sizes" "$work/all" > "$work/candidates"

# 4) Hash the candidates; keep the first path of every hash group as canonical.
while IFS=$'\t' read -r size mode inode path; do
  hash="$(sha256sum -- "$path")"
  printf '%s\t%s\t%s\t%s\t%s\n' "${hash%% *}" "$size" "$mode" "$inode" "$path"
done < "$work/candidates" | sort > "$work/hashed"

# 5) Report: link count per group, space already shared counted once.
awk -F'\t' '
  {
    group = $1 "\t" $3
    files[group]++
    if (!seen[group "\t" $4]++) inodes[group]++
    size[group] = $2
  }
  END {
    for (group in files) {
      if (files[group] < 2) continue
      groups++
      links += inodes[group] - 1
      if (inodes[group] > 0)
        free += size[group] * (inodes[group] - 1)
    }
    printf "duplicate groups: %d, links to create: %d\n", groups, links
    printf "space to reclaim: %.1f GiB\n", free / 1073741824
  }
' "$work/hashed"

if [ "$apply" -eq 0 ]; then
  echo
  echo "dry run: pass --apply to create the hardlinks"
  exit 0
fi

# 6) Apply: hardlink every non-canonical copy onto the first file of its group.
made=0
failed=0
awk -F'\t' '{print $1 "\t" $3 "\t" $5}' "$work/hashed" \
  | awk -F'\t' '
    {
      group = $1 "\t" $2
      if (!(group in canon)) { canon[group] = $3; next }
      print canon[group] "\t" $3
    }
  ' > "$work/pairs"

while IFS=$'\t' read -r canonical duplicate; do
  if ln -f -- "$canonical" "$duplicate" 2> "$work/err"; then
    made=$((made + 1))
  else
    failed=$((failed + 1))
    printf 'skip %s: %s\n' "$duplicate" "$(cat "$work/err")" >&2
  fi
done < "$work/pairs"

printf 'hardlinked %d files, %d failures\n' "$made" "$failed"
[ "$failed" -eq 0 ]

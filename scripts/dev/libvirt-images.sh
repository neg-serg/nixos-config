#!/usr/bin/env bash
# Safe offline maintenance for libvirt qcow2 images on ZFS.
#
# Sanoid already snapshots tank/nixos hourly/daily/weekly/monthly, so every
# image has recovery points. This helper adds an explicit pre-change snapshot
# and performs an offline qcow2 rewrite; it aborts if a VM has the image open.
#
# Usage:
#   sudo libvirt-images.sh list
#   sudo libvirt-images.sh snapshot [label]
#   sudo libvirt-images.sh check IMAGE
#   sudo libvirt-images.sh compact IMAGE
#   sudo libvirt-images.sh restore SNAPSHOT IMAGE
#
# IMAGE must live in LIBVIRT_IMAGE_DIR (default /var/lib/libvirt/images).
# Snapshot names are looked up on LIBVIRT_ZFS_DATASET (default tank/nixos).
set -euo pipefail

IMAGE_DIR="${LIBVIRT_IMAGE_DIR:-/var/lib/libvirt/images}"
DATASET="${LIBVIRT_ZFS_DATASET:-tank/nixos}"

die() {
  printf 'libvirt-images: %s\n' "$*" >&2
  exit 2
}

need_root() {
  [ "$(id -u)" -eq 0 ] || die "run as root (or via sudo): zfs/qemu image replacement needs it"
}

need_tool() {
  command -v "$1" > /dev/null 2>&1 || die "missing tool: $1"
}

image_path() {
  local image="${1:?image path required}"
  case "$image" in
    "$IMAGE_DIR"/*.qcow2) ;;
    *) die "image must be a .qcow2 under $IMAGE_DIR: $image" ;;
  esac
  [ -f "$image" ] || die "no such image: $image"
  printf '%s\n' "$image"
}

dataset_mount() {
  zfs get -H -o value mountpoint "$DATASET"
}

snapshot_name() {
  local label="${1:-manual}"
  printf '%s@libvirt-%s-%s\n' "$DATASET" "$(date +%Y%m%d-%H%M%S)" "$label"
}

cmd_list() {
  need_tool qemu-img
  printf '== images in %s ==\n' "$IMAGE_DIR"
  find "$IMAGE_DIR" -maxdepth 1 -type f -name '*.qcow2' -printf '%s %p\n' \
    | sort -nr \
    | while read -r size image; do
      printf '%10s  %s\n' "$(numfmt --to=iec "$size")" "$(basename "$image")"
      qemu-img info "$image" 2> /dev/null | awk '
        /virtual size/ { print "            virtual " $3 " " $4 }
        /disk size/ { print "            disk    " $3 " " $4 }
        /corrupt/ { print "            " $0 }
      '
    done
  if command -v zfs > /dev/null 2>&1 && [ "$(id -u)" -eq 0 ]; then
    printf '\n== recent %s snapshots ==\n' "$DATASET"
    zfs list -H -t snapshot -o name,creation -s creation "$DATASET" 2> /dev/null | tail -10
  fi
}

cmd_snapshot() {
  need_root
  need_tool zfs
  local snap
  snap="$(snapshot_name "${1:-manual}")"
  zfs snapshot "$snap"
  printf 'created %s\n' "$snap"
  printf 'restore example: sudo %s restore %s windows.qcow2\n' "$0" "$snap"
}

cmd_check() {
  need_tool qemu-img
  local image
  image="$(image_path "${1:-}")"
  qemu-img check "$image"
}

cmd_compact() {
  need_root
  need_tool zfs
  need_tool qemu-img

  local image tmp snap
  image="$(image_path "${1:-}")"
  if command -v fuser > /dev/null 2>&1 && fuser -s "$image" 2> /dev/null; then
    die "image is open by a process (VM running?): $image"
  fi
  if pgrep -af 'qemu-system.*' 2> /dev/null | grep -Fq "$image"; then
    die "a qemu process references the image: $image"
  fi

  snap="$(snapshot_name compact)"
  zfs snapshot "$snap"
  printf 'snapshot: %s\n' "$snap"

  tmp="${image}.compact.$$"
  trap 'rm -f "$tmp"' EXIT
  qemu-img convert -p -c -O qcow2 "$image" "$tmp"
  qemu-img check "$tmp"
  mv -f "$tmp" "$image"
  trap - EXIT

  printf 'compacted: %s\n' "$image"
  printf 'snapshot retained: %s\n' "$snap"
  printf 'rollback: sudo zfs rollback %s   (reverts the whole dataset)\n' "$snap"
  printf 'single-file restore: sudo %s restore %s %s\n' "$0" "$snap" "$(basename "$image")"
}

cmd_restore() {
  need_root
  need_tool zfs
  need_tool qemu-img

  local snap image mount src tmp
  snap="${1:?snapshot name required (dataset@snapshot)}"
  image="$(image_path "${2:-}")"
  mount="$(dataset_mount)"
  [ "$mount" != "-" ] || die "dataset $DATASET is not mounted"
  src="${mount%/}/.zfs/snapshot/${snap#*@}/var/lib/libvirt/images/$(basename "$image")"
  [ -f "$src" ] || die "image not found in snapshot: $src"

  tmp="${image}.restore.$$"
  trap 'rm -f "$tmp"' EXIT
  cp --reflink=auto "$src" "$tmp"
  qemu-img check "$tmp"
  mv -f "$tmp" "$image"
  trap - EXIT
  printf 'restored %s from %s\n' "$image" "$snap"
}

case "${1:-}" in
  list) cmd_list ;;
  snapshot)
    shift
    cmd_snapshot "$@"
    ;;
  check)
    shift
    cmd_check "$@"
    ;;
  compact)
    shift
    cmd_compact "$@"
    ;;
  restore)
    shift
    cmd_restore "$@"
    ;;
  *)
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac

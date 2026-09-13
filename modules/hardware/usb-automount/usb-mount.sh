#!/bin/sh
PATH=$PATH:/run/current-system/sw/bin

usage() {
  echo "Usage: $0 {add|remove} device_name (e.g. sdb1)"
  echo "$1"
  echo "$2"
  exit 1
}

if [ $# -ne 2 ]; then
  usage "$@"
fi

ACTION=$1
DEVBASE=$2
DEVICE="/dev/${DEVBASE}"

# See if this drive is already mounted, and if so where
MOUNT_POINT=$(mount | grep ${DEVICE} | awk '{ print $3 }')

do_mount() {
  if [ -n "${MOUNT_POINT}" ]; then
    echo "Warning: ${DEVICE} is already mounted at ${MOUNT_POINT}"
    exit 1
  fi

  # Get info for this drive: $ID_FS_LABEL, $ID_FS_UUID, and $ID_FS_TYPE
  eval "$(blkid -o udev "${DEVICE}")"

  # Figure out a mount point to use
  LABEL=${ID_FS_LABEL}
  if [ -z "${LABEL}" ]; then
    LABEL=${DEVBASE}
  elif grep -q " /mnt/${LABEL} " /etc/mtab; then
    # Already in use, make a unique one
    LABEL=${LABEL}-${DEVBASE}
  fi
  MOUNT_POINT="/mnt/${LABEL}"

  echo "Mount point: ${MOUNT_POINT}"

  mkdir -p ${MOUNT_POINT}

  # Global mount options
  OPTS="rw,noatime"

  # File system type specific mount options
  case "${ID_FS_TYPE}" in
    vfat) OPTS="${OPTS},users,gid=100,umask=000,shortname=mixed,utf8=1,flush" ;;
    exfat) OPTS="${OPTS},fmask=0000,dmask=0000" ;;
  esac

  if ! mount -o ${OPTS} ${DEVICE} ${MOUNT_POINT}; then
    echo "Error mounting ${DEVICE} (status = $?)"
    rmdir ${MOUNT_POINT}
    exit 1
  fi

  echo "**** Mounted ${DEVICE} at ${MOUNT_POINT} ****"
}

do_unmount() {
  if [ -z "${MOUNT_POINT}" ]; then
    echo "Warning: ${DEVICE} is not mounted"
  else
    umount -l ${DEVICE}
    echo "**** Unmounted ${DEVICE}"
  fi

  # Delete all empty dirs in /mnt that aren't being used as mount points
  for f in /mnt/*; do
    if [ -n "$(find "$f" -maxdepth 0 -type d -empty 2> /dev/null)" ]; then
      if ! grep -q " $f " /etc/mtab; then
        echo "**** Removing mount point $f"
        rmdir "$f"
      fi
    fi
  done
}

case "${ACTION}" in
  add)
    do_mount
    ;;
  remove)
    do_unmount
    ;;
  *)
    usage "$@"
    ;;
esac

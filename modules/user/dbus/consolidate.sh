shopt -s nullglob

# Create all standard dbus-1 subdirectories
for sub in \
  etc/dbus-1/system.d \
  etc/dbus-1/session.d \
  share/dbus-1/system.d \
  share/dbus-1/session.d \
  share/dbus-1/system-services \
  share/dbus-1/services; do
  mkdir -p "$out/$sub"
done

# Merge policy files (*.conf) from system.d and session.d
for dirset in \
  "etc/dbus-1/system.d:*.conf" \
  "share/dbus-1/system.d:*.conf" \
  "share/dbus-1/session.d:*.conf"; do
  subdir="${dirset%%:*}"
  pattern="${dirset##*:}"
  for pkg in $dbusPkgs; do
    srcdir="$pkg/$subdir"
    if [ -d "$srcdir" ]; then
      for f in "$srcdir"/$pattern; do
        [ -f "$f" ] && ln -sfn "$f" "$out/$subdir/$(basename "$f")"
      done
    fi
  done
done

# Merge activation files (*.service) from system-services and services.
# Two packages can ship different filenames for the same D-Bus name (for
# example org.gnome.keyring.service and org.gnome.keyring.portal.service), and
# dbus-broker then logs "Ignoring duplicate name '…'" at error priority on
# every boot — 289 such lines before this dedupe. The first provider wins; the
# link name stays the file's own basename, so activation still works.
declare -A seen_names=()
for dirset in \
  "share/dbus-1/system-services:*" \
  "share/dbus-1/services:*"; do
  subdir="${dirset%%:*}"
  for pkg in $dbusPkgs; do
    srcdir="$pkg/$subdir"
    if [ -d "$srcdir" ]; then
      for f in "$srcdir"/*; do
        [ -f "$f" ] || continue
        name=""
        while IFS= read -r line; do
          case "$line" in
            Name=*)
              name=${line#Name=}
              break
              ;;
          esac
        done < "$f"
        if [ -n "$name" ] && [ -n "${seen_names[$name]:-}" ]; then
          continue
        fi
        [ -n "$name" ] && seen_names[$name]=$f
        ln -sfn "$f" "$out/$subdir/$(basename "$f")"
      done
    fi
  done
done

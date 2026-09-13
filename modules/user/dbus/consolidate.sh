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

# Merge activation files (*.service) from system-services and services
for dirset in \
  "share/dbus-1/system-services:*" \
  "share/dbus-1/services:*"; do
  subdir="${dirset%%:*}"
  for pkg in $dbusPkgs; do
    srcdir="$pkg/$subdir"
    if [ -d "$srcdir" ]; then
      for f in "$srcdir"/*; do
        [ -f "$f" ] && ln -sfn "$f" "$out/$subdir/$(basename "$f")"
      done
    fi
  done
done

mkdir -p "$out/bin"
makeWrapper @QSBIN@ "$out/bin/.qs-wrapped" \
  --prefix QT_PLUGIN_PATH : "@QTBASE@/@QTPLUGINPREFIX@" \
  --prefix QT_PLUGIN_PATH : "@QT5COMPAT@/@QTPLUGINPREFIX_V2@" \
  --prefix QT_PLUGIN_PATH : "@QTWAYLAND@/@QTPLUGINPREFIX_V3@" \
  --prefix QT_PLUGIN_PATH : "@QTSVG@/@QTPLUGINPREFIX_V4@" \
  --prefix QML2_IMPORT_PATH : "@QT5COMPAT_V2@/@QTQMLPREFIX@" \
  --prefix QML2_IMPORT_PATH : "@QTDECLARATIVE@/@QTQMLPREFIX_V2@" \
  --prefix QML2_IMPORT_PATH : "@QTPOSITIONING@/@QTQMLPREFIX_V3@" \
  --prefix QML2_IMPORT_PATH : "@QTSVG_V2@/@QTQMLPREFIX_V4@" \
  --prefix QML2_IMPORT_PATH : "@HIGHLIGHTING@/@QTQMLPREFIX_V5@" \
  --prefix QT_PLUGIN_PATH : "@QTMULTIMEDIA@/@QTPLUGINPREFIX_V5@" \
  --prefix QML2_IMPORT_PATH : "@QTMULTIMEDIA_V2@/@QTQMLPREFIX_V6@" \
  --prefix QML2_IMPORT_PATH : "@QSQMLPATH@" \
  --prefix XDG_DATA_DIRS : "@THEME@/share" \
  --set QT_QPA_PLATFORM wayland \
  --set QML_XHR_ALLOW_FILE_READ 1 \
  --prefix PATH : @QSPATH@

# A bare `qs` must never draw a second panel: quickshell only exits on an
# explicit IPC kill (`qs kill`), so starting it while the panel already
# runs leaves two instances, two overlapping bars and a D-Bus conflict.
# Outside systemd, drop any leftover instance of this config and hand the
# panel back to systemd so it stays supervised. Anything with arguments
# (ipc / kill / -p ...) goes to the real binary untouched, and under
# systemd (INVOCATION_ID set) nothing is intercepted, so the unit can
# always start even if another instance is around.
cat > "$out/bin/qs" << 'SHIM'
#!@shell@
if [ -z "$INVOCATION_ID" ] && [ "$#" -eq 0 ]; then
  for _ in 1 2 3 4 5; do
    @wrapped@ kill >/dev/null 2>&1 || break
    sleep 0.3
  done
  if command -v systemctl >/dev/null 2>&1 && systemctl --user start quickshell.service >/dev/null 2>&1; then
    exit 0
  fi
fi
exec @wrapped@ "$@"
SHIM
substituteInPlace "$out/bin/qs" \
  --replace-fail '@shell@' @RUNTIMESHELL@ \
  --replace-fail '@wrapped@' "$out/bin/.qs-wrapped"
chmod +x "$out/bin/qs"
ln -s qs "$out/bin/quickshell"

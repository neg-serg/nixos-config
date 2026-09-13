interp="$(cat $NIX_CC/nix-support/dynamic-linker)"
basePath="@RUNTIME@"
patchelf --set-interpreter "$interp" --set-rpath "$basePath" "$out/bin/lsfg-vk-cli"
patchelf --set-rpath "$basePath" "$out/lib/liblsfg-vk-layer.so"
# Qt6 UI (lsfg-vk-ui): rpath + plugin/QML import paths via wrapper
qtPath="@QTDECLARATIVE@"
patchelf --set-interpreter "$interp" --set-rpath "$qtPath" "$out/libexec/lsfg-vk-ui"
makeWrapper "$out/libexec/lsfg-vk-ui" "$out/bin/lsfg-vk-ui" \
  --prefix QT_PLUGIN_PATH : "@QTBASE@/lib/qt-6/plugins" \
  --prefix QML2_IMPORT_PATH : "@QTDECLARATIVE_V2@/lib/qt-6/qml" \
  --prefix QT_QPA_PLATFORM_PLUGIN_PATH : "@QTBASE_V2@/lib/qt-6/plugins/platforms"

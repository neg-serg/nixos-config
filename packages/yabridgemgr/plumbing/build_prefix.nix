{
  runCommand,
  wineWowPackages,
  squashfsTools,
  username ? "wineuser",
  plugins ? [],
}:
runCommand "build_prefix" {
  nativeBuildInputs = [
    wineWowPackages.full # 32/64-bit Wine for plugins
    squashfsTools # mksquashfs to pack the prefix
  ];
} (''
    mkdir $out
    export WINEPREFIX=$(pwd)/prefix
    mkdir home
    export HOME=$(pwd)/home
    export USER=${username}

    echo "--------------------"
    echo "Creating Wine Prefix"
    echo "--------------------"
    wine hostname

    echo "--------------------"
    echo "Installing Plugins"
    echo "--------------------"

  ''
  + (builtins.foldl' (a: b: a + b + "\n") "" plugins)
  + ''

    echo "--------------------"
    echo "Waiting for wine to be done"
    echo "--------------------"
    wineserver --wait

    echo "--------------------"
    echo "Creating squashfs image"
    echo "--------------------"
    mksquashfs prefix $out/wineprefix.squashfs

    # No Xvfb; nothing to clean up here.
  '')

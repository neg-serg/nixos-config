{ pkgs, ... }:
{
  environment.systemPackages = [
    # Note: upstream hardware.keyboard.qmk handles udev rules and might pull in qmk.
    # We rely on upstream for udev, but trying to hide the binary using shell.
    pkgs.qmk-udev-rules # Explicitly keeping this for now if upstream doesn't cover it or relies on it
  ];
}

# GPU undervolt through CoreCtrl

- Optional capability (disabled by default): `hardware.gpu.corectrl.enable = false;`
- When enabled, installs CoreCtrl and a polkit rule allowing members of a chosen group (default
  `wheel`) to use the CoreCtrl helper.
- Optional: set `hardware.gpu.corectrl.ppfeaturemask = "0xffffffff";` to unlock extended OC/UV
  controls on some AMD GPUs.

Example:

```nix
{
  hardware.gpu.corectrl = {
    enable = true;            # off by default
    group = "wheel";          # who can tune
    # ppfeaturemask = "0xffffffff"; # optional, only if needed for your GPU
  };
}
```

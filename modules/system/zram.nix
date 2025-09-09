{ lib, ... }: {
  zramSwap = {
    enable = lib.mkDefault true;
    memoryPercent = 50;
  };
}

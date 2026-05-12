{ pkgs, ... }:
{
  services.pulseaudio = {
    enable = false;
    support32Bit = false;
    configFile = pkgs.runCommand "default.pa" { } ''
      sed 's/avoid-resampling$/avoid-resampling = true/' \
      ${pkgs.pulseaudio}/etc/pulse/default.pa > $out # Sound server for POSIX and Win32 systems
    '';
  };
}

{pkgs, ...}: {
  systemd.services.nixindex = {
    serviceConfig.Type = "oneshot";
    path = [pkgs.nix-index];
    script = ''
      #!/bin/sh
      ${pkgs.nix-index}/bin/nix-index
    '';
  };

  systemd.timers.nixindex = {
    wantedBy = ["timers.target"];
    partOf = ["nixindex.service"];
    timerConfig = {
      OnCalendar = "*-*-* 4:00:00";
      Unit = "nixindex.service";
    };
  };
}

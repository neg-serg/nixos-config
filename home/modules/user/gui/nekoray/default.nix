{pkgs, ...}: {
  home.packages = with pkgs; [
    nekoray
  ];

  systemd.user.services.nekoray = {
    Unit = {
      Description = "Nekoray Proxy Client";
      After = ["graphical-session-pre.target"];
      PartOf = ["graphical-session.target"];
    };

    Service = {
      ExecStart = "${pkgs.nekoray}/bin/nekoray";
      Restart = "on-failure";
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };
}

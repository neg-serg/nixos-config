{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.throne
  ];

  # systemd.user.services.nekoray = {
  # Unit = {
  #   Description = "Nekoray Proxy Client (Throne)";
  #   After = ["graphical-session-pre.target"];
  #   PartOf = ["graphical-session.target"];
  # };

  # Service = {
  #   ExecStart = "${pkgs.throne}/bin/nekoray"; # Binary name might still be nekoray or throne, assumed throne package keeps compat or I should check binary.
  #   Restart = "on-failure";
  # };

  # Install = {
  #   WantedBy = ["graphical-session.target"];
  # };
  # };
}

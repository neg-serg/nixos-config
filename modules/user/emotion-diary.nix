{
  pkgs,
  lib,
  config,
  ...
}:
let
  systemdUser = config.lib.neg.systemdUser;

  # Aura is a single-file offline diary that lives in the user's src tree. It is
  # served over HTTP rather than opened as a file because localStorage is scoped
  # to the page origin: file://, 127.0.0.1 and localhost are three different
  # storages, and a changing address looks like an empty diary.
  diaryDir = "${config.lib.neg.homeDir}/src/emotion-diary";

  serve = pkgs.writeShellScript "aura-diary-serve" ''
    # Bind only to the loopback interface: the diary never leaves this host.
    exec ${lib.getExe pkgs.python3} -m http.server 8080 \
      --bind 127.0.0.1 --directory ${diaryDir}
  '';
in
{
  # The address is part of the data contract, so the port is fixed here.
  systemd.user.services.aura-diary = systemdUser.mkUserService {
    description = "Aura — local emotion/CBT diary (static file server)";
    presets = [ "defaultWanted" ];
    serviceConfig = {
      ExecStart = serve;
      Restart = "on-failure";
    };
  };
}

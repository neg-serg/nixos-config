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
  diaryDir = "${config.lib.neg.homeDir}/src/@main/@projects/emotion-diary";

  serve = pkgs.writeShellScript "aura-diary-serve" ''
    # Bind only to the loopback interface: the diary never leaves this host.
    # miniserve (Rust) serves index.html at / like the Python http.server did.
    exec ${lib.getExe pkgs.miniserve} --port 8080 --interfaces 127.0.0.1 \
      --index index.html ${diaryDir}
  '';
in
{
  # The address is part of the data contract, so the port is fixed here.
  systemd.user.services.aura-diary = systemdUser.mkUserService {
    description = "Aura — local emotion/CBT diary (static file server)";
    presets = [
      "defaultWanted"
      "restartOnFailure"
    ];
    serviceConfig = {
      ExecStart = serve;
    };
  };
}

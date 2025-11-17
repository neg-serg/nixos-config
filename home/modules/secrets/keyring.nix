{
  lib,
  xdg,
  config,
  ...
}:
with lib; let
  disable = name:
    xdg.mkXdgText "autostart/${name}" ''
      [Desktop Entry]
      Type=Application
      Name=${name} (disabled)
      Hidden=true
    '';
in {
  # Disable GNOME Keyring autostart entries to avoid conflicts with
  # gpg-agent and ssh-agent managed by Home Manager.
  # This prevents systemd's XDG autostart generator from creating
  # app-gnome-keyring-*-autostart user services that fail under Hyprland.
  config = mkMerge [
    (disable "gnome-keyring-ssh.desktop")
    (disable "gnome-keyring-secrets.desktop")
    (disable "gnome-keyring-pkcs11.desktop")
    # Some distros ship a legacy daemon entry; disable just in case.
    (disable "gnome-keyring-daemon.desktop")
    # Ensure SSH_AUTH_SOCK points to the Home Manager ssh-agent service.
    # Note: environment.d does not expand systemd specifiers like %t nor
    # shell vars; set an absolute runtime path to avoid shells inheriting
    # a literal "%t/ssh-agent" value.
    # This repo targets user UID 1000; adjust if different.
    (xdg.mkXdgText "environment.d/90-ssh-agent.conf" "SSH_AUTH_SOCK=/run/user/1000/ssh-agent\n")
    {
      # Remove a pre-existing gnome-keyring env drop-in that overrides SSH_AUTH_SOCK.
      # This avoids clients picking up %t/keyring/ssh when ssh-agent.service is active.
      home.activation.rmGnomeKeyringSSHEnv =
        config.lib.neg.mkEnsureAbsent "${config.xdg.configHome}/environment.d/10-gnome-keyring.conf";
    }
  ];
}

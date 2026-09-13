{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  inherit (config.users.users.neg) home;
  cfg = config.features.dev;
  enableIac = cfg.enable && (cfg.pkgs.iac or false);

  # Ansible Config
  ansibleCfg = builtins.readFile (config.lib.neg.path "files/ansible/ansible.cfg");

  ansibleHosts = ''
    # Add your inventory groups/hosts here
  '';
in
{
  config =
    lib.mkIf enableIac {
      environment.systemPackages = [
        pkgs.ansible # Radically simple IT automation
        pkgs.sshpass # Non-interactive ssh password auth
      ];

      environment.variables = {
        ANSIBLE_HOME = "${home}/.local/share/ansible"; # From envs.nix
        ANSIBLE_CONFIG = "${home}/.config/ansible/ansible.cfg";
        ANSIBLE_ROLES_PATH = "${home}/.local/share/ansible/roles";
        ANSIBLE_GALAXY_COLLECTIONS_PATHS = "${home}/.local/share/ansible/collections";
      };

    }
    // (lib.mkIf enableIac (
      neg.mkHomeFiles {
        ".config/ansible/ansible.cfg".text = ansibleCfg;
        ".config/ansible/hosts".text = ansibleHosts;

        # Ensure directories exist via keep files (pseudo-creation)
        ".local/share/ansible/roles/.keep".text = "";
        ".local/share/ansible/collections/.keep".text = "";
        ".cache/ansible/facts/.keep".text = "";
        ".cache/ansible/ssh/.keep".text = "";
      }
    ));
}

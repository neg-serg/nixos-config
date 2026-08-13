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
  ansibleCfg = ''
    [defaults]
    roles_path = ~/.local/share/ansible/roles
    collections_paths = ~/.local/share/ansible/collections
    inventory = ~/.config/ansible/hosts
    retry_files_enabled = False
    stdout_callback = yaml
    bin_ansible_callbacks = True
    interpreter_python = auto_silent
    forks = 20
    strategy = free
    gathering = smart
    fact_caching = jsonfile
    fact_caching_connection = ~/.cache/ansible/facts
    fact_caching_timeout = 86400
    timeout = 30

    [galaxy]
    server_list = galaxy

    [galaxy_server.galaxy]
    url=https://galaxy.ansible.com/

    [ssh_connection]
    pipelining = True
    control_path_dir = ~/.cache/ansible/ssh
    ssh_args = -o ControlMaster=auto -o ControlPersist=60s
  '';

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

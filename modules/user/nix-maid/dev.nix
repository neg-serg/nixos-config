{
  pkgs,
  lib,
  config,
  neg,
  impurity ? null,
  ...
}: let
  n = neg impurity;
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
in {
  config = lib.mkIf (cfg.enable or false) (lib.mkMerge [
    {
      # Packages
      environment.systemPackages = lib.optionals enableIac [
        pkgs.ansible # Radically simple IT automation
        pkgs.sshpass # Non-interactive ssh password auth
      ];

      # Environment Variables
      environment.variables = lib.mkIf enableIac {
        ANSIBLE_CONFIG = "${config.users.users.neg.home}/.config/ansible/ansible.cfg";
        ANSIBLE_ROLES_PATH = "${config.users.users.neg.home}/.local/share/ansible/roles";
        ANSIBLE_GALAXY_COLLECTIONS_PATHS = "${config.users.users.neg.home}/.local/share/ansible/collections";
      };
    }
    (lib.mkIf enableIac (n.mkHomeFiles {
      ".config/ansible/ansible.cfg".text = ansibleCfg;
      ".config/ansible/hosts".text = ansibleHosts;

      # Ensure directories exist via keep files (pseudo-creation)
      ".local/share/ansible/roles/.keep".text = "";
      ".local/share/ansible/collections/.keep".text = "";
      ".cache/ansible/facts/.keep".text = "";
      ".cache/ansible/ssh/.keep".text = "";
    }))
  ]);
}

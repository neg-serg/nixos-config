{ lib, ... }: {
  # nixpkgs-slim removed services/mail/ entirely (postfix, dovecot, etc.),
  # but the zfs module (tasks/filesystems/zfs.nix) references
  # config.services.mail.sendmailSetuidWrapper in the default for
  # services.zfs.zed.enableMail.  Provide a stub option so eval does not fail.
  options.services.mail.sendmailSetuidWrapper = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "sendmail setuid wrapper";
          program = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Path to the sendmail program";
          };
        };
      }
    );
    default = null;
    description = "Stub from nixpkgs-slim compat — replaced removed postfix module";
  };
}

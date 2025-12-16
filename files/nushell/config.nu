const config_dir = $nu.default-config-dir

source ($config_dir | path join "aliases.nu")
source ($config_dir | path join "git.nu")
source ($config_dir | path join "broot.nu")
use ($config_dir | path join "git-completion.nu") *

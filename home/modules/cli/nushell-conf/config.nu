# Nushell requires compile-time constant paths for source
const config_dir = $nu.default-config-dir

source ($config_dir | path join "aliases.nu")
source ($config_dir | path join "git.nu")
source ($config_dir | path join "broot.nu")
use ($config_dir | path join "git-completion.nu") *

# oh-my-posh prompt is set via PROMPT_COMMAND in extraEnv
# aliae aliases are set via shellAliases in nushell.nix

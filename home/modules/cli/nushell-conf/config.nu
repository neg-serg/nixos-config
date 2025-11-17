source $"($env.XDG_CONFIG_HOME)/nushell/aliases.nu"
source $"($env.XDG_CONFIG_HOME)/nushell/git.nu"
source $"($env.XDG_CONFIG_HOME)/nushell/broot.nu"
use $"($env.XDG_CONFIG_HOME)/nushell/git-completion.nu" *
source $"($env.XDG_CONFIG_HOME)/nushell/aliae.nu"

# Add bebexpand plugin only if installed locally
let _bexpand_path = ("~/.local/share/cargo/bin/nu_plugin_bexpand" | path expand)
if ($_bexpand_path | path exists) {
  plugin add $_bexpand_path
}

# Initialize oh-my-posh only if available
if not (which oh-my-posh | is-empty) {
  oh-my-posh init nu
}

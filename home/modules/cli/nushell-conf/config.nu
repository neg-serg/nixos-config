source $"($env.XDG_CONFIG_HOME)/nushell/aliases.nu"
source $"($env.XDG_CONFIG_HOME)/nushell/git.nu"
source $"($env.XDG_CONFIG_HOME)/nushell/broot.nu"
use $"($env.XDG_CONFIG_HOME)/nushell/git-completion.nu" *
source $"($env.XDG_CONFIG_HOME)/nushell/aliae.nu"



# Initialize oh-my-posh only if available
if not (which oh-my-posh | is-empty) {
  oh-my-posh init nu
}

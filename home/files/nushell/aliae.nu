# Aliae integration for Nushell
# Print init for nushell and source it if aliae exists

let xdg_config = ($env.XDG_CONFIG_HOME? | default ($nu.home-path | path join ".config"))
let cfg = ($xdg_config | path join "aliae" "config.yaml")

if (which aliae | is-empty) == false {
  let cache_dir = ($env.XDG_CACHE_HOME? | default ($nu.temp-path) | path join "aliae")
  let init_path = ($cache_dir | path join "init.nu")
  mkdir $cache_dir | ignore
  ^aliae init nu --config $cfg --print | save --force $init_path
  source $init_path
}


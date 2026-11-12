
_exists rg && {
    local rg_options=(
        --max-columns=0
        --max-columns-preview
        --glob="'!*.git*'"
        --glob="'!*.obsidian'"
        --colors=match:fg:25
        --colors=match:style:underline
        --colors=line:fg:cyan
        --colors=line:style:bold
        --colors=path:fg:249
        --colors=path:style:bold
        --smart-case
        --hidden
    )
    alias -g RG="rg $rg_options"
    alias -g zrg="rg $rg_options -z"
}

_exists sudo && {
    local sudo_list=(chmod chown modprobe umount)
    local logind_sudo_list=(reboot halt poweroff)
    for c in ${sudo_list[@]}; {_exists "$c" && alias "$c=sudo $c"}
}
_exists journalctl && journalctl() {command journalctl "${@:--b}";}

# Run any command through the local SOCKS5 proxy (nh os switch, nix flake lock,
# git over https, curl/yt-dlp...). Thin wrapper over `proxy run <cmd...>`.
_exists proxy && xp() { proxy run "$@"; }
_exists proxy && nxp() { xp nix "$@"; } # nix through the proxy: nxp flake update / nxp flake lock --update-input <name>
# Completion for the two proxy wrappers. `xp`'s first argument is the command to
# run, which is exactly what the shell's precommand completer does; `nxp` has
# `nix` baked in, so its completer restores the full word list and lets the
# normal dispatch complete nix's own arguments. Without this both only complete
# file names.
if (( $+functions[compdef] )); then
    (( $+functions[xp] )) && compdef _precommand xp
    _nxp_complete() { words=(nix "${words[2,-1]}"); (( CURRENT++ )); _normal }
    (( $+functions[nxp] )) && compdef _nxp_complete nxp
fi
_exists mpc && {
    cdm(){
        dirname="$XDG_MUSIC_DIR/$(dirname "$(mpc -f '%file%'|head -1)")"
        cd "$dirname"
    }
}
_exists curl && {
    geoip(){ curl ipinfo.io/$1; }
    sprunge(){ curl -F "sprunge=<-" http://sprunge.us <"$1" ;}
}
if [[ -e /etc/NIXOS ]]; then
    # nvd/dix: diff closures: https://discourse.nixos.org/t/nvd-simple-nix-nixos-version-diff-tool/12397/3
    hash -d nix-now="/run/current-system"
    hash -d nix-boot="/nix/var/nix/profiles/system"
    _exists nixos-rebuild && {
        unalias nixos-rebuild 2>/dev/null
    }
    foobar(){nix run github:emmanuelrosa/erosanix#foobar2000}
    flake-checker(){nix run github:DeterminateSystems/flake-checker}
    # Root-side /etc/nixos work over the git+ssh flake inputs (aurora-src, wl):
    # sudo scrubs the environment, so nix would clone them with root's own ssh
    # setup and stop at "Permission denied (publickey)". Hand the caller's key
    # over explicitly. Extra arguments are appended, so an override such as
    # `nfu --option substitute false` beats the defaults baked in below.
    _nix_root_ssh="ssh -F $HOME/.ssh/config -i $HOME/.ssh/id_ed25519 -o IdentitiesOnly=yes"
    nfu(){ sudo env GIT_SSH_COMMAND="$_nix_root_ssh" nix flake update --flake /etc/nixos "$@" || return; [[ -w /etc/nixos/flake.lock ]] || sudo chown --reference=/etc/nixos/flake.nix /etc/nixos/flake.lock } # root rewrote flake.lock: give it back to the caller, or the next user-side `just update` hits EACCES
    nsw(){ sudo env GIT_SSH_COMMAND="$_nix_root_ssh" nixos-rebuild switch --flake /etc/nixos --option substituters https://cache.nixos.org "$@" } # same, for the switch
    # Completion for those two: the command they run is baked into the function,
    # so the completer restores the full word list (including the flags the
    # function adds) and lets the normal dispatch complete the tool's own
    # options. Without it both complete file names.
    if (( $+functions[compdef] )); then
        _nfu_complete() { words=(nix flake update --flake /etc/nixos "${words[2,-1]}"); (( CURRENT += 5 )); _normal }
        _nsw_complete() { words=(nixos-rebuild switch --flake /etc/nixos --option substituters https://cache.nixos.org "${words[2,-1]}"); (( CURRENT += 7 )); _normal }
        compdef _nfu_complete nfu
        compdef _nsw_complete nsw
    fi

    qi(){ NIXPKGS_ALLOW_UNFREE=1 nix shell --impure 'nixpkgs#'$1 }
    q(){ nix shell 'nixpkgs#'$1 }
    flakify() {
        # thx to Mic92:
        if [ ! -e flake.nix ]; then
            nix flake new -t github:Mic92/flake-templates#nix-develop .
        elif [ ! -e .envrc ]; then
            echo "use flake" > .envrc
        fi
        direnv allow
        ${EDITOR:-vim} flake.nix
    }
fi

_exists docker && {
    carbonyl(){docker run --rm -ti fathyb/carbonyl https://youtube.com}
    ipmi_one(){ docker run -p 127.0.0.1:5900:5900 -p 127.0.0.1:8080:8080 gari123/ipmi-kvm-docker; echo xdg-open http://127.0.0.1:8080|wl-copy }
    ipmi_two(){ docker run -p 8080:8080 solarkennedy/ipmi-kvm-docker; echo xdg-open localhost:8080|wl-copy }
}

_exists broot && autoload -Uz br

_exists lazytail && {
    alias lt=lazytail # TUI log viewer (sources from ~/.config/lazytail/config.yaml)
    ltc(){ lazytail -n "$@" } # cmd | ltc NAME  ->  ~/.config/lazytail/data/NAME.log (tee-like)
}
# Colour wrappers for the tools that print plain text and never need a terminal
# (df, du, free, lsblk, ip, ss, ping, traceroute, dig, mount, dmesg, ps, lsof,
# sensors, lspci, smartctl, uptime, env, find, tar, diff, nmap, iptables,
# systemd-analyze). The command list lives in the tint package (builtin table)
# plus ~/.config/tint/config.toml, so the wrappers are generated here instead of
# being a second copy in this file. Pager/progress/tty tools (nix, cargo,
# python, docker, kubectl, journalctl, ...) are deliberately not wrapped; use
# `cmd | tint -r NAME`. tint execs the
# command when stdout is not a tty, so a pipe pays one exec and keeps its exit
# code; lines that a tool already coloured are passed through untouched.
_exists tint && eval "$(tint --shell zsh)"

# `git` under tint: its transport and pack commands are the ones that print a
# plain progress ladder, and git draws that ladder only on a terminal (`git push
# | cat` loses it entirely). Under `tint --pty` git really sees a terminal, tint
# relays the ladder and colours it, and the exit code stays git's.
#
# Everything else stays on git: status, diff and log already colour themselves,
# and they own a pager or an editor that a relay would only get in the way of.
# Pipes and redirects go straight to git as well, or `git log | grep` would
# suddenly receive pager output.
#
# A function, not an alias: the command word stays `git`, so zsh and carapace
# keep completing subcommands, refs and paths. Aliases that expand to git
# (`gp = git push`) keep their completion for the same reason.
if _exists tint; then
  git() {
    emulate -L zsh
    local sub=
    local -i i=1
    # Skip the global options that take a value, so `git -C repo push` and
    # `git -c k=v fetch` are recognised as the commands they are.
    while (( i <= $# )); do
      case $argv[i] in
        -c|-C|--git-dir|--work-tree|--namespace|--config-env|--super-prefix) (( i += 2 )) ;;
        --*) (( i += 1 )) ;;
        *) sub=$argv[i]; break ;;
      esac
    done
    case $sub in
      (push|fetch|pull|clone|ls-remote|remote|submodule|gc|repack|fsck|prune|checkout|switch|restore|reset)
        if [[ -t 1 && -t 2 ]]; then
          command tint --pty -r generic -- git "$@"
          return
        fi
        ;;
    esac
    command git "$@"
  }
fi

autoload zc

# vim: ft=zsh:nowrap

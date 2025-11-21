_exists() { (( $+commands[$1] )) }
alias qe='cd ^.git*(/om[1]D)'
alias ls="${aliases[ls]:-ls} --time-style=+\"%d.%m.%Y %H:%M\" --color=auto --hyperlink=auto"
_exists eza && {
    alias eza="eza --icons=auto --hyperlink"
    alias ls="${aliases[eza]:-eza}"
    lcr(){eval "${aliases[eza]:-eza} -al --sort=created --color=always" "$@" | tail -14 }
    lsd(){eval "${aliases[eza]:-eza} -alD --sort=created --color=always" "$@" | tail -14 }
}
alias fc="fc -liE 100"

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

alias emptydir='ls -ld **/*(/^F)'
_exists sudo && {
    alias sudo='sudo '
    local sudo_list=(chmod chown modprobe umount)
    local logind_sudo_list=(reboot halt poweroff)
    for c in ${sudo_list[@]}; {_exists "$c" && alias "$c=sudo $c"}
}
_exists dosbox && alias dosbox=dosbox -conf "$XDG_CONFIG_HOME"/dosbox/dosbox.conf
_exists gdb && alias gdb="gdb -nh -x ${XDG_CONFIG_HOME}/gdb/gdbinit"
_exists iostat && alias iostat='iostat --compact -p -h -s'
_exists journalctl && journalctl() {command journalctl "${@:--b}";}
_exists mtr && alias mtrr='mtr -wzbe'
_exists nvidia-settings && alias nvidia-settings="nvidia-settings --config=$XDG_CONFIG_HOME/nvidia/settings"
_exists ssh && alias ssh="TERM=xterm-256color ${aliases[ssh]:-ssh}"
_exists umimatrix && alias matrix='unimatrix -l Aang -s 95'
_exists mpv && {
    alias mpv="mpv"
    alias mpa="${aliases[mpv]:-mpv} -mute "$@" > ${HOME}/tmp/mpv.log"
    alias mpi="${aliases[mpv]:-mpv} --interpolation=yes --tscale='oversample' \
        --video-sync='display-resample' "$@" > ${HOME}/tmp/mpv.log"
}
_exists mpc && {
    cdm(){
        dirname="$XDG_MUSIC_DIR/$(dirname "$(mpc -f '%file%'|head -1)")"
        cd "$dirname"
    }
}
local rlwrap_list=(bb fennel guile irb)
local noglob_list=(fc find ftp history lftp links2 locate lynx nix nixos-remote nixos-rebuild rake rsync sftp you-get yt wget wget2)
_exists scp && alias scp="noglob scp -r"
for c in ${noglob_list[@]}; {_exists "$c" && alias "$c=noglob $c"}
for c in ${rlwrap_list[@]}; {_exists "$c" && alias "$c=rlwrap $c"}
for c in ${nocorrect_list[@]}; {_exists "$c" && alias "$c=nocorrect $c"}
for c in ${dev_null_list[@]}; {_exists "$c" && alias "$c=$c 2>/dev/null"}
_exists svn && alias svn="svn --config-dir $XDG_CONFIG_HOME/subversion"
_exists curl && {
    alias cht='f(){ curl -s "cheat.sh/$(echo -n "$*"|jq -sRr @uri)";};f'
    geoip(){ curl ipinfo.io/$1; }
    sprunge(){ curl -F "sprunge=<-" http://sprunge.us <"$1" ;}
}
_exists fzf && {
    logs() {
        local cmd log_file
        cmd="command find /var/log/ -type f -name '*log' 2>/dev/null"
        log_file=$(eval "$cmd" | fzf --height 40% --min-height 25 --tac --tiebreak=length,begin,index --reverse --inline-info) && $PAGER "$log_file"
    }
}

if [[ -e /etc/NIXOS ]]; then
    # thx to @oni: https://discourse.nixos.org/t/nvd-simple-nix-nixos-version-diff-tool/12397/3
    hash -d nix-now="/run/current-system"
    hash -d nix-boot="/nix/var/nix/profiles/system"
    _exists nixos-rebuild && {
        
    }
    foobar(){nix run github:emmanuelrosa/erosanix#foobar2000}
    flake-checker(){nix run github:DeterminateSystems/flake-checker}
    linux-kernel(){
        nix-shell -E 'with import <nixpkgs> {};
            (builtins.getFlake "github:chaotic-cx/nyx/nyxpkgs-unstable").packages.x86_64-linux.linuxPackages_cachyos.kernel.overrideAttrs
            (o: {nativeBuildInputs=o.nativeBuildInputs ++ [ pkg-config ncurses ];})'
        # unpackPhase && cd linux-*; patchPhase; make nconfig
    }
    _exists nh && {
        
        
    }
    nbuild(){ nix-build -E 'with import <nixpkgs> {}; callPackage ./default.nix {}'}
    nlocate(){ nix run github:nix-community/nix-index-database "$@" }
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

autoload zc
unfunction _exists
# vim: ft=zsh:nowrap

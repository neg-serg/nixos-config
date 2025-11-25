# Temporary fallback for Aliae aliases in Zsh.
# TODO: remove this file and its .zshrc wiring once Aliae is reliable again.
#
# This mirrors the alias set from modules/cli/aliae.nix so that Zsh has
# working aliases even when the aliae binary or config is unavailable.

# Core eza / ls wrappers
alias l='eza --icons=auto --hyperlink'
alias ll='eza --icons=auto --hyperlink -l'
alias lsd='eza --icons=auto --hyperlink -alD --sort=created --color=always'
alias ls='eza --icons=auto --hyperlink'
alias eza='eza --icons=auto --hyperlink'

# Core tools
alias cat='bat -pp'
alias g='git'
alias gs='git status -sb'
alias qe='qe'
alias acp='cp'
alias als='ls'
alias lcr='eza --icons=auto --hyperlink -al --sort=created --color=always'

# Git shortcuts
alias add='git add'
alias checkout='git checkout'
alias commit='git commit'
alias fc='fc -liE 100'
alias ga='git add'
alias gaa='git add --all'
alias gam='git am'
alias gama='git am --abort'
alias gamc='git am --continue'
alias gams='git am --skip'
alias gamscp='git am --show-current-patch'
alias gap='git apply'
alias gapa='git add --patch'
alias gapt='git apply --3way'
alias gau='git add --update'
alias gav='git add --verbose'
alias gb='git branch'
alias gbD='git branch -D'
alias gba='git branch -a'
alias gbd='git branch -d'
alias gbl='git blame -b -w'
alias gbnm='git branch --no-merged'
alias gbr='git branch --remote'
alias gbs='git bisect'
alias gbsb='git bisect bad'
alias gbsg='git bisect good'
alias gbsr='git bisect reset'
alias gbss='git bisect start'
alias gc='git commit -v'
alias gc!='git commit -v --amend'
alias gca='git commit -v -a'
alias gca!='git commit -v -a --amend'
alias gcam='git commit -a -m'
alias gcan!='git commit -v -a --no-edit --amend'
alias gcans!='git commit -v -a -s --no-edit --amend'
alias gcas='git commit -a -s'
alias gcasm='git commit -a -s -m'
alias gcb='git checkout -b'
alias gcl='git clone --recurse-submodules'
alias gclean='git clean -id'
alias gcmsg='git commit -m'
alias gcn!='git commit -v --no-edit --amend'
alias gco='git checkout'
alias gcor='git checkout --recurse-submodules'
alias gcount='git shortlog -sn'
alias gcp='git cherry-pick'
alias gcpa='git cherry-pick --abort'
alias gcpc='git cherry-pick --continue'
alias gcs='git commit -S'
alias gcsm='git commit -s -m'
alias gd='git diff -w -U0 --word-diff-regex=[^[:space:]]'
alias gdca='git diff --cached'
alias gdcw='git diff --cached --word-diff'
alias gds='git diff --staged'
alias gdup='git diff @{upstream}'
alias gdw='git diff --word-diff'
alias gf='git fetch'
alias gfa='git fetch --all --prune'
alias gfg='git ls-files | grep'
alias gfo='git fetch origin'
alias gignore='git update-index --assume-unchanged'
alias gignored="git ls-files -v | grep '^[[:lower:]]'"
alias gl='git pull'
alias gm='git merge'
alias gma='git merge --abort'
alias gmtl='git mergetool --no-prompt'
alias gp='git push'
alias gpd='git push --dry-run'
alias gpf='git push --force-with-lease'
alias gpf!='git push --force'
alias gpr='git pull --rebase'
alias gpristine='git reset --hard && git clean -dffx'
alias gpv='git push -v'
alias gr='git remote'
alias gra='git remote --add'
alias grb='git rebase'
alias grba='git rebase --abort'
alias grbc='git rebase --continue'
alias grbi='git rebase -i'
alias grbo='git rebase --onto'
alias grbs='git rebase --skip'
alias grev='git revert'
alias grh='git reset'
alias grhh='git reset --hard'
alias grm='git rm'
alias grmc='git rm --cached'
alias grs='git restore'
alias grup='git remote update'
alias gsh='git show'
alias gsi='git submodule init'
alias gsps='git show --pretty=short --show-signature'
alias gsta='git stash save'
alias gstaa='git stash apply'
alias gstall='git stash --all'
alias gstc='git stash clear'
alias gstd='git stash drop'
alias gstl='git stash list'
alias gstp='git stash pop'
alias gsts='git stash show --text'
alias gstu='git stash --include-untracked'
alias gsu='git submodule update'
alias gsw='git switch'
alias gswc='git switch -c'
alias gts='git tag -s'
alias gu="git reset --soft 'HEAD^'"
alias gup='git pull --rebase'
alias gupa='git pull --rebase --autostash'
alias gupav='git pull --rebase --autostash -v'
alias gupv='git pull --rebase -v'
alias gwch='git whatchanged -p --abbrev-commit --pretty=medium'
alias pull='git pull'
alias push='git push'
alias resolve='git mergetool --tool=nwim'
alias stash='git stash'
alias status='git status'

# Misc core aliases
alias sudo='sudo '
alias cp='cp --reflink=auto'
alias mv='mv -i'
alias mk='mkdir -p'
alias rd='rmdir'
alias x='xargs'
alias sort='sort --parallel 8 -S 16M'
alias :q='exit'
alias s='sudo '
alias dig='dig +noall +answer'
alias rsync='rsync -az --compress-choice=zstd --info=FLIST,COPY,DEL,REMOVE,SKIP,SYMSAFE,MISC,NAME,PROGRESS,STATS'
alias nrb='sudo nixos-rebuild'
alias j='journalctl'
alias emptydir='emptydir'
alias dosbox='dosbox -conf $XDG_CONFIG_HOME/dosbox/dosbox.conf'
alias gdb='gdb -nh -x $XDG_CONFIG_HOME/gdb/gdbinit'
alias iostat='iostat --compact -p -h -s'
alias mtrr='mtr -wzbe'
alias "nvidia-settings"='nvidia-settings --config=$XDG_CONFIG_HOME/nvidia/settings'
alias ssh='TERM=xterm-256color ssh'
alias matrix='unimatrix -l Aang -s 95'
alias svn='svn --config-dir $XDG_CONFIG_HOME/subversion'
alias scp='scp -r'

# Optional aliases, enabled only when tools are present

if command -v mpv >/dev/null 2>&1; then
  alias mpv='mpv'
  alias mp='mpv'
  alias mpa='mpa'
  alias mpi='mpi'
fi

if command -v rg >/dev/null 2>&1; then
  alias rg="rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden"
fi

if command -v nmap >/dev/null 2>&1; then
  alias nmap-vulners='nmap -sV --script=vulners/vulners.nse'
  alias nmap-vulscan='nmap -sV --script=vulscan/vulscan.nse'
fi

if command -v prettyping >/dev/null 2>&1; then
  alias ping='prettyping'
fi

if command -v duf >/dev/null 2>&1; then
alias df='duf -theme ansi -hide special -hide-mp $HOME/* /nix/store'
fi

if command -v dust >/dev/null 2>&1; then
  alias sp='dust -r'
fi

if command -v khal >/dev/null 2>&1; then
  alias cal='khal calendar'
fi

if command -v hexyl >/dev/null 2>&1 || command -v hxd >/dev/null 2>&1; then
  alias hexdump='hxd'
fi

if command -v ouch >/dev/null 2>&1; then
  alias se='ouch decompress'
  alias pk='ouch compress'
fi

if command -v pigz >/dev/null 2>&1; then
  alias gzip='pigz'
fi

if command -v pbzip2 >/dev/null 2>&1; then
  alias bzip2='pbzip2'
fi

if command -v plocate >/dev/null 2>&1; then
  alias locate='plocate'
fi

alias xz='xz --threads=0'
alias zstd='zstd --threads=0'

if command -v mpvc >/dev/null 2>&1; then
  alias mpvc='mpvc -S $XDG_CONFIG_HOME/mpv/socket'
fi

if command -v wget2 >/dev/null 2>&1; then
  alias wget='wget2 --hsts-file $XDG_DATA_HOME/wget-hsts'
fi

if command -v yt-dlp >/dev/null 2>&1; then
  alias yt='yt-dlp --downloader aria2c --embed-metadata --embed-thumbnail --embed-subs --sub-langs=all'
  alias yta='yt-dlp --downloader aria2c --embed-metadata --embed-thumbnail --embed-subs --sub-langs=all --write-info-json'
fi

if command -v curl >/dev/null 2>&1; then
  alias moon='curl wttr.in/Moon'
  alias we="curl 'wttr.in/?T'"
  alias wem='curl wttr.in/Moscow?lang=ru'
fi

if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  alias cht='cht'
fi

if command -v rlwrap >/dev/null 2>&1; then
  alias bb='rlwrap bb'
  alias fennel='rlwrap fennel'
  alias guile='rlwrap guile'
  alias irb='rlwrap irb'
fi

if command -v btm >/dev/null 2>&1; then
  alias htop='btm -b -T --mem_as_value'
fi

if command -v iotop >/dev/null 2>&1; then
  alias iotop='sudo iotop -oPa'
fi

if command -v lsof >/dev/null 2>&1; then
  alias ports='sudo lsof -Pni'
fi

if command -v kmon >/dev/null 2>&1; then
  alias kmon='sudo kmon -u --color 19683a'
fi

if command -v fd >/dev/null 2>&1; then
  alias fd='fd -H --ignore-vcs'
  alias fda='fd -Hu'
fi

if command -v mpc >/dev/null 2>&1; then
  alias love='mpc sendmessage mpdas love'
  alias unlove='mpc sendmessage mpdas unlove'
fi

if command -v handlr >/dev/null 2>&1; then
  alias e='handlr open'
fi

if command -v erd >/dev/null 2>&1; then
  alias tree='erd'
fi

if command -v nixify >/dev/null 2>&1; then
  alias nixify='nix-shell -p nur.repos.kampka.nixify'
fi

if command -v nix-index >/dev/null 2>&1; then
  alias nlocate='nix run github:nix-community/nix-index-database'
fi

if command -v flatpak >/dev/null 2>&1; then
  alias bottles='flatpak run com.usebottles.bottles'
  alias obs='flatpak run com.obsproject.Studio'
  alias onlyoffice='QT_QPA_PLATFORM=xcb flatpak run org.onlyoffice.desktopeditors'
  alias zoom='flatpak run us.zoom.Zoom'
fi

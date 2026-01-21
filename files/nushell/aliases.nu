def _exists [name: string] {
  not (which $name | is-empty)
}

# def cp [] { ^cp --reflink=auto }
# alias ls = eza --icons=auto --hyperlink
def qe [] { cd (als -a | where name =~ '^.git.*' | where type == dir | sort-by modified | last | get name) }
def fc [] {
  let path = $env.HISTORY_PATH
  ^$env.EDITOR $path
}
def rg [...args] {
  let base_opts = [
    --max-columns=0
    --max-columns-preview
    --glob '!*.git*'
    --glob '!*.obsidian'
    --colors match:fg:25
    --colors match:style:underline
    --colors line:fg:cyan
    --colors line:style:bold
    --colors path:fg:249
    --colors path:style:bold
    --smart-case
    --hidden
  ]
  ^rg ...$base_opts ...$args
}

def zrg [...args] {
  ^rg -z ...$args
}

def iotop [] { sudo iotop -oPa }
def ports [] { sudo lsof -Pni }
def kmon [] { sudo kmon -u --color 19683a }
def htop [] { btm -b -T --mem_as_value }
def dd [] { ^dd status=progress }
def dig [] { ^dig +noall +answer }
# def dosbox [] { dosbox -conf $"($env.XDG_CONFIG_HOME)/dosbox/dosbox.conf" }
def fd [] { ^fd -H --ignore-vcs }
def fda [] { ^fd -Hu }
def gdb [] { ^gdb -nh -x $"($env.XDG_CONFIG_HOME)/gdb/gdbinit" }
def iostat [] { ^iostat --compact -p -h -s }
def mtrr [] { mtr -wzbe }
def rsync [] { ^rsync -az --compress-choice=zstd --info=FLIST,COPY,DEL,REMOVE,SKIP,SYMSAFE,MISC,NAME,PROGRESS,STATS }
def ssh [] { TERM=xterm-256color ssh }
def matrix [] { unimatrix -l Aang -s 95 }
def mpa [...args: string] {
  ^mpv -mute ...$args | save -f $"($env.HOME)/tmp/mpv.log"
}
def mpi [...args: string] {
  ^mpv --interpolation=yes --tscale=oversample --video-sync=display-resample ...$args | save -f $"($env.HOME)/tmp/mpv.log"
}
def love [] { mpc sendmessage mpdas love }
def unlove [] { mpc sendmessage mpdas unlove }
def cdm [] {
  let rel_path = (mpc -f '%file%' | lines | first | path dirname)
  let full_path = $"($env.XDG_MUSIC_DIR)/($rel_path)"
  cd $full_path
}

# NixOS-related

def nrb [] { sudo nixos-rebuild }
def foobar [] { nix run github:emmanuelrosa/erosanix#foobar2000 }
def flake-checker [] { nix run github:DeterminateSystems/flake-checker }

def S [...args: string] { nix shell ...$args }
def nbuild [] { nix-build -E 'with import <nixpkgs> {}; callPackage ./default.nix {}' }
def nlocate [...args: string] { nix run github:nix-community/nix-index-database ...$args }
def qi [pkg: string] {
  let name = $"nixpkgs#($pkg)"
  NIXPKGS_ALLOW_UNFREE=1 nix shell --impure $name
}
def q [pkg: string] { nix shell $"nixpkgs#($pkg)" }
def flakify [] {
  if not ("./flake.nix" | path exists) {
    nix flake new -t github:Mic92/flake-templates#nix-develop .
  }
  if not ("./.envrc" | path exists) {
    echo "use flake" | save -f .envrc
  }
  direnv allow
  ^($env.EDITOR | default "vim") flake.nix
}

# Docker-based
def carbonyl [] { docker run --rm -ti fathyb/carbonyl https://youtube.com }
def ipmi_one [] {
  docker run -p 127.0.0.1:5900:5900 -p 127.0.0.1:8080:8080 gari123/ipmi-kvm-docker
  echo "xdg-open http://127.0.0.1:8080" | wl-copy
}
def ipmi_two [] {
  docker run -p 8080:8080 solarkennedy/ipmi-kvm-docker
  echo "xdg-open localhost:8080" | wl-copy
}

# Flatpak-based
def bottles [] { flatpak run com.usebottles.bottles }
def obs [] { flatpak run com.obsproject.Studio }
def onlyoffice [] { QT_QPA_PLATFORM=xcb flatpak run org.onlyoffice.desktopeditors }
def zoom [] { flatpak run us.zoom.Zoom }

# Curl-based
def moon [] { curl wttr.in/Moon }
def we [] { curl 'wttr.in/?T' }
def wem [] { curl 'wttr.in/Moscow?lang=ru' }
def sprunge [file: path] {
  open $file | ^curl -F 'sprunge=<-' http://sprunge.us
}
def cht [...args: string] {
  let query = ($args | str join " " | ^jq -sRr @uri | str trim)
  curl -s $"cheat.sh/($query)"
}

def j [...args: string] {
  if ($args | is-empty) {
    ^journalctl -b
  } else {
    ^journalctl ...$args
  }
}

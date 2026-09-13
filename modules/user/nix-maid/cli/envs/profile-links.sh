echo "Ensuring legacy profile links for user neg..."
@runuserExe@ -u neg -- @bashExe@ -c ' # Set of system utilities for Linux
  set -eu
  mkdir -p "$HOME/.local/state/nix/profiles"
  PROFILE_TARGET="/etc/profiles/per-user/neg"

  ln -sfn "$PROFILE_TARGET" "$HOME/.local/state/nix/profiles/profile"
  ln -sfn "$HOME/.local/state/nix/profiles/profile" "$HOME/.local/state/nix/profile"
  ln -sfn "$HOME/.local/state/nix/profiles/profile" "$HOME/.nix-profile"

  # Legacy zshenv-extra logic: ensure ~/tmp is a symlink to a temp dir if invalid
  # (Though usually ~/tmp should be ephemeral or just a dir)
  # We replicate the logic from home/modules/user/envs/zshenv-extra.sh
  if [ ! -e "$HOME/tmp" ] || [ ! -L "$HOME/tmp" ]; then
     rm -rf "$HOME/tmp"
     # Create a secure temp dir and link it?
     # The original script does `tmp_loc=$(mktemp -d); ln -fs ...`
     # But mktemp -d creates it in /tmp usually.
     # Ideally we just want ~/tmp to exist.
     mkdir -p "$HOME/tmp"
  fi

'

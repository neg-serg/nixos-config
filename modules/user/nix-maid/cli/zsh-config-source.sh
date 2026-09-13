mkdir -p "$out"
cp -R @SHELLFILES@/zsh/. "$out"/
chmod -R u+w "$out"
sed -i "s|@zinit@|@ZINIT@|g" "$out/.zshrc"
sed -i "s|@native-syntax@|@SYNTAX@|g" "$out/.zshrc"
cat > "$out/.zshenv" << 'EOF'
# shellcheck disable=SC1090
skip_global_compinit=1
# Hardcoded path for profile session vars (standard location)
session_vars="$HOME/.nix-profile/etc/profile.d/session-vars.sh"
if [ -r "$session_vars" ]; then
  . "$session_vars"
elif [ -r "/etc/profiles/per-user/$USER/etc/profile.d/session-vars.sh" ]; then
  . "/etc/profiles/per-user/$USER/etc/profile.d/session-vars.sh"
fi
# DEEPSEEK API key for dsh (from SOPS secret; keep any existing override)
export DEEPSEEK_API_KEY="${DEEPSEEK_API_KEY:-$(cat /run/secrets/deepseek-api 2>/dev/null)}"
export WORDCHARS='*/?_-.[]~&;!#$%^(){}<>~` '
export KEYTIMEOUT=10
export REPORTTIME=60
export ESCDELAY=1
@ZSHENVEXTRAS@
EOF

# Pure assertions over lib/neg-helpers.nix hasFzfHashComment — eval-only.
# Wired into flake/checks.nix as the "fzf-opts-guard" check.
# Ground truth (empirically verified against fzf 0.72.0): a '#' at the start
# of a token (after whitespace, outside quotes) is a comment that silently
# drops the rest of FZF_*_OPTS; '#' inside a token or inside quotes is literal.
let
  h = import ./neg-helpers.nix;
  check = cond: msg: {
    inherit msg;
    ok = cond;
  };
  checks = [
    (check (h.hasFzfHashComment "--bind=x # comment") "flags inline comment after a bind")
    (check (h.hasFzfHashComment "# comment") "flags comment at the start")
    (check (h.hasFzfHashComment "--bind='ctrl-n:down' # emacs-style list navigation") "flags the exact 5cd4942a regression pattern")
    (check (h.hasFzfHashComment "--bind=x #comment") "flags '#' token without trailing space")
    (check (h.hasFzfHashComment "--prompt='a #b' # real comment") "flags comment even after a quoted hash")
    (check (!(h.hasFzfHashComment "--color=gutter:#000000")) "allows '#' inside a token (colors)")
    (check (!(h.hasFzfHashComment "--prompt='a #b'")) "allows '#' inside quotes")
    (check (!(h.hasFzfHashComment "--bind=x:y#z")) "does not treat mid-token '#' as a comment")
    (check (
      !(h.hasFzfHashComment "--footer='[Enter] Paste  [Ctrl-y] Yank  [?] Preview'")
    ) "allows brackets/quotes without hash")
  ];
in
{
  inherit checks;
  failures = builtins.filter (c: !c.ok) checks;
  report = builtins.concatStringsSep "; " (map (f: f.msg) (builtins.filter (c: !c.ok) checks));
}

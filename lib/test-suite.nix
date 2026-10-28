# Eval-only assertion harness shared by the lib/*-tests.nix suites.
#
# A suite is a list of assertions built with `check`. flake/checks.nix
# (`mkOkCheck`) consumes exactly three fields: `checks` (for the "N assertions"
# line of a passing check), `failures` (what it tests) and `report` (the message
# it throws). Every suite used to spell that trio plus its own `check`
# constructor out by hand — both live here now, so a new suite is a file with
# imports and assertions and nothing else:
#
#   let
#     t = import ./test-suite.nix;
#     inherit (t) check;
#   in
#   t.suite [
#     (check (hasFzfHashComment "--bind=x # c") "flags an inline comment")
#   ]
#
# Keep this file dependency-free (builtins only): it is imported by checks that
# deliberately carry no config/flake dependencies.
rec {
  # cond → bool, msg → the sentence printed when the assertion fails.
  check = cond: msg: {
    inherit msg;
    ok = cond;
  };

  suite =
    checks:
    let
      failures = builtins.filter (c: !c.ok) checks;
    in
    {
      inherit checks failures;
      report = builtins.concatStringsSep "; " (map (f: f.msg) failures);
    };
}

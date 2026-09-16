##
# Package: hilbert
# Purpose: Hilbert transform and Hartley phasing utilities — SC quark (ambisonictoolkit). Pure sclang classes.
#   Dependency of ATK.
# Source: https://github.com/ambisonictoolkit/Hilbert
{
  lib,
  mkScQuark,
}:
mkScQuark {
  pname = "hilbert";
  version = "unstable-2019-05-08";

  owner = "ambisonictoolkit";
  repo = "Hilbert";
  rev = "264e8cd6db8593feefe6eceb338770df9fae65e0";
  hash = "sha256-k0EwWQHv1TTMUb132L/X1ZDsqcqFAPHrF1/scKLdteM=";

  installDir = "Hilbert";
  install = ''
    cp -r Classes "$extdir/"
    cp -r HelpSource "$extdir/" 2>/dev/null || true
    cp Hilbert.quark LICENSE "$extdir/" 2>/dev/null || true
  '';

  meta = {
    description = "SuperCollider quark: Hilbert transform and Hartley phasing utilities";
    homepage = "https://github.com/ambisonictoolkit/Hilbert";
    license = lib.licenses.gpl2Plus;
  };
}

# Shared builder for the local Vicinae extensions: a directory under
# files/gui/vicinae-extensions installed as-is (node bundle + manifest).
#
# The extension supplies its package name, the source directory and the
# description; `platforms`/`maintainers` get the usual local defaults.
{
  lib,
  stdenv,
  paths,
}:
{
  pname,
  description,
  # Directory name under files/gui/vicinae-extensions.
  srcDir,
  version ? "0.1.0",
}:
stdenv.mkDerivation {
  inherit pname version;

  src = paths.path "files/gui/vicinae-extensions/${srcDir}";

  installPhase = ''
    mkdir -p $out
    cp -r . $out/
  '';

  meta = lib.mkMeta {
    inherit description;
    license = lib.licenses.mit;
  };
}

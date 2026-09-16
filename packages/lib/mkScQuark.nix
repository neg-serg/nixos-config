# Shared builder for pure-sclang SuperCollider "quark" packages: fetch an
# upstream source tree and copy its classes/help into
# $out/share/SuperCollider/extensions/<installDir>.
#
# Only for packages with no build step whose installPhase is a plain sequence
# of `cp` commands. The package supplies the fetch spec, the install body and
# its meta; `platforms`/`maintainers` get the usual local defaults.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchgit,
}:
{
  pname,
  version,
  # Source: fetchFromGitHub (owner/repo) or fetchgit (url).
  owner ? null,
  repo ? null,
  url ? null,
  rev,
  hash,
  # Directory name under share/SuperCollider/extensions.
  installDir,
  # Shell lines run inside installPhase; $extdir is in scope.
  install,
  meta,
}:
stdenvNoCC.mkDerivation {
  inherit pname version;

  src =
    if url != null then
      fetchgit { inherit url rev hash; }
    else
      fetchFromGitHub {
        inherit
          owner
          repo
          rev
          hash
          ;
      };

  installPhase = ''
    runHook preInstall
    extdir="$out/share/SuperCollider/extensions/${installDir}"
    mkdir -p "$extdir"
    ${install}
    runHook postInstall
  '';

  meta = {
    platforms = lib.platforms.all;
    maintainers = [ ];
  }
  // meta;
}

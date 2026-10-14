# Source URLs that went dead upstream, repointed at a mirror serving the same
# tarball. The fixed-output hash pins the content, so a mirror swap cannot
# change what gets built — the URL is only a transport detail.
_inputs: _final: prev: {

  # newt: releases.pagure.org stopped serving the release artifacts (404 for
  # newt-0.52.24.tar.gz, confirmed 2026-10-14; nixpkgs master still carries the
  # dead URL). NetworkManager's nmtui depends on newt, so a from-source rebuild
  # of this host fails while fetching it. The MacPorts distfiles mirror carries
  # the identical tarball (sha256-Xe1+Ih+F9kJSHEmxgmyN4ZhFqjcrr11jClF3S1RPvbs=).
  newt = prev.newt.overrideAttrs (old: {
    src = prev.fetchurl {
      url = "https://macports-distfiles.mirrorservice.org/libnewt/newt-${old.version}.tar.gz";
      hash = "sha256-Xe1+Ih+F9kJSHEmxgmyN4ZhFqjcrr11jClF3S1RPvbs=";
    };
  });
}

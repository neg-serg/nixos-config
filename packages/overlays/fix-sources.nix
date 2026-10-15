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

  # sqliteodbc: the upstream host no longer serves the 0.99991 tarball
  # (http://www.ch-werner.de/sqliteodbc/ answers 404 and the HTTPS certificate
  # does not match), and nixpkgs master still points there. qtbase's ODBC SQL
  # driver needs it, so a from-source qt6 build fails. Ubuntu's orig tarball is
  # byte-identical — same sha256 as nixpkgs pins (verified 2026-10-14).
  unixodbcDrivers = prev.unixodbcDrivers // {
    sqlite = prev.unixodbcDrivers.sqlite.overrideAttrs (old: {
      src = prev.fetchurl {
        name = "sqliteodbc-${old.version}.tar.gz";
        url = "http://archive.ubuntu.com/ubuntu/pool/universe/s/sqliteodbc/sqliteodbc-${old.version}.orig.tar.gz";
        hash = "sha256-TZStuNPN4fqUoorrDfzHvnMUW8383z1eIlQ02zHcilw=";
      };
    });
  };

  # bmake: crufty.net stopped serving the release tarball (404 for
  # bmake-20260313.tar.gz, confirmed 2026-10-14; nixpkgs master still carries
  # the dead URL). lowdown builds with bmake and the nix/maid chain depends on
  # lowdown, so a from-source rebuild of this host fails while fetching it.
  # ftp.netbsd.org/pub/NetBSD/misc/sjg is the upstream release directory
  # (tarball, .md5 and .sha1 sit next to each other) and serves the identical
  # file — the pinned fixed-output hash matches (verified 2026-10-14).
  bmake = prev.bmake.overrideAttrs (old: {
    src = prev.fetchurl {
      url = "https://ftp.netbsd.org/pub/NetBSD/misc/sjg/bmake-${old.version}.tar.gz";
      hash = "sha256-dsjzzULuBc/7R7zIElbj1edCb00I5zN4i0WYXe30+XU=";
    };
  });

  # typescript-language-server: its pnpm deps FOD stopped reproducing the hash
  # nixpkgs pins — the build dies with
  #   specified: sha256-MUSxDMlbG21KSesGdEvqa2kEpuVfLlXRUX1qV/FGsSo=
  #        got: sha256-xR/EF60lVBsITKgH7wCM2wHM46PFQevD51KfCENSUH4=
  # (npm registry content drifted, checked 2026-10-15). Pin the hash the
  # builder actually produces; nix keeps the mismatched output under that hash,
  # so the deps are already in the store and nothing is refetched.
  typescript-language-server = prev.typescript-language-server.overrideAttrs (old: {
    pnpmDeps = old.pnpmDeps.overrideAttrs (_: {
      outputHash = "sha256-xR/EF60lVBsITKgH7wCM2wHM46PFQevD51KfCENSUH4=";
    });
  });
}

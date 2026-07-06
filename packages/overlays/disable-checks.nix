inputs: final: finalPrev:
{
  # Disable flaky OpenLDAP tests (fails on syncreplication)
  openldap = finalPrev.openldap.overrideAttrs (_old: {
    doCheck = false;
  });

  # Disable libyuv tests (fails with OOM and has many warnings)
  libyuv = finalPrev.libyuv.overrideAttrs (old: {
    doCheck = false;
    cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DUNIT_TEST=OFF" ];
  });

  # Disable rsync tests (fails on hardlinks test)
  rsync = finalPrev.rsync.overrideAttrs (_old: {
    doCheck = false;
  });

  # Disable flaky libuv tests
  libuv = finalPrev.libuv.overrideAttrs (_old: {
    doCheck = false;
  });

  # Disable flaky lua-language-server tests
  lua-language-server = finalPrev.lua-language-server.overrideAttrs (_old: {
    doCheck = false;
  });

  # Skip flaky PSA crypto tests in mbedtls (SEGFAULT on concurrent, failures on persistent/init)
  mbedtls = finalPrev.mbedtls.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DSKIP_TEST_SUITES=psa_crypto" ];
  });

  # XFS breaks nix-util readLinkAt test on kernel 7.0+
  # Build failures on nixpkgs-unstable
  valkey = finalPrev.valkey.overrideAttrs (_old: {
    doCheck = false;
    # Note: if valkey still fails to build, it's a transient nixpkgs issue
  });
  notmuch = finalPrev.notmuch.overrideAttrs (_old: {
    doCheck = false;
  });

  nix = finalPrev.nix.overrideAttrs (_old: {
    doCheck = false;
    doInstallCheck = false;
  });

  nixVersions = finalPrev.nixVersions // {
    stable = finalPrev.nixVersions.stable.overrideAttrs (_old: {
      doCheck = false;
      doInstallCheck = false;
    });
  };

  # Disable flaky cmark-gfm timing test (test 539: takes less than 1000ms to run)
  cmark-gfm = finalPrev.cmark-gfm.overrideAttrs (_old: {
    doCheck = false;
  });

  # Disable flaky pytest-xdist tests
  pythonPackagesExtensions = (finalPrev.pythonPackagesExtensions or [ ]) ++ [
    (_python-final: python-prev: {
      pytest-xdist = python-prev.pytest-xdist.overrideAttrs (_old: {
        doCheck = false;
      });
      uvloop = python-prev.uvloop.overrideAttrs (_old: {
        doCheck = false; # flaky timing test
      });
      pylint = python-prev.pylint.overrideAttrs (_old: {
        doCheck = false; # flaky primer test (network-dependent)
      });
      rich = python-prev.rich.overrideAttrs (_old: {
        doCheck = false; # flaky test_brokenpipeerror
      });
      aiohttp = python-prev.aiohttp.overrideAttrs (_old: {
        doCheck = false; # flaky tests
      });
      django = python-prev.django.overrideAttrs (_old: {
        doCheck = false; # flaky test DB teardown
      });
    })
  ];
}

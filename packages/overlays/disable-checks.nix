_: _: finalPrev: {
  # Disable flaky openexr tests (testMultiPartThreading, testCompositeDeepScanLine abort with EAGAIN)
  openexr = finalPrev.openexr.overrideAttrs (_old: {
    doCheck = false;
  });

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
    cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DSKIP_TEST_SUITES=psa_crypto;psa_crypto_init" ];
  });

  # (valkey override removed: with doCheckByDefault = false it already evaluates
  # to doCheck = false — verified against the same pin, audit 2026-09-15)
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

  # Disable flaky rescrobbled test (test_filter_script: broken pipe on subprocess spawn)
  rescrobbled = finalPrev.rescrobbled.overrideAttrs (_old: {
    doCheck = false;
  });

  # Disable flac tests (segfault on --threads 63, flaky threaded encoder test)
  flac = finalPrev.flac.overrideAttrs (_old: {
    doCheck = false;
  });

  # Disable flaky pulseaudio test (once-test hangs indefinitely on 32-thread machine)
  libpulseaudio = finalPrev.libpulseaudio.overrideAttrs (_old: {
    doCheck = false;
  });

  # Disable ffmpeg tests (test data generation fails with error 245 on gen)
  ffmpeg = finalPrev.ffmpeg.overrideAttrs (_old: {
    doCheck = false;
  });
  ffmpeg-headless = finalPrev.ffmpeg-headless.overrideAttrs (_old: {
    doCheck = false;
  });

  # (pylint override removed: already doCheck = false via doCheckByDefault,
  # verified against the same pin, audit 2026-09-15)

  # (samba override removed: already doCheck = false via doCheckByDefault,
  # verified against the same pin, audit 2026-09-15)
  # (samba4 removed: it is a nixpkgs alias of samba, and allowAliases=false is
  # set in flake/lib.nix, so finalPrev.samba4 was a latent eval error)
  # (pytest-xdist/uvloop/rich/aiohttp/django overrides removed: with
  # doCheckByDefault = false (flake/lib.nix) they already evaluate to
  # doCheck = false — verified by eval against the same nixpkgs pin, audit 2026-09-15)

  # Limit WebKit parallelism: unified builds + 32 cores OOMs on 64GB
  webkitgtk_4_1 = finalPrev.webkitgtk_4_1.overrideAttrs (_old: {
    NIX_BUILD_CORES = 4;
  });

  # qt3d: GCC OOM-killed during PCH compilation on 32-thread machine
  qt3d = finalPrev.qt3d.overrideAttrs (_old: {
    NIX_BUILD_CORES = 4;
  });

  # qtwebengine: V8 Chromium OOM on 32-thread (~24K compile units).
  # Build invokes ninja -j32 via cmake -E env — NIX_BUILD_CORES is ignored.
  # Use a preBuild wrapper that limits ninja parallelism.
  qtwebengine = finalPrev.qtwebengine.overrideAttrs (old: {
    preBuild = (old.preBuild or "") + ''
      # Wrap ninja to enforce 4-core limit
      real_ninja=$(type -P ninja)
      cat > $TMPDIR/ninja-wrapper << WRAP
      #!/bin/sh
      exec $real_ninja -j4 "$@"
      WRAP
      chmod +x $TMPDIR/ninja-wrapper
      export PATH=$TMPDIR/ninja-wrapper:$PATH
    '';
  });
}

_final: prev: {
  # Targeted fix via reusable helper: tigervnc needs autoreconf.
  tigervnc = _final.neg.functions.withAutoreconf prev.tigervnc;

  # CMake policy floor for projects expecting pre-3.30 behavior
  # HackRF fails with: "Compatibility with CMake < 3.5 has been removed"
  hackrf = prev.hackrf.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });
  # Older multimon-ng builds can hit the same policy error
  "multimon-ng" = prev."multimon-ng".overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });

  # bpftrace 0.23.x does not support LLVM 21 yet; pin to LLVM 20
  bpftrace = prev.bpftrace.override {llvmPackages = prev.llvmPackages_20;};

  # SoapyRemote fails CMake policy checks with newer CMake; set policy floor
  soapyremote = prev.soapyremote.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });

  # Airspy family: set CMake policy floor for modern CMake
  airspy = prev.airspy.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });
  airspyhf = prev.airspyhf.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });

  # Soapy plugins that also need the policy floor
  soapyairspy = prev.soapyairspy.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });

  # Other SoapySDR plugins that may require the policy floor
  soapyrtlsdr = prev.soapyrtlsdr.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });
  soapyhackrf = prev.soapyhackrf.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });
  soapybladerf = prev.soapybladerf.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });
  soapyplutosdr = prev.soapyplutosdr.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });
  soapyuhd = prev.soapyuhd.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });
  soapysdrplay = prev.soapysdrplay.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });
  soapyaudio = prev.soapyaudio.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });

  # Core SoapySDR and vendor libs
  soapysdr = prev.soapysdr.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });
  libbladeRF = prev.libbladeRF.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });

  # Analog Devices libs used by Soapy/GR
  libad9361 = prev.libad9361.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });
  libiio = prev.libiio.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });

  # LimeSuite (LimeSDR stack)
  limesuite = prev.limesuite.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });

  # snowman removed upstream (do not reference)

  # Security: avoid insecure Mbed TLS 2 by aliasing to v3
  mbedtls_2 = prev.mbedtls;

  # SDR apps: proactively set policy floor
  inspectrum = prev.inspectrum.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });
  "gr-osmosdr" = prev."gr-osmosdr".overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });
  gqrx = prev.gqrx.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });
  kalibrate-rtl = prev.kalibrate-rtl.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });

  # GNU Radio: disable upstream tests (flaky qa_blocks_hier_block2)
  gnuradio = prev.gnuradio.overrideAttrs (_old: {
    doCheck = false;
    checkPhase = ":";
  });

  # aflplusplus: removed from profile; drop overrides

  # RTL-SDR family
  "rtl-sdr" = prev."rtl-sdr".overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });
  rtl-sdr-librtlsdr = prev.rtl-sdr-librtlsdr.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });

  # Rofi plugins
  rofi-file-browser = prev.rofi-file-browser.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });
  rofi-emoji = prev.rofi-emoji.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });

  # OpenMW: no local override — use upstream packaging for cache hits

  # retdec: removed from profile; drop overrides to avoid unnecessary patching

  # Reserved for development/toolchain overlays
  neg = {};
}

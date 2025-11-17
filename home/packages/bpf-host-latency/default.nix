{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
}: let
  py = python3.withPackages (ps: [ps.bcc]);
in
  stdenvNoCC.mkDerivation rec {
    pname = "bpf-host-latency";
    version = "2016-01-28";

    src = ./.;

    nativeBuildInputs = [makeWrapper];

    installPhase = ''
      runHook preInstall
      install -Dm0644 ./bpf-host-latency.py "$out/share/${pname}/bpf-host-latency.py"
      makeWrapper ${py}/bin/python "$out/bin/bpf-host-latency" \
        --add-flags "$out/share/${pname}/bpf-host-latency.py"
      chmod +x "$out/bin/bpf-host-latency"
      runHook postInstall
    '';

    meta = with lib; {
      description = "Trace DNS lookup latency (getaddrinfo/gethostbyname[2]) via BCC/eBPF";
      longDescription = ''
        A packaged variant of Brendan Gregg's gethostlatency tool. Requires root
        privileges and a kernel with eBPF/BCC support.
      '';
      homepage = "https://github.com/iovisor/bcc";
      license = licenses.asl20;
      platforms = platforms.linux;
      mainProgram = "bpf-host-latency";
    };
  }

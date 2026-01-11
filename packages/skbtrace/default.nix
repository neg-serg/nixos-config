{
  lib,
  buildGoModule,
  fetchFromGitHub,
  bpftrace,
}:
buildGoModule rec {
  pname = "skbtrace";
  version = "unstable-2024-07-08";

  src = fetchFromGitHub {
    owner = "yandex-cloud";
    repo = "skbtrace";
    rev = "a7d6218d7c7430f48d591252648af22c7e9b1e34";
    hash = "sha256-jmL95Ji4Oe7UAUfPK3kEYKSaH/BCq0i9sPS9ZRP/Rqc=";
  };

  vendorHash = "sha256-6ZtoZhKtNZ9iWCTYYZsmF64T55ovb12Id9EPtuChyEw=";

  subPackages = [ "cmd" ];

  propagatedBuildInputs = [ bpftrace ];

  meta = with lib; {
    description = "BPFTrace helper for tracing socket buffers via eBPF";
    longDescription = ''
      Generates and runs BPFTrace scripts for inspecting socket buffers. Requires
      an eBPF-capable kernel, root privileges, and available bpftrace runtime.
    '';
    homepage = "https://github.com/yandex-cloud/skbtrace";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "skbtrace";
    platforms = platforms.linux;
  };
}

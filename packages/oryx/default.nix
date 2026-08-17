{
  lib,
  stdenv,
  fetchurl,
}:

# Oryx — TUI for sniffing network traffic using eBPF (Rust + Aya).
# Pre-built musl static binary from the release page; no runtime deps.
# Requires a kernel with CONFIG_DEBUG_INFO_BTF=y and CONFIG_NET_CLS_BPF=y
# (see modules/system/kernel/overlay.config) and root (sudo oryx).
let
  version = "0.8.0";
in
stdenv.mkDerivation {
  pname = "oryx";
  inherit version;

  src = fetchurl {
    url = "https://github.com/pythops/oryx/releases/download/v${version}/oryx-x86_64-unknown-linux-musl";
    hash = "sha256-+CghsbqmOlZFo4suPpmD84/6ca5ZJbhucge7PIK9Dqo=";
  };

  dontUnpack = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/oryx"
    runHook postInstall
  '';

  meta = with lib; {
    description = "TUI for sniffing network traffic using eBPF";
    homepage = "https://github.com/pythops/oryx";
    license = licenses.gpl3Only;
    mainProgram = "oryx";
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}

{
  lib,
  buildGoModule,
  fetchFromGitHub,
  hyprland,
  makeWrapper,
}:
buildGoModule rec {
  pname = "niri-screen-time";
  version = "unstable-2026-09-02";

  src = fetchFromGitHub {
    owner = "probeldev";
    repo = "niri-screen-time";
    rev = "147fdc3837b79dfadb54d31a236ede6a6e4fba1a";
    hash = "sha256-LHItt1NLxoWJeyTAsLc7qi3kFzip+Kl6bO53g20zS8I=";
  };

  vendorHash = "sha256-9y1F2ZrmpiQJ9ZTq9SoRE2PxR65DDNCeBKf4M0HUQC4=";

  # The daemon drives `hyprctl activewindow`, which exits 6 when Hyprland's
  # IPC reply misses its 5 s socket read timeout. Upstream panics on any poll
  # error and spawns a goroutine per 200 ms tick, so a starved compositor both
  # piles up hyprctl children and crash-loops the unit. The patch logs a lost
  # sample instead and keeps one poll in flight at a time.
  patches = [ ./daemon-survive-ipc-stalls.patch ];

  nativeBuildInputs = [ makeWrapper ];

  # The daemon shells out to `hyprctl activewindow` (class + title). systemd
  # user services run with a minimal PATH, so hyprland's bin dir is baked into
  # the wrapper instead of relying on the session environment.
  postFixup = ''
    wrapProgram $out/bin/niri-screen-time --prefix PATH : ${lib.makeBinPath [ hyprland ]}
  '';

  meta = lib.mkMeta {
    description = "Screen time tracker by window class/title for Wayland compositors (niri, Hyprland)";
    homepage = "https://github.com/probeldev/niri-screen-time";
    license = lib.licenses.mit;
    mainProgram = "niri-screen-time";
  };
}

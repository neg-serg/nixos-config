{ lib
, rustPlatform
, fetchFromGitHub
, pkg-config
, clang
, gtk4
, libadwaita
, pipewire
}:

rustPlatform.buildRustPackage rec {
  pname = "pw-audioshare";
  version = "1.0.6";

  src = fetchFromGitHub {
    owner = "destructatron";
    repo = "pw-audioshare";
    rev = "v${version}";
    hash = "sha256-JDhxJSZkHzWqJTHBvGlzQk6RM9YwQo5tSxiakRHF2ho=";
  };

  cargoHash = lib.fakeHash;

  nativeBuildInputs = [
    pkg-config
    clang
  ];

  buildInputs = [
    gtk4
    libadwaita
    pipewire
  ];

  meta = with lib; {
    description = "Accessible GTK4 PipeWire patchbay with auto-connect presets";
    longDescription = ''
      An accessible GTK4 patchbay for PipeWire. Unlike visual node-graph tools,
      PW Audioshare uses list-based views that work well with screen readers.
      Features auto-connect presets, system tray, and full keyboard navigation.
    '';
    homepage = "https://github.com/destructatron/pw-audioshare";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "pw-audioshare";
    platforms = platforms.linux;
  };
}

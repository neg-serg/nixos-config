{
  lib,
  buildGoModule,
  fetchgit,
  pkg-config,
  alsa-lib,
}:
buildGoModule {
  pname = "subsonic-tui";
  version = "0-unstable-2025-12-10";

  src = fetchgit {
    url = "https://git.dayanhub.com/sagi/subsonic-tui.git";
    rev = "9dbae78c2facb520193e5a88bb40a5fcd2fb8f5e";
    hash = "sha256-rM9+UZV8Ly4XCBZl3YACQ0wn/y326cZ53c0YZexa9eI=";
  };

  vendorHash = "sha256-PmmoGnMTAHPpCvRbSTWaca6qOWOimQdiHxlWBa4ZW/Q=";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ alsa-lib ];

  meta = {
    description = "Subsonic TUI client";
    homepage = "https://git.dayanhub.com/sagi/subsonic-tui";
    license = lib.licenses.mit;
    maintainers = [ ];
  };
}

{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "iris";
  version = "0.6.3";

  src = fetchFromGitHub {
    owner = "versenilvis";
    repo = "iris";
    rev = "v${version}";
    hash = "sha256-+1FZgqViuQYZkhjxvbAg9l8vvazyA5RACyVRL7ubWHQ=";
  };

  # Go module dependencies (charmbracelet lipgloss/glamour, cobra, modernc sqlite, ...).
  vendorHash = "sha256-h3v9jXYmLJbllzqg+e4wOJZsQ5d+KEeeurTPCGhOlgI=";

  # TestDetectCached_MidSessionFileCreation fails in the Nix sandbox: the
  # cache invalidation relies on directory mtime, but overlayfs doesn't bump
  # it for a file created within the same second. All other tests pass.
  doCheck = false;

  ldflags = [
    "-s"
    "-w"
    "-X github.com/versenilvis/iris/root.Version=v${version}"
  ];

  meta = with lib; {
    description = "IRIS (Intelligent Real-time Input Suggestion) — shell auto-completion that works like code editor's IntelliSense";
    homepage = "https://github.com/versenilvis/iris";
    license = licenses.bsd0;
    maintainers = [ ];
    mainProgram = "iris";
    platforms = platforms.linux;
  };
}

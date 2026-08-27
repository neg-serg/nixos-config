{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "iris";
  # main (c86c0244): adds ghost-text = 2 (ghost text only, no suggestion menu)
  # which v0.6.3 cannot do (its ghost-text is a plain bool and the menu always
  # renders). Unreleased upstream; pinned for reproducibility.
  version = "0.6.3-unstable-2026-08-27";

  src = fetchFromGitHub {
    owner = "versenilvis";
    repo = "iris";
    rev = "c86c0244cf6b02eb8f27482313aaf946c175366e";
    hash = "sha256-3WDH2nunFznhvw8P+UBxcuxGOcSerdyNDen/5seViQA=";
  };

  # Go module dependencies (charmbracelet lipgloss/glamour, cobra, modernc sqlite, ...).
  vendorHash = "sha256-9GZn8xxdWGeAfTjJXj7VF4gyFpsyrNUDHlM+oCxiUAs=";

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

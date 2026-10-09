{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "iris";
  # Tagged release (2026-10-09). Before this the pin was unreleased main
  # c86c0244 (pre-v0.7.0), taken just for ghost-text = 2 — v0.7.0 shipped
  # that as a documented 3-mode option (0 = off, 1 = menu + ghost, 2 = ghost
  # only), along with the arrow-key, atuin/menu and history fixes.
  version = "0.7.3";

  src = fetchFromGitHub {
    owner = "versenilvis";
    repo = "iris";
    rev = "v0.7.3";
    hash = "sha256-7JdwXpt+EDU6fRjBf0kzHwCeB2NFwYk1rSZY790QIag=";
  };

  # Go module dependencies (charmbracelet lipgloss/glamour, cobra, modernc sqlite, ...).
  vendorHash = "sha256-9GZn8xxdWGeAfTjJXj7VF4gyFpsyrNUDHlM+oCxiUAs=";

  # [trantor] The accept key (Ctrl+E / Tab) inserts the menu's current suggestion
  # when the menu is visible, otherwise falls through to the shell so the key
  # keeps its normal meaning (Ctrl+E: end-of-line, Tab: fzf-on-tab / ~/m/new
  # expansion). Upstream always consumes the key, even with a hidden menu —
  # re-checked on v0.7.3: root/wrapper.go still says "always consume the full
  # binding atomically, even when the overlay is hidden".
  patches = [ ./iris-select-fallthrough.patch ];

  # TestDetectCached_MidSessionFileCreation fails in the Nix sandbox: the
  # cache invalidation relies on directory mtime, but overlayfs doesn't bump
  # it for a file created within the same second. All other tests pass.
  doCheck = false;

  ldflags = [
    "-s"
    "-w"
    "-X github.com/versenilvis/iris/root.Version=v${version}"
  ];

  meta = lib.mkMeta {
    description = "IRIS (Intelligent Real-time Input Suggestion) — shell auto-completion that works like code editor's IntelliSense";
    homepage = "https://github.com/versenilvis/iris";
    license = lib.licenses.bsd0;
    mainProgram = "iris";
  };
}

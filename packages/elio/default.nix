{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  zstd,
}:

# elio: three-pane terminal file manager (Places / Files / Preview) on ratatui —
# grid and list views, inline image previews, archive handling, trash, duplicate
# finder, fuzzy find. Not in the pinned nixpkgs; upstream ships nix/package.nix,
# and this keeps its derivation shape (minus the fileset, since fetchFromGitHub
# already delivers the whole tagged tree) so the binary carries the upstream
# desktop entry and hicolor icons.
#
# zstd is a real build input: the zstd crate builds zstd-sys, which is told to
# use the system library through pkg-config instead of vendoring its own C copy.
rustPlatform.buildRustPackage rec {
  pname = "elio";
  version = "1.14.0";

  src = fetchFromGitHub {
    owner = "elio-fm";
    repo = "elio";
    tag = "v${version}";
    hash = "sha256-E4MEr/Hz7CJvnbqTyrf+rVp9CCJLJN7hWRW+DHNCavg=";
  };

  cargoHash = "sha256-Ejk1CJxjKljIhf/Fa12LYCzeubzZ7HGNAh9eo1dK/9I=";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ zstd ];
  env.ZSTD_SYS_USE_PKG_CONFIG = "1";

  # Upstream keeps the suite out of install builds: it drives real shells (bash,
  # zsh, fish, nushell), /proc introspection and a session bus, none of which a
  # Nix builder has. Their flake exposes the full run as a separate check.
  doCheck = false;

  postInstall = ''
    install -Dm644 packaging/linux/elio.desktop "$out/share/applications/elio.desktop"
    mkdir -p "$out/share/icons"
    cp -r packaging/linux/icons/hicolor "$out/share/icons/"
  '';

  meta = lib.mkMeta {
    description = "Terminal file manager with three-pane layout, previews, archives and fuzzy find";
    homepage = "https://github.com/elio-fm/elio";
    license = lib.licenses.mit;
    mainProgram = "elio";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}

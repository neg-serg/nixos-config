{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "zhist";
  version = "1.1.1";

  src = fetchFromGitHub {
    owner = "overflowy";
    repo = "zhist";
    rev = "v${version}";
    hash = "sha256-94XdxL5SvOJp7Ar6FzK955TAL0CVR7DOg2duL0TPImw=";
  };

  # Stdlib-only module (no go.sum entries) — no vendored dependencies.
  vendorHash = null;

  ldflags = [
    "-s"
    "-w"
  ];

  meta = with lib; {
    description = "Smarter shell history for Zsh: stores dir, exit status, and duration per command, with an fzf picker";
    homepage = "https://github.com/overflowy/zhist";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "zhist";
    platforms = platforms.unix;
  };
}

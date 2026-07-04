{
  lib,
  buildGoModule,
  fetchFromGitHub,
  chafa,
  glib,
  pkg-config,
}:

buildGoModule rec {
  pname = "termeverything";
  version = "0.7.8";

  src = fetchFromGitHub {
    owner = "mmulet";
    repo = "term.everything";
    rev = "c8e04be0ae9a05b43f17065fe6b7d2687152f7c4";
    hash = "sha256-bpdp3KHKkHnMaBUzhndiagLRMbCDpoc3I5qIi6gS7WY=";
  };

  vendorHash = null; # no external Go dependencies

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ chafa glib ];

  ldflags = [ "-s" "-w" ];

  subPackages = [ "." ];

  meta = with lib; {
    description = "Run GUI windows inside your terminal — a Wayland compositor that renders to the terminal via ANSI escape codes";
    homepage = "https://github.com/mmulet/term.everything";
    license = licenses.agpl3Only;
    maintainers = [ ];
    platforms = platforms.linux;
    mainProgram = "term.everything";
  };
}

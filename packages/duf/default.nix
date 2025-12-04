{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "duf";
  version = "0.9.1-neg";

  src = fetchFromGitHub {
    owner = "neg-serg";
    repo = "duf";
    rev = "1d76f13b3c43ae7a96aedb59acaaaa8de3c57de4";
    hash = "sha256-0MmC5FxY8Rwnu2J4bwtYJGKaUcpFWRA1HviyNMhnKjY=";
  };

  vendorHash = "sha256-mCOP6R072dmJBHN8c7ae8l7yN1O25FDLIgRGUSWUn2E=";

  ldflags = [
    "-s"
    "-w"
    "-X main.Version=${version}"
  ];

  meta = with lib; {
    description = "Disk Usage/Free Utility (fork with plain style support)";
    homepage = "https://github.com/neg-serg/duf";
    license = licenses.mit;
    maintainers = [];
    mainProgram = "duf";
    platforms = platforms.unix;
  };
}

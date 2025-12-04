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
    rev = "71c5a20c53b775cf9f153384f00c822a370a723c";
    hash = "sha256-/FIKIijqNhOODohKBFcX7xlTyLS2wdK83g5GdQ0v148=";
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

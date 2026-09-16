{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "flow";
  version = "0.2.5";

  src = fetchFromGitHub {
    owner = "programmersd21";
    repo = "flow";
    rev = "v${version}";
    hash = "sha256-V3OPABvWcul5wZEbyyfFnYZxDCfVy4ugye1yntpH1hU=";
  };

  # charmbracelet TUI stack (bubbletea/bubbles/lipgloss) + gopsutil + toml
  vendorHash = "sha256-KwLuF9dMvUgmeoM8K+zMrAH9fa5y1tzWtuGvjY1Q0vE=";

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
  ];

  meta = lib.mkMeta {
    description = "Terminal dashboard for real-time network throughput";
    homepage = "https://github.com/programmersd21/flow";
    license = lib.licenses.mit;
    mainProgram = "flow";
  };
}

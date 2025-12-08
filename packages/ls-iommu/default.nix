{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "ls-iommu";
  version = "2.3.0";

  src = fetchFromGitHub {
    owner = "HikariKnight";
    repo = "ls-iommu";
    rev = version;
    hash = "sha256-1UaYE1Nr91L6tR+9ZaEDLLlY7pVMy4MVXAKNimEl5+I=";
  };

  vendorHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

  subPackages = ["cmd"];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/HikariKnight/ls-iommu/internal/version.Version=${version}"
  ];

  meta = with lib; {
    description = "List devices and their IOMMU groups";
    homepage = "https://github.com/HikariKnight/ls-iommu";
    license = licenses.mit;
    maintainers = [];
    mainProgram = "ls-iommu";
    platforms = platforms.linux;
  };
}

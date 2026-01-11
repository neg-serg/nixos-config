{
  lib,
  buildGoModule,
  makeWrapper,
  hwdata,
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

  vendorHash = "sha256-LwvQj4UcbNk4kG6rE72/NwxQtXr37koC1/NFz7V/Sek=";

  subPackages = [ "cmd" ];

  nativeBuildInputs = [ makeWrapper ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/HikariKnight/ls-iommu/internal/version.Version=${version}"
  ];

  postInstall = ''
    mv "$out/bin/cmd" "$out/bin/${pname}"
    wrapProgram "$out/bin/${pname}" \
      --set PCIDB_PATH ${hwdata}/share/hwdata/pci.ids \
      --set GHW_PCIDB_PATH ${hwdata}/share/hwdata/pci.ids
  '';

  meta = with lib; {
    description = "List devices and their IOMMU groups";
    homepage = "https://github.com/HikariKnight/ls-iommu";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "ls-iommu";
    platforms = platforms.linux;
  };
}

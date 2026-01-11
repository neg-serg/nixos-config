{
  buildPythonApplication,
  fetchFromGitHub,
  poetry-core,
  aiofiles,
  asyncio-dgram,
}:
buildPythonApplication {
  pname = "pyprland";
  version = "2.5.0";
  src = fetchFromGitHub {
    owner = "hyprland-community";
    repo = "pyprland";
    rev = "e82637d73207abd634a96ea21fa937455374d131";
    sha256 = "0znrp6x143dmh40nihlkzyhpqzl56jk7acvyjkgyi6bchzp4a7kn";
  };
  format = "pyproject";
  nativeBuildInputs = [ poetry-core ];
  propagatedBuildInputs = [
    aiofiles
    asyncio-dgram
  ];
  meta.mainProgram = "pypr";
}

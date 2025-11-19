{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage rec {
  pname = "telegram-bot-mcp";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "NexusX-MCP";
    repo = "telegram-mcp-server";
    rev = "e8786bb11f492307311c28ff242c5f6315679ece";
    hash = "sha256-A9U6RfscMllXlcY9lXJDys/8FgxsuG5Xr5HIH3aoZQE=";
  };

  npmDepsHash = "sha256-X08na3K2/UAJpM01UZtfKnmZnQXGddaoB4qWqv/3Ogo=";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    substituteInPlace package.json \
      --replace '"prepare": "npm run build",' ""
  '';

  npmFlags = ["--ignore-scripts"];
  npmInstallFlags = npmFlags;

  meta = with lib; {
    description = "Telegram bot MCP server using Bot API";
    homepage = "https://github.com/NexusX-MCP/telegram-mcp-server";
    license = licenses.mit;
    mainProgram = "tg-mcp";
    platforms = platforms.unix;
  };
}

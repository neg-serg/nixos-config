{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs,
  makeWrapper,
}:
buildNpmPackage rec {
  pname = "telegram-bot-mcp";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "NexusX-MCP";
    repo = "telegram-mcp-server";
    rev = "e8786bb11f492307311c28ff242c5f6315679ece";
    hash = "sha256-A9U6RfscMllXlcY9lXJDys/8FgxsuG5Xr5HIH3aoZQE=";
  };

  npmDepsHash = "sha256-X08na3K2/UAJpM01UZtfKnmZnQXGddaoB4qWqv/3Ogo=";

  npmFlags = ["--ignore-scripts"];
  npmInstallFlags = npmFlags;

  nativeBuildInputs = [makeWrapper];

  postInstall = ''
    makeWrapper ${nodejs}/bin/node $out/bin/telegram-bot-mcp \
      --add-flags $out/lib/node_modules/tg-mcp/dist/index.js
  '';

  meta = with lib; {
    description = "Telegram Bot MCP server";
    homepage = "https://github.com/NexusX-MCP/telegram-mcp-server";
    license = licenses.isc;
    mainProgram = "telegram-bot-mcp";
    platforms = platforms.unix;
    maintainers = [];
  };
}

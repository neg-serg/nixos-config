{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "telegram-mcp";
  version = "0.1.23";

  src = fetchFromGitHub {
    owner = "chaindead";
    repo = "telegram-mcp";
    rev = "v${version}";
    hash = "sha256-QegWkj4RPna1qe041plwGMkupnpZH8T8pjGVBBrgsnE=";
  };

  vendorHash = "sha256-4pKxV43UHWZWRzZ1hVHK4rYX1vUsZK073+kJNHaWzIU=";

  ldflags = [
    "-s"
    "-w"
  ];

  meta = with lib; {
    description = "Telegram MCP server for managing dialogs and messages";
    homepage = "https://github.com/chaindead/telegram-mcp";
    license = licenses.mit;
    mainProgram = "telegram-mcp";
    platforms = platforms.unix;
  };
}

{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage rec {
  pname = "imap-mcp";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "dominik1001";
    repo = "imap-mcp";
    rev = "965b3628a68e80148922f57043ddb6a3e25187ee";
    hash = "sha256-gENdZskOFtbpyfeufCByAIW0JvOUzTs7YAQ4TrMj3bw=";
  };

  npmDepsHash = "sha256-u9B/yKEnBtBqlfMzOX88rvolqL8ylEAbmBlGtaKuNOo=";

  meta = with lib; {
    description = "IMAP MCP server for managing mailboxes";
    homepage = "https://github.com/dominik1001/imap-mcp";
    license = licenses.mit;
    mainProgram = "imap-mcp";
    platforms = platforms.unix;
  };
}

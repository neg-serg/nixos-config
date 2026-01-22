{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  sqlite,
}:
stdenv.mkDerivation rec {
  pname = "sqlitecpp";
  version = "3.3.1";

  src = fetchFromGitHub {
    owner = "SRombauts";
    repo = "SQLiteCpp";
    rev = version;
    hash = "sha256-8l1JRaE7w9vJ4bCSLGAk9zwYHDFeKkBi9pE5fUJfLRc=";
  };

  nativeBuildInputs = [
    cmake
    ninja
  ];

  buildInputs = [ sqlite ];

  cmakeFlags = [
    "-DSQLITECPP_INTERNAL_SQLITE=ON"
    "-DSQLITE_ENABLE_FTS5=ON"
    "-DSQLITECPP_BUILD_TESTS=OFF"
    "-DSQLITECPP_BUILD_EXAMPLES=OFF"
  ];

  meta = with lib; {
    description = "SQLiteC++ (SQLiteCpp) is a smart and easy to use C++ SQLite3 wrapper";
    homepage = "https://github.com/SRombauts/SQLiteCpp";
    license = licenses.mit;
    platforms = platforms.all;
  };
}

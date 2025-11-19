with import <nixpkgs> {}; # Import nixpkgs

  stdenv.mkDerivation rec {
    pname = "hellcard";
    version = "unstable-2025-04-23";

    src = fetchFromGitHub {
      owner = "danihek";
      repo = "hellcard";
      rev = "62fd97f7c71b52cdb630cb55ac18b9b9fc07ce45";
      hash = "sha256-LZfz2NZ8ibf1Pdut7vP+Lgj+8HpugvctxIuSI76LHcc=";
    };

    # Ensure all required build dependencies are listed here
    buildInputs = [
      # Example: add dependencies if needed
      # cmake
      # pkg-config
    ];

    # Optional: custom build phases if the project requires them
    buildPhase = ''
      make  # or other build commands
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp hellcard $out/bin/  # ensure the binary name/path is correct
    '';

    meta = {
      description = "";
      homepage = "https://github.com/danihek/hellcard";
      license = lib.licenses.mit;
      platforms = lib.platforms.all;
    };
  }

______________________________________________________________________

## description: Create custom package / overlay

# Add Custom Package

## Steps

### 1. Create package directory:

```bash
mkdir -p packages/my-package
```

### 2. Write derivation:

```nix
# packages/my-package/default.nix
{ pkgs, lib, ... }:

pkgs.stdenv.mkDerivation {
  pname = "my-package";
  version = "1.0.0";
  
  src = pkgs.fetchFromGitHub {
    owner = "username";
    repo = "repo-name";
    rev = "v1.0.0";
    sha256 = lib.fakeSha256;
  };
  
  buildInputs = [ pkgs.some-dependency ];
  
  meta = with lib; {
    description = "My custom package";
    license = licenses.mit;
  };
}
```

### 3. Add to overlay:

```nix
# packages/overlay.nix
final: prev: {
  my-package = final.callPackage ./my-package { };
}
```

### 4. Use in configuration:

```nix
environment.systemPackages = [ pkgs.my-package ];
```

## Script Packages

For simple scripts:

```nix
pkgs.writeShellApplication {
  name = "my-script";
  runtimeInputs = [ pkgs.jq pkgs.curl ];
  text = ''
    #!/usr/bin/env bash
    echo "Hello, world!"
  '';
}
```

## In-tree projects

A project that lives in the repo and carries its own manifest (`Cargo.toml`)
takes its version from that file instead of repeating a literal:

```nix
# packages/my-package/default.nix
{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "my-package";
  version = (lib.importTOML ./Cargo.toml).package.version;
  # ...
}
```

`just bump <package> [<version>]` bumps the manifest and its lockfile(s); the
derivation and the binary (`CARGO_PKG_VERSION`) follow without an edit here.
The `manifest-version` lint guard rejects a literal next to a `Cargo.toml`.

## Get Hash

```bash
nix-prefetch-url --unpack https://github.com/user/repo/archive/v1.0.0.tar.gz
```

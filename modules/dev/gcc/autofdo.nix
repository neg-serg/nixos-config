{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.dev.gcc.autofdo;
in {
  options.dev.gcc.autofdo = {
    enable = lib.mkEnableOption "Install AutoFDO tooling (sample-based PGO helpers).";

    gccProfile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a GCC AutoFDO profile file (e.g., .afdo) to use for sample PGO.
        When set, helper wrappers `gcc-afdo` and `g++-afdo` are provided which
        call GCC with `-fauto-profile=<path>` automatically.
      '';
      example = "/var/lib/afdo/myprofile.afdo";
    };

    clangProfile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to an LLVM/Clang sample profile (e.g., .prof, .profdata, or .yaml)
        for SamplePGO. When set, helper wrappers `clang-afdo` and `clang++-afdo`
        are provided which call Clang with `-fprofile-sample-use=<path>`.
      '';
      example = "/var/lib/afdo/llvm.prof";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable (let
      hasAutofdo = pkgs ? autofdo;
    in {
      # Install AutoFDO tools only if available in the pinned nixpkgs.
      # If unavailable, silently skip to keep evaluation noise-free.
      environment.systemPackages = lib.optionals hasAutofdo [pkgs.autofdo];
    }))

    (lib.mkIf (cfg.gccProfile != null) {
      environment.systemPackages = let
        gccFlags = "-fauto-profile=${toString cfg.gccProfile}";
      in [
        (pkgs.writeShellScriptBin "gcc-afdo" ''
          exec gcc ${gccFlags} "$@"
        '')
        (pkgs.writeShellScriptBin "g++-afdo" ''
          exec g++ ${gccFlags} "$@"
        '')
      ];
    })

    (lib.mkIf (cfg.clangProfile != null) {
      environment.systemPackages = let
        clangFlags = "-fprofile-sample-use=${toString cfg.clangProfile}";
      in [
        (pkgs.writeShellScriptBin "clang-afdo" ''
          exec clang ${clangFlags} "$@"
        '')
        (pkgs.writeShellScriptBin "clang++-afdo" ''
          exec clang++ ${clangFlags} "$@"
        '')
      ];
    })
  ];
}

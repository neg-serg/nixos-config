{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  enabled = config.features.llm.enable or false;
  cfg = config.services.colibri;

  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    torch
    safetensors
    huggingface-hub
    numpy
    tokenizers
    datasets
  ]);

  mkColibri =
    { arch ? "x86-64-v3" }:
    pkgs.stdenv.mkDerivation {
      pname = "colibri";
      version = "1.0";
      src = inputs.colibri;

      nativeBuildInputs = [ pkgs.makeWrapper ];

      buildInputs = [
        pkgs.gcc
        pkgs.gmp
      ];

      ARCH = arch;

      buildPhase = ''
        runHook preBuild
        make -C c glm ARCH="$ARCH"
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        cp c/glm $out/bin/glm

        mkdir -p $out/share/colibri
        cp c/coli $out/share/colibri/coli
        chmod +x $out/share/colibri/coli
        cp -r c/tools $out/share/colibri/tools

        makeWrapper ${pythonEnv}/bin/python $out/bin/coli \
          --add-flags "$out/share/colibri/coli" \
          --set PYTHONPATH "${pythonEnv}/${pkgs.python3.sitePackages}"
        runHook postInstall
      '';

      meta = with pkgs.lib; {
        description = "Run GLM-5.2 (744B MoE) on a consumer machine with ~25 GB RAM";
        homepage = "https://github.com/JustVugg/colibri";
        license = licenses.asl20;
        platforms = platforms.linux;
        mainProgram = "glm";
      };
    };
in
{
  options.services.colibri = {
    enable = lib.mkEnableOption ''
      colibrì — inference engine for GLM-5.2 (744B MoE).
      Runs frontier-class model on consumer hardware by streaming
      experts from disk. Pure C engine, no GPU required.

      Requires ~370 GB free disk space for the converted int4 model.
      Download from: https://huggingface.co/mateogrgic/GLM-5.2-colibri-int4-with-int8-mtp

      On this machine (Ryzen 9 9950X3D · AVX-512+VNNI · 60 GB · PCIe 5.0 NVMe):
      expected decode ~0.8–1.6 tok/s with warm cache and MTP speculation.
    '';

    modelDir = lib.mkOption {
      type = lib.types.str;
      default = "/zero/llm/glm52_i4";
      description = ''
        Path to the converted int4 model directory (~370 GB).
        Download: `coli convert --model <path>` after installing colibri,
        or obtain pre-converted weights from Hugging Face.
      '';
    };

    arch = lib.mkOption {
      type = lib.types.enum [
        "x86-64-v3"
        "native"
      ];
      default = "native";
      description = ''
        CPU microarchitecture target for the C engine.
        `native` enables AVX-512+VNNI on Zen 4/5 (1.3–2× faster matmul).
        `x86-64-v3` builds a portable AVX2 binary for distribution.
      '';
    };

    ramBudget = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = ''
        RAM budget in GB for the engine (expert cache + dense model).
        `null` means auto-detect from available system memory.
        On a 60 GB machine, set to 45 to leave headroom for desktop.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        DIRECT = "1";
        MTP = "3";
        PIPE_WORKERS = "16";
      };
      description = ''
        Extra environment variables passed to `coli`. Common knobs:

        Performance (for PCIe 5.0 NVMe + AVX-512 CPU):
        - `DIRECT=1` — O_DIRECT disk reads (bypass page cache)
        - `PREFETCH=1` — async expert readahead
        - `PIPE_WORKERS=N` — parallel I/O threads (set to core count)

        Speculative decoding (MTP):
        - `MTP=N` — MTP draft depth (3 is typical; 0 to disable)
        - MTP gives 2.2–2.8× tokens per forward when cache is warm;
          on cold cache it routes to extra experts — disable on first run.

        Expert caching:
        - `PIN=/path/stats.txt` — pin hot experts from usage profile
        - `PIN_GB=N` — gigabytes of RAM for pinned hot experts
        - Collect usage history first: `STATS=stats.txt coli chat`

        Other:
        - `KVSAVE=1` — persist compressed KV-cache across restarts
        - `THINK=1` — enable GLM-5.2 reasoning block
        - `GRAMMAR=file.gbnf` — grammar-constrained output
      '';
    };

    serve = {
      enable = lib.mkEnableOption "OpenAI-compatible HTTP API server (coli serve --model ...)";
      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Bind address for the API server.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 8000;
        description = "Port for the OpenAI-compatible API.";
      };
      modelId = lib.mkOption {
        type = lib.types.str;
        default = "glm-5.2-colibri";
        description = "Model identifier reported by the API.";
      };
      apiKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to file containing API key. Unauthenticated if null.";
      };
    };
  };

  config = lib.mkIf enabled {
    services.colibri = {
      arch = lib.mkDefault "native";
      modelDir = lib.mkDefault "/zero/llm/glm52_i4";
      ramBudget = lib.mkDefault 45;

      settings = lib.mkDefault {
        DIRECT = "1";
        PIPE_WORKERS = "16";
        PREFETCH = "1";
        MTP = "3";
      };
    };
  }
  // (lib.mkIf (enabled && cfg.enable) (
    let
      pkg = mkColibri { arch = cfg.arch; };
      env = cfg.settings // {
        COLI_MODEL = cfg.modelDir;
      } // lib.optionalAttrs (cfg.ramBudget != null) {
        RAM_GB = toString cfg.ramBudget;
      };
      envList = lib.mapAttrsToList (k: v: "${k}=${v}") env;
      wrappedColi = pkgs.writeShellScriptBin "coli" ''
        export ${lib.concatStringsSep " " envList}
        exec ${pkg}/bin/coli "$@"
      '';
    in
    {
      environment.systemPackages = [
        pkg
        wrappedColi
      ];

      systemd.services.colibri-serve = lib.mkIf cfg.serve.enable (
        let
          apiKeyArgs = lib.optionalString (cfg.serve.apiKeyFile != null)
            "--api-key-file ${cfg.serve.apiKeyFile}";
        in
        {
          description = "colibrì OpenAI-compatible API server";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          environment = env // lib.optionalAttrs (cfg.serve.apiKeyFile != null) {
            COLI_API_KEY = "$(cat ${cfg.serve.apiKeyFile})";
          };
          serviceConfig = {
            ExecStart = "${pkg}/bin/coli serve"
              + " --host ${cfg.serve.host}"
              + " --port ${toString cfg.serve.port}"
              + " --model-id ${cfg.serve.modelId}"
              + " ${apiKeyArgs}";
            Restart = "on-failure";
            RestartSec = "10";
            DynamicUser = true;
            StateDirectory = "colibri";
            WorkingDirectory = "/var/lib/colibri";
            LimitNOFILE = 65536;
            MemoryHigh = if cfg.ramBudget != null
            then "${toString (cfg.ramBudget + 4)}G"
            else "50G";
          };
        }
      );

      networking.firewall = lib.mkIf cfg.serve.enable (
        lib.mkIf (cfg.serve.host != "127.0.0.1") {
          allowedTCPPorts = [ cfg.serve.port ];
        }
      );
    }
  ));
}

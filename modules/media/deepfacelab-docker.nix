{ lib, config, pkgs, ... }:
let
  mainUser = config.users.main.name or "neg";
  homeDir = "/home/${mainUser}";
  enabled = config.roles.media.enable or false;

  deepfacelabRoot = "${homeDir}/vid/deepfacelab";
  dataDir = "${deepfacelabRoot}/data";
  repoDir = "${deepfacelabRoot}/repo";

  deepfacelabDocker = pkgs.writeShellScriptBin "deepfacelab-docker" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    IMAGE="${DFL_DOCKER_IMAGE:-ubuntu}"
    REPO_DIR="${DFL_REPO_DIR:-${repoDir}}"
    DATA_DIR="${DFL_DATA_DIR:-${dataDir}}"

    if ! command -v docker >/dev/null 2>&1; then
      echo "deepfacelab-docker: docker not found in PATH" >&2
      exit 1
    fi

    mkdir -p "$REPO_DIR" "$DATA_DIR"

    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
      cat <<'EOF'
Usage: deepfacelab-docker [docker-args...] [-- command]

This helper starts an Ubuntu container for DeepFaceLab_Linux.

Defaults (override via env vars):
  DFL_DOCKER_IMAGE  - Docker image (default: ubuntu)
  DFL_REPO_DIR      - host path for repo (default: ~/vid/deepfacelab/repo)
  DFL_DATA_DIR      - host path for data (default: ~/vid/deepfacelab/data)

Inside the container you typically:
  1) apt update && apt install deps per DeepFaceLab_Linux guide
  2) git clone https://github.com/nagadit/DeepFaceLab_Linux.git /workspace
  3) Follow the README inside /workspace.

Examples:
  deepfacelab-docker
    # open bash inside the container in /workspace

  DFL_DOCKER_IMAGE=ubuntu:22.04 deepfacelab-docker
    # override base image (example with explicit tag)
EOF
      exit 0
    fi

    if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
      echo "deepfacelab-docker: pulling image $IMAGE..."
      docker pull "$IMAGE"
    fi

    docker run --rm -it \
      -u "$(id -u):$(id -g)" \
      -v "$REPO_DIR":/workspace \
      -v "$DATA_DIR":/data \
      -w /workspace \
      "$IMAGE" \
      "$@"
  '';
in {
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter [
      deepfacelabDocker # helper to launch DeepFaceLab Ubuntu Docker container
    ];

    systemd.tmpfiles.rules = [
      "d ${deepfacelabRoot} 0750 ${mainUser} ${mainUser} -"
      "d ${dataDir} 0750 ${mainUser} ${mainUser} -"
      "d ${repoDir} 0750 ${mainUser} ${mainUser} -"
    ];
  };
}

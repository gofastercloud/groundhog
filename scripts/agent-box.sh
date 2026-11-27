#!/usr/bin/env bash
# agent-box — Hardened, disposable OrbStack/Docker sandbox mounting ONLY the target directory.
# Auto-starts OrbStack if stopped, auto-builds groundhog-agent-box:latest on first use,
# and runs offline (--network=none, --read-only, --cap-drop=ALL, non-root) by default.
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="${DIR}/${SOURCE}"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
DEFAULT_IMAGE="groundhog-agent-box:latest"
DOCKERFILE_DIR="${SCRIPT_DIR}/agent-box"

NET_MODE="none"
IMAGE="$DEFAULT_IMAGE"
MOUNT_DIR="$PWD"
FORCE_BUILD=0
NO_BUILD=0
CMD=()

usage() {
  cat <<'EOF'
Usage: agent-box [OPTIONS] [-- COMMAND...]

Options:
  --net            Enable outbound bridge network (default: offline / none)
  --image <name>   Container image (default: groundhog-agent-box:latest)
  --dir <path>     Host directory to mount at /workspace (default: $PWD)
  --build          Rebuild the groundhog-agent-box image before running
  --no-build       Fail instead of auto-building if the image is missing
  -h, --help       Show this help

Examples:
  agent-box                                  # Offline interactive bash on $PWD
  agent-box -- make verify                   # Run verify command offline in $PWD
  agent-box --dir ../wt -- uv run pytest -q  # Run tests offline in a worktree
  agent-box --net --image python:3.13-slim   # Custom image with outbound network
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --net)
      NET_MODE="bridge"
      shift
      ;;
    --image)
      IMAGE="${2:?--image requires a value}"
      shift 2
      ;;
    --dir)
      MOUNT_DIR="${2:?--dir requires a value}"
      shift 2
      ;;
    --build)
      FORCE_BUILD=1
      shift
      ;;
    --no-build)
      NO_BUILD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      CMD=("$@")
      break
      ;;
    *)
      CMD=("$@")
      break
      ;;
  esac
done

MOUNT_DIR="$(cd "$MOUNT_DIR" && pwd)"

ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "agent-box: 'docker' CLI not found on PATH. Install OrbStack first." >&2
    exit 1
  fi
  if docker info >/dev/null 2>&1; then
    return 0
  fi
  if ! command -v orb >/dev/null 2>&1; then
    echo "agent-box: Docker daemon is not running and 'orb' CLI was not found. Start OrbStack or Docker and retry." >&2
    exit 1
  fi
  echo "agent-box: OrbStack is stopped — starting it..." >&2
  if ! orb start >/dev/null 2>&1; then
    echo "agent-box: failed to start OrbStack. Open OrbStack.app and check its status." >&2
    exit 1
  fi
  local _
  for _ in $(seq 1 20); do
    if docker info >/dev/null 2>&1; then
      echo "agent-box: OrbStack is ready." >&2
      return 0
    fi
    sleep 1
  done
  echo "agent-box: timed out waiting for Docker daemon after starting OrbStack." >&2
  exit 1
}

ensure_image() {
  if [[ "$FORCE_BUILD" -eq 1 ]]; then
    if [[ ! -f "${DOCKERFILE_DIR}/Dockerfile" ]]; then
      echo "agent-box: Dockerfile not found at ${DOCKERFILE_DIR}/Dockerfile" >&2
      exit 1
    fi
    echo "agent-box: building ${DEFAULT_IMAGE}..." >&2
    docker build -t "$DEFAULT_IMAGE" "$DOCKERFILE_DIR"
    return 0
  fi
  if docker image inspect "$IMAGE" >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$IMAGE" == "$DEFAULT_IMAGE" && "$NO_BUILD" -eq 0 && -f "${DOCKERFILE_DIR}/Dockerfile" ]]; then
    echo "agent-box: ${DEFAULT_IMAGE} not found — building it once..." >&2
    docker build -t "$DEFAULT_IMAGE" "$DOCKERFILE_DIR"
    return 0
  fi
  echo "agent-box: image '${IMAGE}' not found locally (pass --build or pull it first)." >&2
  exit 1
}

ensure_docker
ensure_image

DOCKER_ARGS=(
  run --rm --init
  --network "$NET_MODE"
  --cap-drop=ALL
  --security-opt=no-new-privileges:true
  --read-only
  --tmpfs "/tmp:rw,nosuid,nodev,size=1g"
  --tmpfs "/home/agent:rw,nosuid,nodev,size=512m"
  --pids-limit 256
  -e HOME=/home/agent
  -e UV_CACHE_DIR=/tmp/uv-cache
  -v "${MOUNT_DIR}:/workspace"
  -w /workspace
)

if [[ ${#CMD[@]} -eq 0 ]]; then
  if [[ -t 0 && -t 1 ]]; then
    DOCKER_ARGS+=(-it)
  fi
  echo "agent-box: ${IMAGE} [network=${NET_MODE}, mount=${MOUNT_DIR}:/workspace]" >&2
  exec docker "${DOCKER_ARGS[@]}" "$IMAGE" sh -c 'command -v bash >/dev/null && exec bash || exec sh'
else
  if [[ -t 0 && -t 1 ]]; then
    DOCKER_ARGS+=(-it)
  fi
  exec docker "${DOCKER_ARGS[@]}" "$IMAGE" "${CMD[@]}"
fi

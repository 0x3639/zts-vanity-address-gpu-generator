#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-"$ROOT_DIR/build"}"
BUILD_TYPE="${CMAKE_BUILD_TYPE:-Release}"
BIN="$BUILD_DIR/znn-vanity-cuda"

CUDA_ARCH="${CUDA_ARCH:-}"
DO_BUILD=1
BUILD_ONLY=0
NO_OUTPUT=0

SUFFIX=""
HAS_OUTPUT=0
ARGS=()

usage() {
  cat <<'USAGE'
Usage:
  ./run.sh <suffix> [search options]
  ./run.sh --suffix <suffix> [search options]

Examples:
  ./run.sh znn
  ./run.sh moon --blocks 8192 --threads 128
  ./run.sh moon --arch 86
  ./run.sh moon --base-seed <64_hex_chars> --start 50000000
  ./run.sh moon --no-output

Wrapper options:
  --arch <n>        Set CMAKE_CUDA_ARCHITECTURES, e.g. 86 or 89
  --build-only      Configure and build, then exit
  --no-build        Run existing build/znn-vanity-cuda without building
  --no-output       Do not auto-save to results/<suffix>-<timestamp>.txt
  --help, -h        Show this help

Search options passed to znn-vanity-cuda:
  --suffix <text>          Vanity suffix matched at end of z1 address
  --account-index <n>      Hardened account index, default 0
  --blocks <n>             CUDA blocks per launch, default 4096
  --threads <n>            CUDA threads per block, default 128
  --start <n>              Starting counter, default 0
  --max-attempts <n>       Stop after n candidates, default unlimited
  --base-seed <hex>        32-byte hex base seed for reproducible search
  --output <file>          Append match details to file

Environment:
  CUDA_ARCH=86             Same as --arch 86
  BUILD_DIR=/path/build    Override build directory
  CMAKE_BUILD_TYPE=Debug   Override build type
  CUDAToolkit_ROOT=/path   Forwarded to CMake when set
  JOBS=8                   Build parallelism
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

require_value() {
  local option="$1"
  local value="${2:-}"
  [[ -n "$value" ]] || die "$option requires a value"
}

append_option_with_value() {
  local option="$1"
  local value="$2"
  require_value "$option" "$value"
  ARGS+=("$option" "$value")
}

while (($#)); do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --arch)
      require_value "$1" "${2:-}"
      CUDA_ARCH="$2"
      shift 2
      ;;
    --build-only)
      BUILD_ONLY=1
      shift
      ;;
    --no-build)
      DO_BUILD=0
      shift
      ;;
    --no-output)
      NO_OUTPUT=1
      shift
      ;;
    --suffix|-s)
      require_value "$1" "${2:-}"
      SUFFIX="$2"
      append_option_with_value "$1" "$2"
      shift 2
      ;;
    --output|-o)
      require_value "$1" "${2:-}"
      HAS_OUTPUT=1
      append_option_with_value "$1" "$2"
      shift 2
      ;;
    --account-index|--blocks|--threads|--start|--max-attempts|--base-seed)
      require_value "$1" "${2:-}"
      append_option_with_value "$1" "$2"
      shift 2
      ;;
    --)
      shift
      ARGS+=("$@")
      break
      ;;
    --*)
      ARGS+=("$1")
      shift
      ;;
    *)
      if [[ -z "$SUFFIX" ]]; then
        SUFFIX="$1"
        ARGS+=(--suffix "$1")
      else
        ARGS+=("$1")
      fi
      shift
      ;;
  esac
done

if [[ "$DO_BUILD" -eq 1 ]]; then
  command -v cmake >/dev/null 2>&1 || die "cmake is required"
  command -v nvcc >/dev/null 2>&1 || die "nvcc was not found; install the NVIDIA CUDA Toolkit"

  CMAKE_ARGS=(-S "$ROOT_DIR" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE="$BUILD_TYPE")
  if [[ -n "$CUDA_ARCH" ]]; then
    CMAKE_ARGS+=("-DCMAKE_CUDA_ARCHITECTURES=$CUDA_ARCH")
  fi
  if [[ -n "${CUDAToolkit_ROOT:-}" ]]; then
    CMAKE_ARGS+=("-DCUDAToolkit_ROOT=$CUDAToolkit_ROOT")
  fi

  cmake "${CMAKE_ARGS[@]}"

  BUILD_ARGS=(--build "$BUILD_DIR")
  if [[ -n "${JOBS:-}" ]]; then
    BUILD_ARGS+=(--parallel "$JOBS")
  else
    BUILD_ARGS+=(--parallel)
  fi
  cmake "${BUILD_ARGS[@]}"
fi

if [[ "$BUILD_ONLY" -eq 1 ]]; then
  exit 0
fi

[[ -n "$SUFFIX" ]] || die "missing suffix; run ./run.sh --help"
[[ -x "$BIN" ]] || die "binary not found at $BIN; run without --no-build first"

if [[ "$NO_OUTPUT" -eq 0 && "$HAS_OUTPUT" -eq 0 ]]; then
  mkdir -p "$ROOT_DIR/results"
  SAFE_SUFFIX="$(printf '%s' "$SUFFIX" | tr -c 'A-Za-z0-9._-' '_')"
  TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
  ARGS+=(--output "$ROOT_DIR/results/${SAFE_SUFFIX}-${TIMESTAMP}.txt")
fi

exec "$BIN" "${ARGS[@]}"

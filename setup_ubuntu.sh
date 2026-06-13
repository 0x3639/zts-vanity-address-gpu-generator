#!/usr/bin/env bash
set -euo pipefail

if ! command -v apt-get >/dev/null 2>&1; then
  echo "error: this setup helper requires apt-get (Ubuntu/Debian)." >&2
  exit 1
fi

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  SUDO=()
else
  command -v sudo >/dev/null 2>&1 || {
    echo "error: sudo is required when not running as root." >&2
    exit 1
  }
  SUDO=(sudo)
fi

echo "Updating apt package indexes..."
"${SUDO[@]}" apt-get update

echo "Installing build prerequisites..."
"${SUDO[@]}" apt-get install -y git build-essential cmake ca-certificates

echo
echo "Installed base build tools."

if command -v nvcc >/dev/null 2>&1; then
  echo "CUDA compiler found:"
  nvcc --version
else
  cat <<'MSG'

nvcc was not found.

Install the NVIDIA CUDA Toolkit, then run ./run.sh again.

On many Ubuntu/Debian systems:
  apt-get install -y nvidia-cuda-toolkit

For NVIDIA's latest toolkit packages:
  https://developer.nvidia.com/cuda-downloads

If you are inside Docker, use a CUDA devel image, not a runtime-only image.
Example:
  nvidia/cuda:12.6.3-devel-ubuntu24.04
MSG
fi

# Zenon CUDA Vanity Address Generator

CUDA-powered vanity search for Zenon wallet addresses.

This tool brute-forces Zenon `z1...` wallet addresses on an NVIDIA GPU and
prints a matching address plus the `seed_hex` needed to recreate it with
`znn_sdk_dart`:

```dart
final store = KeyStore.fromSeed(seedHex);
final address = await store.getKeyPair(0).address;
```

It is modeled after
[`0x3639/znn-address-generator`](https://github.com/0x3639/znn-address-generator.git),
but moves the hot search loop to CUDA.

## Current Scope

The current CUDA backend searches Zenon wallet addresses that start with `z1`.
It does not yet generate Zenon token standards that start with `zts1`, and it
does not yet produce BIP39 mnemonic phrases.

The result is still usable by the Zenon SDK through `KeyStore.fromSeed(seedHex)`.
BIP39 mnemonic search can be added later as a separate mode, but it requires a
GPU PBKDF2-HMAC-SHA512 path over generated mnemonic sentences.

## Requirements

Build and run this on a machine with:

- NVIDIA GPU
- NVIDIA CUDA Toolkit with `nvcc`
- CMake 3.24 or newer
- C++17-capable host compiler
- Optional: Dart SDK for result validation with `znn_sdk_dart`

Check the CUDA compiler:

```bash
nvcc --version
```

Check the GPU:

```bash
nvidia-smi
```

## Fresh Ubuntu/Debian Setup

These commands are the fastest path on a fresh NVIDIA Linux machine.

1. Log in to the GPU machine.

```bash
ssh <user>@<gpu-machine>
```

2. Confirm the NVIDIA driver can see the GPU.

```bash
nvidia-smi
```

If this command is missing or does not show a GPU, install/fix the NVIDIA
driver before continuing.

3. Install common build tools.

```bash
sudo apt update
sudo apt install -y git build-essential cmake
```

4. Install the CUDA Toolkit if `nvcc` is missing.

```bash
nvcc --version
```

If that fails, install CUDA with one of these approaches:

```bash
sudo apt install -y nvidia-cuda-toolkit
```

For the newest NVIDIA-packaged toolkit, use NVIDIA's official Linux CUDA
instructions and select your distro, version, architecture, and the `deb
(network)` installer:

```text
https://docs.nvidia.com/cuda/cuda-installation-guide-linux/
https://developer.nvidia.com/cuda-downloads
```

After installation, open a new shell or add CUDA to your path if needed:

```bash
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}
nvcc --version
```

5. Clone this repository.

```bash
git clone https://github.com/0x3639/zts-vanity-address-gpu-generator.git
cd zts-vanity-address-gpu-generator
```

6. Make the wrapper executable.

```bash
chmod +x run.sh
```

7. Pick your CUDA architecture.

Use `86` if you are unsure and are on a common RTX 30/A10/A40/A6000 machine.
Use this quick guide for common GPUs:

```text
T4 / RTX 20xx              75
A100                       80
RTX 30xx / A10 / A40       86
L4 / L40 / RTX 40xx        89
H100 / H200                90
```

8. Build and run a short suffix search.

```bash
./run.sh znn --arch 86
```

Replace `86` with the architecture for your GPU. Replace `znn` with the suffix
you want at the end of the address.

9. Run a real search and save the result automatically.

```bash
./run.sh moon --arch 86 --blocks 8192 --threads 128
```

When it finds a match, the result prints in the terminal and is also saved in
`results/`.

10. Verify the generated seed with the Zenon Dart SDK.

Install Dart if needed, then run:

```bash
dart pub get
dart run tools/validate_seed.dart <seed_hex_from_output> 0
```

The printed address must match the CUDA output.

## Easy Script

The easiest way to build and run is the wrapper script:

```bash
./run.sh znn
```

That command configures/builds the CUDA binary if needed, creates `results/`,
runs the search for an address ending in `znn`, and saves the match to a
timestamped file such as `results/znn-20260613_153000.txt`.

If your checkout did not preserve the executable bit, run:

```bash
chmod +x run.sh
```

Use a specific CUDA architecture:

```bash
./run.sh znn --arch 86
```

Pass search options through to the CUDA binary:

```bash
./run.sh moon --blocks 8192 --threads 128
```

Run without auto-saving:

```bash
./run.sh moon --no-output
```

Build only:

```bash
./run.sh --build-only --arch 86
```

Run an existing build without rebuilding:

```bash
./run.sh moon --no-build
```

Wrapper options:

```text
--arch <n>        Set CMAKE_CUDA_ARCHITECTURES, e.g. 86 or 89
--build-only      Configure and build, then exit
--no-build        Run existing build/znn-vanity-cuda without building
--no-output       Do not auto-save to results/<suffix>-<timestamp>.txt
--help, -h        Show wrapper help
```

Environment variables:

```text
CUDA_ARCH=86             Same as --arch 86
BUILD_DIR=/path/build    Override build directory
CMAKE_BUILD_TYPE=Debug   Override build type
CUDAToolkit_ROOT=/path   Forwarded to CMake when set
JOBS=8                   Build parallelism
```

## Manual Build

Default release build:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

If CMake cannot infer the CUDA architecture, set it manually. Examples:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_ARCHITECTURES=86
cmake --build build -j
```

Common architecture values include `75` for many RTX 20 cards, `86` for many
RTX 30 cards, `89` for many RTX 40 cards, and `90` for H100-class cards. Use
the value that matches your GPU.

If CUDA is installed outside the default location, pass `CUDAToolkit_ROOT`:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCUDAToolkit_ROOT=/usr/local/cuda
cmake --build build -j
```

## Manual Run

Find a Zenon address ending in `znn`:

```bash
./build/znn-vanity-cuda --suffix znn
```

Save the match to a file:

```bash
mkdir -p results
./build/znn-vanity-cuda --suffix moon --output results/moon.txt
```

Use a larger launch size on a strong GPU:

```bash
./build/znn-vanity-cuda --suffix moon --blocks 8192 --threads 128
```

## Command Options

```text
--suffix <text>          Required vanity suffix, matched at end of z1 address
--account-index <n>      Hardened account index, default 0
--blocks <n>             CUDA blocks per launch, default 4096
--threads <n>            CUDA threads per block, default 128
--start <n>              Starting counter, default 0
--max-attempts <n>       Stop after n candidates, default unlimited
--base-seed <hex>        32-byte hex base seed for reproducible search
--output <file>          Append match details to file
--help                   Show CLI help
```

## Suffix Rules

Suffixes are matched at the end of the full Bech32 address, including checksum
characters.

Valid suffix characters are Bech32 characters:

```text
qpzry9x8gf2tvdw0s3jn54khce6mua7l
```

That means `1`, `b`, `i`, and `o` are not valid. The tool lowercases suffix
input automatically.

Expected work is roughly:

```text
32^suffix_length attempts
```

Examples:

```text
3 characters: about 32,768 attempts
4 characters: about 1,048,576 attempts
5 characters: about 33,554,432 attempts
6 characters: about 1,073,741,824 attempts
```

## Output

A successful run prints fields like:

```text
Found match
address: z1...
seed_hex: ...
private_key_hex: ...
public_key_hex: ...
derivation_path: m/44'/73404'/0'
counter: ...
base_seed_hex: ...
checked: ...
elapsed_seconds: ...
rate: ... seeds/sec
```

Field meanings:

- `address`: matching Zenon wallet address.
- `seed_hex`: secret wallet seed to use with `KeyStore.fromSeed(seedHex)`.
- `private_key_hex`: derived private key for the reported account index.
- `public_key_hex`: public key used to compute the address.
- `derivation_path`: Zenon SDK derivation path.
- `counter`: counter that generated this candidate from `base_seed_hex`.
- `base_seed_hex`: 32-byte search-stream seed.
- `checked`: number of candidates checked in this run.
- `rate`: measured candidate rate.

## Reproduce Or Resume A Search

By default the tool creates a random `base_seed_hex` each run. To make a search
reproducible, provide your own 32-byte base seed:

```bash
./build/znn-vanity-cuda \
  --suffix moon \
  --base-seed 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f
```

To resume from a later counter, use the same `--base-seed` and pass `--start`:

```bash
./build/znn-vanity-cuda \
  --suffix moon \
  --base-seed 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f \
  --start 50000000
```

To split work across multiple machines, give every machine the same
`--base-seed` but a different `--start` range and `--max-attempts`:

```bash
./build/znn-vanity-cuda --suffix moon --base-seed <hex> --start 0        --max-attempts 100000000
./build/znn-vanity-cuda --suffix moon --base-seed <hex> --start 100000000 --max-attempts 100000000
./build/znn-vanity-cuda --suffix moon --base-seed <hex> --start 200000000 --max-attempts 100000000
```

## Validate A Result

Use the official Zenon Dart SDK helper after a match:

```bash
dart pub get
dart run tools/validate_seed.dart <seed_hex> 0
```

The printed address should exactly match the CUDA result. The second argument
is the account index; use the same value you passed to `--account-index`.

## Use The Seed In Dart

```dart
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

Future<void> main() async {
  const seedHex = '<seed_hex from CUDA output>';
  final store = KeyStore.fromSeed(seedHex);
  final address = await store.getKeyPair(0).address;
  print(address);
}
```

## Security Notes

Treat `seed_hex` as the wallet secret. Anyone who has it can control the
matching address.

Also keep `base_seed_hex` private if you plan to resume or reproduce a search
stream. `base_seed_hex` plus `counter` recreates the candidate seed stream.

Do not paste generated secrets into chat, logs, issue trackers, or terminals
you do not control.

## Troubleshooting

`Failed to find nvcc`

Install the NVIDIA CUDA Toolkit or point CMake at it:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCUDAToolkit_ROOT=/usr/local/cuda
```

`CMAKE_CUDA_ARCHITECTURES must be non-empty`

Pass your GPU architecture explicitly:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_ARCHITECTURES=86
```

`Invalid suffix character`

Use only Bech32 characters:

```text
qpzry9x8gf2tvdw0s3jn54khce6mua7l
```

`No match found after ... attempts`

The run hit `--max-attempts` before finding a match. Increase
`--max-attempts`, shorten the suffix, or resume with the same `--base-seed`
and a later `--start`.

# ZTS Vanity Address Generator

CUDA-powered Zenon wallet vanity search.

This tool searches Zenon wallet addresses (`z1...`) for a suffix at the end of
the address, then prints the matching address plus the 64-byte seed hex used by
Zenon SDK's `KeyStore.fromSeed(seedHex)`.

It is modeled after [`0x3639/znn-address-generator`](https://github.com/0x3639/znn-address-generator.git),
but the brute-force loop runs on an NVIDIA CUDA GPU.

## What It Searches

The CUDA kernel generates candidate 64-byte seeds from a private 32-byte base
seed and a counter:

```text
candidate_seed = SHA512(base_seed || counter)
```

For every candidate seed it derives the Zenon private key using the SDK path:

```text
m/44'/73404'/<account-index>'
```

Then it computes:

```text
Ed25519 public key -> SHA3-256(public key)[0..19] -> Bech32 z1 address
```

The suffix is matched against the end of the full Bech32 address, including the
checksum characters. Example: `--suffix znn` finds addresses ending in `znn`.

## Build

Requires an NVIDIA GPU and CUDA Toolkit with `nvcc`.

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

If CMake cannot infer your GPU architecture, set it manually:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_ARCHITECTURES=86
```

## Run

```bash
./build/znn-vanity-cuda --suffix znn
```

Useful options:

```text
--suffix <text>          Required vanity suffix, matched at the end
--account-index <n>      Derivation account index, default 0
--blocks <n>             CUDA blocks per launch, default 4096
--threads <n>            CUDA threads per block, default 128
--start <n>              Starting counter, default 0
--max-attempts <n>       Stop after n candidates, default 0 means unlimited
--base-seed <hex>        32-byte hex base seed for reproducible search
--output <file>          Append the match to a file
```

Example:

```bash
./build/znn-vanity-cuda --suffix moon --blocks 8192 --threads 128 --output results/moon.txt
```

Expected attempts are roughly `32^suffix_length`, because Zenon addresses use
the Bech32 character set.

## Validate A Result

After the CUDA tool prints a match, verify the address with the official SDK:

```bash
dart pub get
dart run tools/validate_seed.dart <seed_hex> 0
```

The printed address should match the CUDA result.

## Important

Treat `seed_hex` as the wallet secret. Anyone who has it can control the
matching address. Also keep `base_seed_hex` private if you plan to resume or
reproduce a search stream.

This first CUDA backend searches SDK seed hex values, not BIP39 mnemonic
sentences. The resulting seed can be used with:

```dart
final store = KeyStore.fromSeed(seedHex);
final address = await store.getKeyPair(0).address;
```

BIP39 mnemonic vanity search is slower and needs an additional GPU PBKDF2-HMAC-
SHA512 path over the generated mnemonic sentence. That can be added as a second
mode after the raw SDK-seed CUDA path is benchmarked.

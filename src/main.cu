// CUDA Zenon vanity address search.
//
// This searches raw Zenon SDK seed hex values. A matching seed can be loaded
// with KeyStore.fromSeed(seedHex) in znn_sdk_dart.

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <random>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#define HD __host__ __device__
#define DEV __device__

using u8 = unsigned char;
using u32 = unsigned int;
using u64 = unsigned long long;
using i64 = long long;
using gf = i64[16];

static constexpr int kAddressLength = 40;
static constexpr int kSeedLength = 64;
static constexpr int kPrivateKeyLength = 32;
static constexpr int kPublicKeyLength = 32;
static constexpr char kBech32Charset[] = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";

__constant__ u8 d_base_seed[32];
__constant__ char d_suffix[41];
__constant__ int d_suffix_len;

struct SearchResult {
  int found;
  u64 counter;
  u8 seed[kSeedLength];
  u8 private_key[kPrivateKeyLength];
  u8 public_key[kPublicKeyLength];
  char address[kAddressLength + 1];
};

static void cuda_check(cudaError_t err, const char* expr, const char* file, int line) {
  if (err != cudaSuccess) {
    std::ostringstream oss;
    oss << file << ":" << line << " CUDA error after " << expr << ": "
        << cudaGetErrorString(err);
    throw std::runtime_error(oss.str());
  }
}

#define CUDA_CHECK(expr) cuda_check((expr), #expr, __FILE__, __LINE__)

HD static inline u64 rotr64(u64 x, int c) {
  return (x >> c) | (x << (64 - c));
}

HD static inline u64 load64_be(const u8* x) {
  u64 u = 0;
  for (int i = 0; i < 8; ++i) {
    u = (u << 8) | x[i];
  }
  return u;
}

HD static inline void store64_be(u8* x, u64 u) {
  for (int i = 7; i >= 0; --i) {
    x[i] = static_cast<u8>(u & 0xff);
    u >>= 8;
  }
}

HD static inline void store64_le(u8* x, u64 u) {
  for (int i = 0; i < 8; ++i) {
    x[i] = static_cast<u8>(u & 0xff);
    u >>= 8;
  }
}

static constexpr u64 kSha512Iv[8] = {
    0x6a09e667f3bcc908ULL, 0xbb67ae8584caa73bULL,
    0x3c6ef372fe94f82bULL, 0xa54ff53a5f1d36f1ULL,
    0x510e527fade682d1ULL, 0x9b05688c2b3e6c1fULL,
    0x1f83d9abfb41bd6bULL, 0x5be0cd19137e2179ULL};

static constexpr u64 kSha512K[80] = {
    0x428a2f98d728ae22ULL, 0x7137449123ef65cdULL,
    0xb5c0fbcfec4d3b2fULL, 0xe9b5dba58189dbbcULL,
    0x3956c25bf348b538ULL, 0x59f111f1b605d019ULL,
    0x923f82a4af194f9bULL, 0xab1c5ed5da6d8118ULL,
    0xd807aa98a3030242ULL, 0x12835b0145706fbeULL,
    0x243185be4ee4b28cULL, 0x550c7dc3d5ffb4e2ULL,
    0x72be5d74f27b896fULL, 0x80deb1fe3b1696b1ULL,
    0x9bdc06a725c71235ULL, 0xc19bf174cf692694ULL,
    0xe49b69c19ef14ad2ULL, 0xefbe4786384f25e3ULL,
    0x0fc19dc68b8cd5b5ULL, 0x240ca1cc77ac9c65ULL,
    0x2de92c6f592b0275ULL, 0x4a7484aa6ea6e483ULL,
    0x5cb0a9dcbd41fbd4ULL, 0x76f988da831153b5ULL,
    0x983e5152ee66dfabULL, 0xa831c66d2db43210ULL,
    0xb00327c898fb213fULL, 0xbf597fc7beef0ee4ULL,
    0xc6e00bf33da88fc2ULL, 0xd5a79147930aa725ULL,
    0x06ca6351e003826fULL, 0x142929670a0e6e70ULL,
    0x27b70a8546d22ffcULL, 0x2e1b21385c26c926ULL,
    0x4d2c6dfc5ac42aedULL, 0x53380d139d95b3dfULL,
    0x650a73548baf63deULL, 0x766a0abb3c77b2a8ULL,
    0x81c2c92e47edaee6ULL, 0x92722c851482353bULL,
    0xa2bfe8a14cf10364ULL, 0xa81a664bbc423001ULL,
    0xc24b8b70d0f89791ULL, 0xc76c51a30654be30ULL,
    0xd192e819d6ef5218ULL, 0xd69906245565a910ULL,
    0xf40e35855771202aULL, 0x106aa07032bbd1b8ULL,
    0x19a4c116b8d2d0c8ULL, 0x1e376c085141ab53ULL,
    0x2748774cdf8eeb99ULL, 0x34b0bcb5e19b48a8ULL,
    0x391c0cb3c5c95a63ULL, 0x4ed8aa4ae3418acbULL,
    0x5b9cca4f7763e373ULL, 0x682e6ff3d6b2b8a3ULL,
    0x748f82ee5defb2fcULL, 0x78a5636f43172f60ULL,
    0x84c87814a1f0ab72ULL, 0x8cc702081a6439ecULL,
    0x90befffa23631e28ULL, 0xa4506cebde82bde9ULL,
    0xbef9a3f7b2c67915ULL, 0xc67178f2e372532bULL,
    0xca273eceea26619cULL, 0xd186b8c721c0c207ULL,
    0xeada7dd6cde0eb1eULL, 0xf57d4f7fee6ed178ULL,
    0x06f067aa72176fbaULL, 0x0a637dc5a2c898a6ULL,
    0x113f9804bef90daeULL, 0x1b710b35131c471bULL,
    0x28db77f523047d84ULL, 0x32caab7b40c72493ULL,
    0x3c9ebe0a15c9bebcULL, 0x431d67c49c100d4cULL,
    0x4cc5d4becb3e42b6ULL, 0x597f299cfc657e2aULL,
    0x5fcb6fab3ad6faecULL, 0x6c44198c4a475817ULL};

HD static inline u64 sha512_ch(u64 x, u64 y, u64 z) {
  return (x & y) ^ (~x & z);
}

HD static inline u64 sha512_maj(u64 x, u64 y, u64 z) {
  return (x & y) ^ (x & z) ^ (y & z);
}

HD static inline u64 sha512_big0(u64 x) {
  return rotr64(x, 28) ^ rotr64(x, 34) ^ rotr64(x, 39);
}

HD static inline u64 sha512_big1(u64 x) {
  return rotr64(x, 14) ^ rotr64(x, 18) ^ rotr64(x, 41);
}

HD static inline u64 sha512_small0(u64 x) {
  return rotr64(x, 1) ^ rotr64(x, 8) ^ (x >> 7);
}

HD static inline u64 sha512_small1(u64 x) {
  return rotr64(x, 19) ^ rotr64(x, 61) ^ (x >> 6);
}

HD static void sha512_compress(u64 state[8], const u8 block[128]) {
  u64 w[80];
  for (int i = 0; i < 16; ++i) {
    w[i] = load64_be(block + 8 * i);
  }
  for (int i = 16; i < 80; ++i) {
    w[i] = sha512_small1(w[i - 2]) + w[i - 7] + sha512_small0(w[i - 15]) + w[i - 16];
  }

  u64 a = state[0];
  u64 b = state[1];
  u64 c = state[2];
  u64 d = state[3];
  u64 e = state[4];
  u64 f = state[5];
  u64 g = state[6];
  u64 h = state[7];

  for (int i = 0; i < 80; ++i) {
    const u64 t1 = h + sha512_big1(e) + sha512_ch(e, f, g) + kSha512K[i] + w[i];
    const u64 t2 = sha512_big0(a) + sha512_maj(a, b, c);
    h = g;
    g = f;
    f = e;
    e = d + t1;
    d = c;
    c = b;
    b = a;
    a = t1 + t2;
  }

  state[0] += a;
  state[1] += b;
  state[2] += c;
  state[3] += d;
  state[4] += e;
  state[5] += f;
  state[6] += g;
  state[7] += h;
}

HD static void sha512_hash(const u8* msg, u64 len, u8 out[64]) {
  u64 state[8];
  for (int i = 0; i < 8; ++i) {
    state[i] = kSha512Iv[i];
  }

  u64 offset = 0;
  while (len - offset >= 128) {
    sha512_compress(state, msg + offset);
    offset += 128;
  }

  u8 block[256];
  for (int i = 0; i < 256; ++i) {
    block[i] = 0;
  }

  const u64 rem = len - offset;
  for (u64 i = 0; i < rem; ++i) {
    block[i] = msg[offset + i];
  }
  block[rem] = 0x80;

  const u64 pad_len = (rem < 112) ? 128 : 256;
  const u64 bit_len_hi = len >> 61;
  const u64 bit_len_lo = len << 3;
  store64_be(block + pad_len - 16, bit_len_hi);
  store64_be(block + pad_len - 8, bit_len_lo);

  sha512_compress(state, block);
  if (pad_len == 256) {
    sha512_compress(state, block + 128);
  }

  for (int i = 0; i < 8; ++i) {
    store64_be(out + 8 * i, state[i]);
  }
}

HD static void hmac_sha512(const u8* key, int key_len, const u8* msg, int msg_len, u8 out[64]) {
  u8 key_block[128];
  for (int i = 0; i < 128; ++i) {
    key_block[i] = 0;
  }

  if (key_len > 128) {
    sha512_hash(key, key_len, key_block);
  } else {
    for (int i = 0; i < key_len; ++i) {
      key_block[i] = key[i];
    }
  }

  u8 inner[320];
  u8 outer[192];
  for (int i = 0; i < 128; ++i) {
    inner[i] = key_block[i] ^ 0x36;
    outer[i] = key_block[i] ^ 0x5c;
  }
  for (int i = 0; i < msg_len; ++i) {
    inner[128 + i] = msg[i];
  }

  u8 inner_hash[64];
  sha512_hash(inner, 128 + msg_len, inner_hash);
  for (int i = 0; i < 64; ++i) {
    outer[128 + i] = inner_hash[i];
  }
  sha512_hash(outer, 192, out);
}

static constexpr i64 kGf0[16] = {0};
static constexpr i64 kGf1[16] = {1};
static constexpr i64 kEdD2[16] = {
    0xf159, 0x26b2, 0x9b94, 0xebd6, 0xb156, 0x8283, 0x149a, 0x00e0,
    0xd130, 0xeef3, 0x80f2, 0x198e, 0xfce7, 0x56df, 0xd9dc, 0x2406};
static constexpr i64 kEdX[16] = {
    0xd51a, 0x8f25, 0x2d60, 0xc956, 0xa7b2, 0x9525, 0xc760, 0x692c,
    0xdc5c, 0xfdd6, 0xe231, 0xc0a4, 0x53fe, 0xcd6e, 0x36d3, 0x2169};
static constexpr i64 kEdY[16] = {
    0x6658, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666,
    0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666};

HD static void set25519(gf r, const gf a) {
  for (int i = 0; i < 16; ++i) {
    r[i] = a[i];
  }
}

HD static void car25519(gf o) {
  for (int i = 0; i < 16; ++i) {
    o[i] += (1LL << 16);
    const i64 c = o[i] >> 16;
    o[(i + 1) * (i < 15)] += c - 1 + 37 * (c - 1) * (i == 15);
    o[i] -= c << 16;
  }
}

HD static void sel25519(gf p, gf q, int b) {
  const i64 c = ~(static_cast<i64>(b) - 1);
  for (int i = 0; i < 16; ++i) {
    const i64 t = c & (p[i] ^ q[i]);
    p[i] ^= t;
    q[i] ^= t;
  }
}

HD static void pack25519(u8* o, const gf n) {
  int i;
  gf m;
  gf t;
  for (i = 0; i < 16; ++i) {
    t[i] = n[i];
  }
  car25519(t);
  car25519(t);
  car25519(t);
  for (int j = 0; j < 2; ++j) {
    m[0] = t[0] - 0xffed;
    for (i = 1; i < 15; ++i) {
      m[i] = t[i] - 0xffff - ((m[i - 1] >> 16) & 1);
      m[i - 1] &= 0xffff;
    }
    m[15] = t[15] - 0x7fff - ((m[14] >> 16) & 1);
    const int b = (m[15] >> 16) & 1;
    m[14] &= 0xffff;
    sel25519(t, m, 1 - b);
  }
  for (i = 0; i < 16; ++i) {
    o[2 * i] = static_cast<u8>(t[i] & 0xff);
    o[2 * i + 1] = static_cast<u8>(t[i] >> 8);
  }
}

HD static u8 par25519(const gf a) {
  u8 d[32];
  pack25519(d, a);
  return d[0] & 1;
}

HD static void gf_add(gf o, const gf a, const gf b) {
  for (int i = 0; i < 16; ++i) {
    o[i] = a[i] + b[i];
  }
}

HD static void gf_sub(gf o, const gf a, const gf b) {
  for (int i = 0; i < 16; ++i) {
    o[i] = a[i] - b[i];
  }
}

HD static void gf_mul(gf o, const gf a, const gf b) {
  i64 t[31];
  for (int i = 0; i < 31; ++i) {
    t[i] = 0;
  }
  for (int i = 0; i < 16; ++i) {
    for (int j = 0; j < 16; ++j) {
      t[i + j] += a[i] * b[j];
    }
  }
  for (int i = 0; i < 15; ++i) {
    t[i] += 38 * t[i + 16];
  }
  for (int i = 0; i < 16; ++i) {
    o[i] = t[i];
  }
  car25519(o);
  car25519(o);
}

HD static void gf_square(gf o, const gf a) {
  gf_mul(o, a, a);
}

HD static void inv25519(gf o, const gf i) {
  gf c;
  for (int a = 0; a < 16; ++a) {
    c[a] = i[a];
  }
  for (int a = 253; a >= 0; --a) {
    gf_square(c, c);
    if (a != 2 && a != 4) {
      gf_mul(c, c, i);
    }
  }
  for (int a = 0; a < 16; ++a) {
    o[a] = c[a];
  }
}

HD static void ed_add(gf p[4], gf q[4]) {
  gf a;
  gf b;
  gf c;
  gf d;
  gf t;
  gf e;
  gf f;
  gf g;
  gf h;

  gf_sub(a, p[1], p[0]);
  gf_sub(t, q[1], q[0]);
  gf_mul(a, a, t);
  gf_add(b, p[0], p[1]);
  gf_add(t, q[0], q[1]);
  gf_mul(b, b, t);
  gf_mul(c, p[3], q[3]);
  gf_mul(c, c, kEdD2);
  gf_mul(d, p[2], q[2]);
  gf_add(d, d, d);
  gf_sub(e, b, a);
  gf_sub(f, d, c);
  gf_add(g, d, c);
  gf_add(h, b, a);

  gf_mul(p[0], e, f);
  gf_mul(p[1], h, g);
  gf_mul(p[2], g, f);
  gf_mul(p[3], e, h);
}

HD static void ed_cswap(gf p[4], gf q[4], u8 b) {
  for (int i = 0; i < 4; ++i) {
    sel25519(p[i], q[i], b);
  }
}

HD static void ed_pack(u8* r, gf p[4]) {
  gf tx;
  gf ty;
  gf zi;
  inv25519(zi, p[2]);
  gf_mul(tx, p[0], zi);
  gf_mul(ty, p[1], zi);
  pack25519(r, ty);
  r[31] ^= par25519(tx) << 7;
}

HD static void ed_scalarmult(gf p[4], gf q[4], const u8* s) {
  set25519(p[0], kGf0);
  set25519(p[1], kGf1);
  set25519(p[2], kGf1);
  set25519(p[3], kGf0);
  for (int i = 255; i >= 0; --i) {
    const u8 b = (s[i / 8] >> (i & 7)) & 1;
    ed_cswap(p, q, b);
    ed_add(q, p);
    ed_add(p, p);
    ed_cswap(p, q, b);
  }
}

HD static void ed_scalarbase(gf p[4], const u8* s) {
  gf q[4];
  set25519(q[0], kEdX);
  set25519(q[1], kEdY);
  set25519(q[2], kGf1);
  gf_mul(q[3], kEdX, kEdY);
  ed_scalarmult(p, q, s);
}

HD static void ed25519_public_from_seed(const u8 private_key[32], u8 public_key[32]) {
  u8 d[64];
  gf p[4];
  sha512_hash(private_key, 32, d);
  d[0] &= 248;
  d[31] &= 127;
  d[31] |= 64;
  ed_scalarbase(p, d);
  ed_pack(public_key, p);
}

HD static inline u64 rotl64(u64 x, int c) {
  return (x << c) | (x >> (64 - c));
}

static constexpr u64 kKeccakRoundConstants[24] = {
    0x0000000000000001ULL, 0x0000000000008082ULL,
    0x800000000000808aULL, 0x8000000080008000ULL,
    0x000000000000808bULL, 0x0000000080000001ULL,
    0x8000000080008081ULL, 0x8000000000008009ULL,
    0x000000000000008aULL, 0x0000000000000088ULL,
    0x0000000080008009ULL, 0x000000008000000aULL,
    0x000000008000808bULL, 0x800000000000008bULL,
    0x8000000000008089ULL, 0x8000000000008003ULL,
    0x8000000000008002ULL, 0x8000000000000080ULL,
    0x000000000000800aULL, 0x800000008000000aULL,
    0x8000000080008081ULL, 0x8000000000008080ULL,
    0x0000000080000001ULL, 0x8000000080008008ULL};

static constexpr int kKeccakRho[24] = {
    1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14,
    27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20, 44};

static constexpr int kKeccakPi[24] = {
    10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4,
    15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1};

HD static void keccakf(u64 st[25]) {
  for (int round = 0; round < 24; ++round) {
    u64 bc[5];
    for (int i = 0; i < 5; ++i) {
      bc[i] = st[i] ^ st[i + 5] ^ st[i + 10] ^ st[i + 15] ^ st[i + 20];
    }
    for (int i = 0; i < 5; ++i) {
      const u64 t = bc[(i + 4) % 5] ^ rotl64(bc[(i + 1) % 5], 1);
      for (int j = 0; j < 25; j += 5) {
        st[j + i] ^= t;
      }
    }

    u64 t = st[1];
    for (int i = 0; i < 24; ++i) {
      const int j = kKeccakPi[i];
      const u64 tmp = st[j];
      st[j] = rotl64(t, kKeccakRho[i]);
      t = tmp;
    }

    for (int j = 0; j < 25; j += 5) {
      for (int i = 0; i < 5; ++i) {
        bc[i] = st[j + i];
      }
      for (int i = 0; i < 5; ++i) {
        st[j + i] ^= (~bc[(i + 1) % 5]) & bc[(i + 2) % 5];
      }
    }

    st[0] ^= kKeccakRoundConstants[round];
  }
}

HD static void sha3_256_32(const u8 input[32], u8 out[32]) {
  u64 st[25];
  for (int i = 0; i < 25; ++i) {
    st[i] = 0;
  }

  for (int i = 0; i < 32; ++i) {
    st[i / 8] ^= static_cast<u64>(input[i]) << (8 * (i % 8));
  }
  st[32 / 8] ^= static_cast<u64>(0x06) << (8 * (32 % 8));
  st[(136 - 1) / 8] ^= static_cast<u64>(0x80) << (8 * ((136 - 1) % 8));
  keccakf(st);

  for (int i = 0; i < 32; ++i) {
    out[i] = static_cast<u8>((st[i / 8] >> (8 * (i % 8))) & 0xff);
  }
}

HD static u32 bech32_polymod_step(u32 chk, u8 value) {
  static constexpr u32 generator[5] = {
      0x3b6a57b2U, 0x26508e6dU, 0x1ea119faU, 0x3d4233ddU, 0x2a1462b3U};
  const u8 top = chk >> 25;
  chk = ((chk & 0x1ffffffU) << 5) ^ value;
  for (int i = 0; i < 5; ++i) {
    if ((top >> i) & 1) {
      chk ^= generator[i];
    }
  }
  return chk;
}

HD static void bech32_encode_zenon_address(const u8 core[20], char out[kAddressLength + 1]) {
  u8 data[32];
  int acc = 0;
  int bits = 0;
  int pos = 0;
  for (int i = 0; i < 20; ++i) {
    acc = (acc << 8) | core[i];
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      data[pos++] = static_cast<u8>((acc >> bits) & 31);
    }
  }

  u32 chk = 1;
  chk = bech32_polymod_step(chk, 3);   // high bits of "z"
  chk = bech32_polymod_step(chk, 0);   // HRP separator
  chk = bech32_polymod_step(chk, 26);  // low bits of "z"
  for (int i = 0; i < 32; ++i) {
    chk = bech32_polymod_step(chk, data[i]);
  }
  for (int i = 0; i < 6; ++i) {
    chk = bech32_polymod_step(chk, 0);
  }
  chk ^= 1;

  out[0] = 'z';
  out[1] = '1';
  for (int i = 0; i < 32; ++i) {
    out[2 + i] = kBech32Charset[data[i]];
  }
  for (int i = 0; i < 6; ++i) {
    const u8 v = static_cast<u8>((chk >> (5 * (5 - i))) & 31);
    out[34 + i] = kBech32Charset[v];
  }
  out[40] = '\0';
}

HD static void derive_private_key(const u8 seed[64], u64 account_index, u8 private_key[32]) {
  static constexpr u8 curve[] = {
      'e', 'd', '2', '5', '5', '1', '9', ' ', 's', 'e', 'e', 'd'};
  u8 iout[64];
  hmac_sha512(curve, 12, seed, 64, iout);

  u8 key[32];
  u8 chain[32];
  for (int i = 0; i < 32; ++i) {
    key[i] = iout[i];
    chain[i] = iout[32 + i];
  }

  const u32 segments[3] = {
      44U + 0x80000000U,
      73404U + 0x80000000U,
      static_cast<u32>(account_index) + 0x80000000U};

  for (int seg = 0; seg < 3; ++seg) {
    u8 data[37];
    data[0] = 0;
    for (int i = 0; i < 32; ++i) {
      data[1 + i] = key[i];
    }
    data[33] = static_cast<u8>((segments[seg] >> 24) & 0xff);
    data[34] = static_cast<u8>((segments[seg] >> 16) & 0xff);
    data[35] = static_cast<u8>((segments[seg] >> 8) & 0xff);
    data[36] = static_cast<u8>(segments[seg] & 0xff);
    hmac_sha512(chain, 32, data, 37, iout);
    for (int i = 0; i < 32; ++i) {
      key[i] = iout[i];
      chain[i] = iout[32 + i];
    }
  }

  for (int i = 0; i < 32; ++i) {
    private_key[i] = key[i];
  }
}

DEV static void candidate_seed_from_counter(u64 counter, u8 seed[64]) {
  u8 msg[40];
  for (int i = 0; i < 32; ++i) {
    msg[i] = d_base_seed[i];
  }
  store64_le(msg + 32, counter);
  sha512_hash(msg, 40, seed);
}

HD static void zenon_address_from_seed(const u8 seed[64], u64 account_index,
                                       u8 private_key[32], u8 public_key[32],
                                       char address[kAddressLength + 1]) {
  u8 digest[32];
  u8 core[20];
  derive_private_key(seed, account_index, private_key);
  ed25519_public_from_seed(private_key, public_key);
  sha3_256_32(public_key, digest);
  core[0] = 0;
  for (int i = 0; i < 19; ++i) {
    core[1 + i] = digest[i];
  }
  bech32_encode_zenon_address(core, address);
}

DEV static bool address_matches_suffix(const char address[kAddressLength + 1]) {
  if (d_suffix_len <= 0 || d_suffix_len > kAddressLength) {
    return false;
  }
  const int start = kAddressLength - d_suffix_len;
  for (int i = 0; i < d_suffix_len; ++i) {
    if (address[start + i] != d_suffix[i]) {
      return false;
    }
  }
  return true;
}

__global__ void search_kernel(u64 start_counter, u64 count, u64 account_index,
                              SearchResult* result) {
  const u64 idx = static_cast<u64>(blockIdx.x) * blockDim.x + threadIdx.x;
  if (idx >= count || result->found) {
    return;
  }

  const u64 counter = start_counter + idx;
  u8 seed[64];
  u8 private_key[32];
  u8 public_key[32];
  char address[kAddressLength + 1];

  candidate_seed_from_counter(counter, seed);
  zenon_address_from_seed(seed, account_index, private_key, public_key, address);

  if (address_matches_suffix(address) && atomicCAS(&result->found, 0, 1) == 0) {
    result->counter = counter;
    for (int i = 0; i < 64; ++i) {
      result->seed[i] = seed[i];
    }
    for (int i = 0; i < 32; ++i) {
      result->private_key[i] = private_key[i];
      result->public_key[i] = public_key[i];
    }
    for (int i = 0; i <= kAddressLength; ++i) {
      result->address[i] = address[i];
    }
  }
}

struct Options {
  std::string suffix;
  std::string output_file;
  std::vector<u8> base_seed;
  u64 account_index = 0;
  u64 start = 0;
  u64 max_attempts = 0;
  int blocks = 4096;
  int threads = 128;
};

static void usage(const char* argv0) {
  std::cout
      << "Usage: " << argv0 << " --suffix <text> [options]\n\n"
      << "Options:\n"
      << "  --suffix <text>          Vanity suffix matched at end of z1 address\n"
      << "  --account-index <n>      Hardened account index, default 0\n"
      << "  --blocks <n>             CUDA blocks per launch, default 4096\n"
      << "  --threads <n>            CUDA threads per block, default 128\n"
      << "  --start <n>              Starting counter, default 0\n"
      << "  --max-attempts <n>       Stop after n candidates, default unlimited\n"
      << "  --base-seed <hex>        32-byte hex base seed for reproducible search\n"
      << "  --output <file>          Append match details to file\n"
      << "  --help                   Show this help\n";
}

static u64 parse_u64(const std::string& value, const std::string& name) {
  try {
    size_t consumed = 0;
    const auto parsed = std::stoull(value, &consumed, 0);
    if (consumed != value.size()) {
      throw std::invalid_argument("trailing input");
    }
    return parsed;
  } catch (const std::exception&) {
    throw std::runtime_error("Invalid numeric value for " + name + ": " + value);
  }
}

static int hex_value(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

static std::vector<u8> parse_hex(const std::string& hex, size_t expected_bytes,
                                 const std::string& name) {
  if (hex.size() != expected_bytes * 2) {
    throw std::runtime_error(name + " must be exactly " +
                             std::to_string(expected_bytes) + " bytes of hex");
  }
  std::vector<u8> out(expected_bytes);
  for (size_t i = 0; i < expected_bytes; ++i) {
    const int hi = hex_value(hex[2 * i]);
    const int lo = hex_value(hex[2 * i + 1]);
    if (hi < 0 || lo < 0) {
      throw std::runtime_error(name + " contains non-hex characters");
    }
    out[i] = static_cast<u8>((hi << 4) | lo);
  }
  return out;
}

static std::string to_hex(const u8* data, size_t len) {
  std::ostringstream oss;
  oss << std::hex << std::setfill('0');
  for (size_t i = 0; i < len; ++i) {
    oss << std::setw(2) << static_cast<int>(data[i]);
  }
  return oss.str();
}

static bool is_bech32_char(char c) {
  for (const char* p = kBech32Charset; *p; ++p) {
    if (*p == c) return true;
  }
  return false;
}

static std::string normalize_suffix(std::string suffix) {
  std::transform(suffix.begin(), suffix.end(), suffix.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  if (suffix.empty()) {
    throw std::runtime_error("--suffix is required");
  }
  if (suffix.size() > kAddressLength) {
    throw std::runtime_error("--suffix cannot be longer than a Zenon address");
  }
  for (char c : suffix) {
    if (!is_bech32_char(c)) {
      throw std::runtime_error(
          "Invalid suffix character '" + std::string(1, c) +
          "'. Bech32 excludes 1, b, i, and o.");
    }
  }
  return suffix;
}

static Options parse_args(int argc, char** argv) {
  Options opts;
  for (int i = 1; i < argc; ++i) {
    const std::string arg = argv[i];
    auto require_value = [&](const std::string& name) -> std::string {
      if (i + 1 >= argc) {
        throw std::runtime_error(name + " requires a value");
      }
      return argv[++i];
    };

    if (arg == "--help" || arg == "-h") {
      usage(argv[0]);
      std::exit(0);
    } else if (arg == "--suffix" || arg == "-s") {
      opts.suffix = require_value(arg);
    } else if (arg == "--account-index") {
      opts.account_index = parse_u64(require_value(arg), arg);
    } else if (arg == "--blocks") {
      opts.blocks = static_cast<int>(parse_u64(require_value(arg), arg));
    } else if (arg == "--threads") {
      opts.threads = static_cast<int>(parse_u64(require_value(arg), arg));
    } else if (arg == "--start") {
      opts.start = parse_u64(require_value(arg), arg);
    } else if (arg == "--max-attempts") {
      opts.max_attempts = parse_u64(require_value(arg), arg);
    } else if (arg == "--base-seed") {
      opts.base_seed = parse_hex(require_value(arg), 32, "--base-seed");
    } else if (arg == "--output" || arg == "-o") {
      opts.output_file = require_value(arg);
    } else {
      throw std::runtime_error("Unknown option: " + arg);
    }
  }

  opts.suffix = normalize_suffix(opts.suffix);
  if (opts.account_index > 0x7fffffffULL) {
    throw std::runtime_error("--account-index must be <= 2147483647");
  }
  if (opts.blocks < 1 || opts.threads < 1 || opts.threads > 1024) {
    throw std::runtime_error("--blocks must be >= 1 and --threads must be 1..1024");
  }
  if (opts.base_seed.empty()) {
    opts.base_seed.resize(32);
    std::random_device rd;
    for (auto& b : opts.base_seed) {
      b = static_cast<u8>(rd() & 0xff);
    }
  }
  return opts;
}

static std::string format_result(const SearchResult& result,
                                 const std::vector<u8>& base_seed,
                                 u64 account_index, u64 checked,
                                 double seconds) {
  std::ostringstream oss;
  oss << "address: " << result.address << "\n";
  oss << "seed_hex: " << to_hex(result.seed, 64) << "\n";
  oss << "private_key_hex: " << to_hex(result.private_key, 32) << "\n";
  oss << "public_key_hex: " << to_hex(result.public_key, 32) << "\n";
  oss << "derivation_path: m/44'/73404'/" << account_index << "'\n";
  oss << "counter: " << result.counter << "\n";
  oss << "base_seed_hex: " << to_hex(base_seed.data(), base_seed.size()) << "\n";
  oss << "checked: " << checked << "\n";
  oss << "elapsed_seconds: " << std::fixed << std::setprecision(3) << seconds << "\n";
  if (seconds > 0) {
    oss << "rate: " << std::fixed << std::setprecision(2)
        << (static_cast<double>(checked) / seconds) << " seeds/sec\n";
  }
  return oss.str();
}

int main(int argc, char** argv) {
  try {
    Options opts = parse_args(argc, argv);

    int device = 0;
    CUDA_CHECK(cudaGetDevice(&device));
    cudaDeviceProp prop{};
    CUDA_CHECK(cudaGetDeviceProperties(&prop, device));

    std::cout << "GPU: " << prop.name << "\n";
    std::cout << "suffix: " << opts.suffix << "\n";
    std::cout << "account path: m/44'/73404'/" << opts.account_index << "'\n";
    std::cout << "base_seed_hex: " << to_hex(opts.base_seed.data(), opts.base_seed.size()) << "\n";
    std::cout << "launch: " << opts.blocks << " blocks x " << opts.threads << " threads\n";
    std::cout << "expected average attempts: 32^" << opts.suffix.size() << "\n\n";

    CUDA_CHECK(cudaMemcpyToSymbol(d_base_seed, opts.base_seed.data(), 32));
    char suffix_buf[41] = {0};
    std::memcpy(suffix_buf, opts.suffix.data(), opts.suffix.size());
    const int suffix_len = static_cast<int>(opts.suffix.size());
    CUDA_CHECK(cudaMemcpyToSymbol(d_suffix, suffix_buf, sizeof(suffix_buf)));
    CUDA_CHECK(cudaMemcpyToSymbol(d_suffix_len, &suffix_len, sizeof(suffix_len)));

    SearchResult* d_result = nullptr;
    CUDA_CHECK(cudaMalloc(&d_result, sizeof(SearchResult)));
    CUDA_CHECK(cudaMemset(d_result, 0, sizeof(SearchResult)));

    const u64 configured_batch = static_cast<u64>(opts.blocks) * opts.threads;
    u64 checked = 0;
    u64 counter = opts.start;
    SearchResult host_result{};

    const auto start_time = std::chrono::steady_clock::now();
    auto last_report = start_time;

    while (true) {
      u64 count = configured_batch;
      if (opts.max_attempts != 0) {
        const u64 remaining = opts.max_attempts > checked ? opts.max_attempts - checked : 0;
        if (remaining == 0) {
          break;
        }
        count = std::min(count, remaining);
      }

      const int launch_blocks = static_cast<int>((count + opts.threads - 1) / opts.threads);
      search_kernel<<<launch_blocks, opts.threads>>>(counter, count, opts.account_index, d_result);
      CUDA_CHECK(cudaGetLastError());
      CUDA_CHECK(cudaDeviceSynchronize());

      checked += count;
      counter += count;

      CUDA_CHECK(cudaMemcpy(&host_result, d_result, sizeof(SearchResult), cudaMemcpyDeviceToHost));
      if (host_result.found) {
        break;
      }

      const auto now = std::chrono::steady_clock::now();
      const double since_report =
          std::chrono::duration<double>(now - last_report).count();
      if (since_report >= 2.0) {
        const double elapsed = std::chrono::duration<double>(now - start_time).count();
        const double rate = elapsed > 0 ? static_cast<double>(checked) / elapsed : 0.0;
        std::cout << "checked " << checked << " | "
                  << std::fixed << std::setprecision(2) << rate
                  << " seeds/sec\r" << std::flush;
        last_report = now;
      }
    }

    const auto end_time = std::chrono::steady_clock::now();
    const double elapsed = std::chrono::duration<double>(end_time - start_time).count();
    std::cout << "\n";

    if (!host_result.found) {
      std::cout << "No match found after " << checked << " attempts.\n";
      CUDA_CHECK(cudaFree(d_result));
      return 2;
    }

    const std::string formatted =
        format_result(host_result, opts.base_seed, opts.account_index, checked, elapsed);
    std::cout << "Found match\n" << formatted;

    if (!opts.output_file.empty()) {
      std::ofstream out(opts.output_file, std::ios::app);
      if (!out) {
        throw std::runtime_error("Unable to open output file: " + opts.output_file);
      }
      out << "Found match\n" << formatted << "\n";
      std::cout << "saved_to: " << opts.output_file << "\n";
    }

    CUDA_CHECK(cudaFree(d_result));
    return 0;
  } catch (const std::exception& e) {
    std::cerr << "error: " << e.what() << "\n\n";
    usage(argv[0]);
    return 1;
  }
}

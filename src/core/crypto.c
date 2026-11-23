#include "core/crypto.h"
#include <string.h>
#include <stdio.h>

/* --- CRC32 Implementation (IEEE 802.3 standard polynomial 0xEDB88320) --- */

static uint32_t crc32_for_byte(uint32_t r) {
    for (int j = 0; j < 8; ++j) {
        r = (r & 1u) ? (0xEDB88320u ^ (r >> 1)) : (r >> 1);
    }
    return r;
}

uint32_t recon_crc32(const uint8_t *data, size_t len) {
    static uint32_t table[256];
    static int table_initialized = 0;

    if (!table_initialized) {
        for (uint32_t i = 0; i < 256; ++i) {
            table[i] = crc32_for_byte(i);
        }
        table_initialized = 1;
    }

    uint32_t crc = 0xFFFFFFFFu;
    for (size_t i = 0; i < len; ++i) {
        uint8_t table_idx = (uint8_t)((crc ^ data[i]) & 0xFFu);
        crc = table[table_idx] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFFu;
}

/* --- SHA-256 Implementation (FIPS 180-4) --- */

static inline uint32_t rotr32(uint32_t x, uint32_t n) {
    return (x >> n) | (x << (32u - n));
}

#define CH(x, y, z)  (((x) & (y)) ^ (~(x) & (z)))
#define MAJ(x, y, z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define EP0(x)       (rotr32((x), 2) ^ rotr32((x), 13) ^ rotr32((x), 22))
#define EP1(x)       (rotr32((x), 6) ^ rotr32((x), 11) ^ rotr32((x), 25))
#define SIG0(x)      (rotr32((x), 7) ^ rotr32((x), 18) ^ ((x) >> 3))
#define SIG1(x)      (rotr32((x), 17) ^ rotr32((x), 19) ^ ((x) >> 10))

static const uint32_t K[64] = {
    0x428A2F98u, 0x71374491u, 0xB5C0FBCFu, 0xE9B5DBA5u,
    0x3956C25Bu, 0x59F111F1u, 0x923F82A4u, 0xAB1C5ED5u,
    0xD807AA98u, 0x12835B01u, 0x243185BEu, 0x550C7DC3u,
    0x72BE5D74u, 0x80DEB1FEu, 0x9BDC06A7u, 0xC19BF174u,
    0xE49B69C1u, 0xEFBE4786u, 0x0FC19DC6u, 0x240CA1CCu,
    0x2DE92C6Fu, 0x4A7484AAu, 0x5CB0A9DCu, 0x76F988DAu,
    0x983E5152u, 0xA831C66Du, 0xB00327C8u, 0xBF597FC7u,
    0xC6E00BF3u, 0xD5A79147u, 0x06CA6351u, 0x14292967u,
    0x27B70A85u, 0x2E1B2138u, 0x4D2C6DFCu, 0x53380D13u,
    0x650A7354u, 0x766A0ABBu, 0x81C2C92Eu, 0x92722C85u,
    0xA2BFE8A1u, 0xA81A664Bu, 0xC24B8B70u, 0xC76C51A3u,
    0xD192E819u, 0xD6990624u, 0xF40E3585u, 0x106AA070u,
    0x19A4C116u, 0x1E376C08u, 0x2748774Cu, 0x34B0BCB5u,
    0x391C0CB3u, 0x4ED8AA4Au, 0x5B9CCA4Fu, 0x682E6FF3u,
    0x748F82EEu, 0x78A5636Fu, 0x84C87814u, 0x8CC70208u,
    0x90BEFFFAu, 0xA4506CEBu, 0xBEF9A3F7u, 0xC67178F2u
};

static void sha256_transform(ReconSha256Context *ctx, const uint8_t block[64]) {
    uint32_t w[64];
    for (size_t t = 0; t < 16; ++t) {
        w[t] = ((uint32_t)block[t * 4] << 24) |
               ((uint32_t)block[t * 4 + 1] << 16) |
               ((uint32_t)block[t * 4 + 2] << 8) |
               ((uint32_t)block[t * 4 + 3]);
    }
    for (size_t t = 16; t < 64; ++t) {
        w[t] = SIG1(w[t - 2]) + w[t - 7] + SIG0(w[t - 15]) + w[t - 16];
    }

    uint32_t a = ctx->state[0];
    uint32_t b = ctx->state[1];
    uint32_t c = ctx->state[2];
    uint32_t d = ctx->state[3];
    uint32_t e = ctx->state[4];
    uint32_t f = ctx->state[5];
    uint32_t g = ctx->state[6];
    uint32_t h = ctx->state[7];

    for (size_t t = 0; t < 64; ++t) {
        uint32_t t1 = h + EP1(e) + CH(e, f, g) + K[t] + w[t];
        uint32_t t2 = EP0(a) + MAJ(a, b, c);
        h = g;
        g = f;
        f = e;
        e = d + t1;
        d = c;
        c = b;
        b = a;
        a = t1 + t2;
    }

    ctx->state[0] += a;
    ctx->state[1] += b;
    ctx->state[2] += c;
    ctx->state[3] += d;
    ctx->state[4] += e;
    ctx->state[5] += f;
    ctx->state[6] += g;
    ctx->state[7] += h;
}

void recon_sha256_init(ReconSha256Context *ctx) {
    ctx->count = 0;
    ctx->state[0] = 0x6A09E667u;
    ctx->state[1] = 0xBB67AE85u;
    ctx->state[2] = 0x3C6EF372u;
    ctx->state[3] = 0xA54FF53Au;
    ctx->state[4] = 0x510E527Fu;
    ctx->state[5] = 0x9B05688Cu;
    ctx->state[6] = 0x1F83D9ABu;
    ctx->state[7] = 0x5BE0CD19u;
}

void recon_sha256_update(ReconSha256Context *ctx, const uint8_t *data, size_t len) {
    size_t buffer_index = (size_t)((ctx->count >> 3) & 0x3Fu);
    ctx->count += (uint64_t)len << 3;

    size_t part_len = 64u - buffer_index;
    size_t i = 0;

    if (len >= part_len) {
        memcpy(&ctx->buffer[buffer_index], data, part_len);
        sha256_transform(ctx, ctx->buffer);
        for (i = part_len; i + 63u < len; i += 64u) {
            sha256_transform(ctx, &data[i]);
        }
        buffer_index = 0;
    }

    if (i < len) {
        memcpy(&ctx->buffer[buffer_index], &data[i], len - i);
    }
}

void recon_sha256_final(ReconSha256Context *ctx, uint8_t digest[32]) {
    uint64_t total_bits = ctx->count;
    uint8_t count_bytes[8];
    for (size_t i = 0; i < 8; ++i) {
        count_bytes[i] = (uint8_t)((total_bits >> ((7u - i) * 8u)) & 0xFFu);
    }

    size_t pad_len = (size_t)((total_bits >> 3) & 0x3Fu);
    size_t space = (pad_len < 56u) ? (56u - pad_len) : (120u - pad_len);
    uint8_t padding[120];
    memset(padding, 0, sizeof(padding));
    padding[0] = 0x80u;

    recon_sha256_update(ctx, padding, space);
    recon_sha256_update(ctx, count_bytes, 8);

    for (size_t i = 0; i < 8; ++i) {
        digest[i * 4] = (uint8_t)((ctx->state[i] >> 24) & 0xFFu);
        digest[i * 4 + 1] = (uint8_t)((ctx->state[i] >> 16) & 0xFFu);
        digest[i * 4 + 2] = (uint8_t)((ctx->state[i] >> 8) & 0xFFu);
        digest[i * 4 + 3] = (uint8_t)(ctx->state[i] & 0xFFu);
    }
}

void recon_sha256(const uint8_t *data, size_t len, uint8_t digest[32]) {
    ReconSha256Context ctx;
    recon_sha256_init(&ctx);
    recon_sha256_update(&ctx, data, len);
    recon_sha256_final(&ctx, digest);
}

void recon_sha256_to_hex(const uint8_t digest[32], char hex_out[65]) {
    static const char hex_chars[] = "0123456789abcdef";
    for (size_t i = 0; i < 32; ++i) {
        hex_out[i * 2] = hex_chars[(digest[i] >> 4) & 0x0Fu];
        hex_out[i * 2 + 1] = hex_chars[digest[i] & 0x0Fu];
    }
    hex_out[64] = '\0';
}

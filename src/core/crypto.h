#ifndef RECON_CRYPTO_H
#define RECON_CRYPTO_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * IEEE 802.3 32-bit Cyclic Redundancy Check (CRC32).
 */
uint32_t recon_crc32(const uint8_t *data, size_t len);

/*
 * FIPS 180-4 SHA-256 cryptographic hash function.
 */
typedef struct {
    uint32_t state[8];
    uint64_t count;
    uint8_t buffer[64];
} ReconSha256Context;

void recon_sha256_init(ReconSha256Context *ctx);
void recon_sha256_update(ReconSha256Context *ctx, const uint8_t *data, size_t len);
void recon_sha256_final(ReconSha256Context *ctx, uint8_t digest[32]);
void recon_sha256(const uint8_t *data, size_t len, uint8_t digest[32]);

/*
 * Formats a 32-byte binary digest into a 64-character lowercase hex string.
 * hex_out must have space for at least 65 bytes (including null terminator).
 */
void recon_sha256_to_hex(const uint8_t digest[32], char hex_out[65]);

#ifdef __cplusplus
}
#endif

#endif /* RECON_CRYPTO_H */

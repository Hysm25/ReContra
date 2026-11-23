#ifndef RECON_PALETTE_H
#define RECON_PALETTE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Authentic 2C02 NTSC master palette (64 colors) mapped to 32-bit RGBA8888.
 */
extern const uint32_t NES_SYSTEM_PALETTE_RGBA[64];

/*
 * Returns 32-bit RGBA color for an authentic NES palette index (0x00..0x3F).
 */
static inline uint32_t nes_color_to_rgba(uint8_t nes_color) {
    return NES_SYSTEM_PALETTE_RGBA[nes_color & 0x3Fu];
}

#ifdef __cplusplus
}
#endif

#endif /* RECON_PALETTE_H */

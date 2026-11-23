#ifndef RECON_PPU_H
#define RECON_PPU_H

#include "core/types.h"
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PPU_MAX_SPRITES_PER_SCANLINE 8u
#define PPU_OAM_SPRITE_COUNT         64u
#define PPU_AUTHENTIC_CYCLIC_SHIFT   0x4Cu

/*
 * PPUCTRL ($2000) Bit Flags
 */
#define PPUCTRL_NAMETABLE_MASK       0x03u
#define PPUCTRL_VRAM_INCREMENT_32    0x04u
#define PPUCTRL_SPRITE_TABLE_1000    0x08u
#define PPUCTRL_BG_TABLE_1000        0x10u
#define PPUCTRL_SPRITE_8X16          0x20u
#define PPUCTRL_SLAVE_MODE           0x40u
#define PPUCTRL_NMI_ENABLE           0x80u

/*
 * PPUMASK ($2001) Bit Flags
 */
#define PPUMASK_GRAYSCALE            0x01u
#define PPUMASK_SHOW_BG_LEFT8        0x02u
#define PPUMASK_SHOW_SPRITES_LEFT8   0x04u
#define PPUMASK_SHOW_BG              0x08u
#define PPUMASK_SHOW_SPRITES         0x10u
#define PPUMASK_EMPHASIZE_RED        0x20u
#define PPUMASK_EMPHASIZE_GREEN      0x40u
#define PPUMASK_EMPHASIZE_BLUE       0x80u

/*
 * Mirroring Types
 */
typedef enum {
    PPU_MIRROR_VERTICAL   = 0, /* Vertical mirroring: Horizontal scrolling (NT0/NT2, NT1/NT3) */
    PPU_MIRROR_HORIZONTAL = 1, /* Horizontal mirroring: Vertical scrolling (NT0/NT1, NT2/NT3) */
    PPU_MIRROR_SINGLE_0   = 2, /* Single screen Nametable 0 ($2000) */
    PPU_MIRROR_SINGLE_1   = 3  /* Single screen Nametable 1 ($2400) */
} PpuMirroringMode;

/*
 * 2C02 PPU State Structure
 */
typedef struct {
    uint8_t vram[PPU_VRAM_SIZE];                     /* 16KB VRAM address space */
    uint8_t oam[OAM_BUFFER_SIZE];                    /* 256-byte OAM memory (64 sprites) */
    uint8_t palette_ram[PALETTE_RAM_SIZE];           /* 32-byte internal Palette RAM ($3F00-$3F1F) */
    uint32_t framebuffer[DISPLAY_WIDTH * DISPLAY_HEIGHT]; /* 256x240 32-bit RGBA8888 output */

    /* Scroll Registers */
    uint16_t scroll_x;                               /* Total horizontal scroll (0..511) */
    uint16_t scroll_y;                               /* Total vertical scroll (0..479) */

    /* Control Registers */
    uint8_t ctrl;                                    /* PPUCTRL ($2000) */
    uint8_t mask;                                    /* PPUMASK ($2001) */
    uint8_t status;                                  /* PPUSTATUS ($2002) */

    /* Configuration & Emulation Flags */
    PpuMirroringMode mirroring;                      /* Mirroring configuration */
    bool flicker_free_sprites;                       /* Toggle: false = 8 sprites/scanline, true = unlimited */
    uint8_t oam_shift_offset;                        /* Cyclic OAM priority shift offset ($4C per frame) */
    uint32_t frame_count;                            /* Rendered frame counter */
} Ppu2C02;

/*
 * Initialize PPU state to authentic power-on defaults.
 */
void ppu_init(Ppu2C02 *ppu);

/*
 * Reset PPU state.
 */
void ppu_reset(Ppu2C02 *ppu);

/*
 * Set PPU mirroring mode.
 */
void ppu_set_mirroring(Ppu2C02 *ppu, PpuMirroringMode mode);

/*
 * Write byte to PPU VRAM ($0000-$3FFF), automatically handling palette mirroring.
 */
void ppu_write_vram(Ppu2C02 *ppu, uint16_t addr, uint8_t val);

/*
 * Read byte from PPU VRAM ($0000-$3FFF).
 */
uint8_t ppu_read_vram(const Ppu2C02 *ppu, uint16_t addr);

/*
 * Copy 256-byte buffer into OAM ($0200-$02FF DMA equivalent).
 */
void ppu_write_oam_buffer(Ppu2C02 *ppu, const uint8_t *oam_src);

/*
 * Load internal Palette RAM from a 32-byte array.
 */
void ppu_load_palettes(Ppu2C02 *ppu, const uint8_t palette_src[PALETTE_RAM_SIZE]);

/*
 * Decodes 2-bit color index (0..3) of an 8x8 tile at pixel coordinate (u, v) [0..7, 0..7].
 */
uint8_t ppu_decode_tile_pixel(const uint8_t *pattern_table_base, uint8_t tile_idx, int u, int v);

/*
 * Resolves mirrored Nametable address for coordinates (tx, ty) [0..63, 0..59].
 */
uint16_t ppu_get_nametable_address(const Ppu2C02 *ppu, uint16_t tx, uint16_t ty);

/*
 * Renders a single scanline (0..239) into the PPU framebuffer.
 */
void ppu_render_scanline(Ppu2C02 *ppu, int scanline);

/*
 * Renders a complete 256x240 frame (all 240 scanlines) into the PPU framebuffer.
 * Advances authentic cyclic OAM priority shift offset ($4C).
 */
void ppu_render_frame(Ppu2C02 *ppu);

#ifdef __cplusplus
}
#endif

#endif /* RECON_PPU_H */

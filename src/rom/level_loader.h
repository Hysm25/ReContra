#ifndef RECON_LEVEL_LOADER_H
#define RECON_LEVEL_LOADER_H

#include "rom/rom_loader.h"
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LEVEL_COUNT                    8u
#define LEVEL_HEADER_BANK              2u
#define LEVEL_HEADERS_CPU_ADDR         0xB319u
#define LEVEL_HEADER_SIZE              32u

#define GAME_PALETTE_PTR_TBL_ADDR      0xD225u
#define GAME_PALETTES_DEFAULT_ADDR     0xD227u
#define GAME_PALETTE_COUNT             110u
#define LVL_ALT_COLLISION_PAL_TBL_ADDR 0xD1ADu

typedef struct {
    uint8_t level_index;
    uint8_t location_type;   /* 0 = Outdoor, 1 = Indoor base */
    uint8_t scrolling_type;  /* 0 = Horizontal, 1 = Vertical (Stage 3) */
    uint16_t screen_ptr;     /* Bank 2 CPU address for screen supertile table */
    uint16_t supertile_ptr;  /* Bank 3 CPU address for 4x4 tile makeup */
    uint16_t palette_ptr;    /* Bank 3 CPU address for supertile palette attributes */
    uint8_t alt_graphics_pos;
    uint8_t collision_limits[3];
    uint8_t palette_cycle_indexes[4];
    uint8_t bg_palette_indexes[4];
    uint8_t sprite_palette_indexes[4];
    uint8_t stop_scrolling_pos;
    uint8_t bullet_solid_collision;
} LevelHeader;

typedef struct {
    uint8_t tiles[4][4]; /* 4 rows of 4 pattern tile indices (16 bytes) */
} SupertileDef;

/*
 * Reads the 32-byte Level Header dynamically from Bank 2 ($B319 + level * 32).
 */
ReconResult level_load_header(const RomData *rom, uint8_t level, LevelHeader *out_header);

/*
 * Reads a single 3-color palette entry (0..109) from Bank 7 game_palettes.
 */
ReconResult level_get_palette_colors(const RomData *rom, uint8_t palette_idx, uint8_t out_colors[3]);

/*
 * Populates PALETTE_CPU_BUFFER (32 bytes: 16 background + 16 sprite NES colors)
 * for the given level matching NES Contra routine `load_palettes_color_to_cpu`.
 */
ReconResult level_load_palettes(const RomData *rom, uint8_t level, uint8_t palette_buffer[PALETTE_RAM_SIZE]);

/*
 * Reads a 4x4 supertile definition (16 bytes) from Bank 3 at supertile_ptr.
 */
ReconResult level_read_supertile(const RomData *rom, uint16_t supertile_base_ptr, uint8_t supertile_id, SupertileDef *out_supertile);

#ifdef __cplusplus
}
#endif

#endif /* RECON_LEVEL_LOADER_H */

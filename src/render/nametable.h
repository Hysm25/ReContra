#ifndef RECON_NAMETABLE_H
#define RECON_NAMETABLE_H

#include "core/types.h"
#include "rom/rom_loader.h"
#include "rom/level_loader.h"
#include "render/ppu.h"
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SUPERTILE_WIDTH_TILES   4u
#define SUPERTILE_HEIGHT_TILES  4u
#define SUPERTILES_PER_ROW      8u
#define HORIZONTAL_SUPERTILE_ROWS 7u
#define VERTICAL_SUPERTILE_ROWS   8u

/*
 * Unpacks an 8x7 supertile screen into the specified Nametable (0 or 1: $2000 or $2400)
 * for horizontal scrolling stages.
 */
ReconResult nametable_unpack_screen_horizontal(
    Ppu2C02 *ppu,
    uint8_t nametable_idx,
    const RomData *rom,
    const LevelHeader *hdr,
    uint8_t screen_index
);

/*
 * Unpacks an 8x8 supertile screen into the specified Nametable for vertical scrolling stages.
 */
ReconResult nametable_unpack_screen_vertical(
    Ppu2C02 *ppu,
    uint8_t nametable_idx,
    const RomData *rom,
    const LevelHeader *hdr,
    uint8_t screen_index
);

/*
 * Unpacks a 3D indoor perspective corridor nametable for base stages.
 */
ReconResult nametable_unpack_corridor_perspective(
    Ppu2C02 *ppu,
    uint8_t nametable_idx,
    uint8_t room_depth_step
);

#ifdef __cplusplus
}
#endif

#endif /* RECON_NAMETABLE_H */

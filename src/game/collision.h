#ifndef RECON_COLLISION_H
#define RECON_COLLISION_H

#include "core/types.h"
#include "rom/rom_loader.h"
#include "rom/level_loader.h"
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BG_COLLISION_DATA_SIZE 128u
#define COLLISION_ROWS_PER_SCREEN 14u
#define COLLISION_COLS_PER_SCREEN 16u
#define COLLISION_BYTES_PER_ROW    4u

/*
 * Collision Point Codes (2 bits per 16x16 block)
 */
#define COLLISION_CODE_EMPTY 0x00u
#define COLLISION_CODE_FLOOR 0x01u
#define COLLISION_CODE_WATER 0x02u
#define COLLISION_CODE_SOLID 0x03u

typedef struct {
    uint8_t data[BG_COLLISION_DATA_SIZE];
    uint8_t screen_indices[2];
    bool screen_loaded[2];
} CollisionGrid;

void collision_grid_init(CollisionGrid *grid);

ReconResult collision_grid_unpack_screen(CollisionGrid *grid, const RomData *rom,
                                         const LevelHeader *header, uint8_t screen_index,
                                         uint8_t nametable_index);

uint8_t collision_grid_get_code(const CollisionGrid *grid, uint16_t world_x, uint16_t world_y);

bool collision_grid_can_drop_down(const CollisionGrid *grid, uint16_t world_x, uint16_t world_y);

#ifdef __cplusplus
}
#endif

#endif /* RECON_COLLISION_H */

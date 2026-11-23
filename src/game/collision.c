#include "game/collision.h"
#include <string.h>

static inline uint8_t determine_tile_code(uint8_t tile_idx, const uint8_t limits[3]) {
    if (tile_idx == 0u) {
        return COLLISION_CODE_EMPTY;
    }
    if (tile_idx < limits[0]) {
        return COLLISION_CODE_FLOOR;
    }
    if (tile_idx < limits[1]) {
        return COLLISION_CODE_EMPTY;
    }
    if (tile_idx < limits[2]) {
        return COLLISION_CODE_WATER;
    }
    return COLLISION_CODE_SOLID;
}

void collision_grid_init(CollisionGrid *grid) {
    if (!grid) return;
    memset(grid, 0, sizeof(CollisionGrid));
}

ReconResult collision_grid_unpack_screen(CollisionGrid *grid, const RomData *rom,
                                         const LevelHeader *header, uint8_t screen_index,
                                         uint8_t nametable_index) {
    if (!grid || !rom || !header) {
        return RECON_ERR_NULL_PTR;
    }
    if (nametable_index > 1u) {
        return RECON_ERR_OUT_OF_BOUNDS;
    }

    uint8_t supertiles[64];
    ReconResult res = level_decompress_screen_supertiles(rom, header, screen_index, supertiles, sizeof(supertiles));
    if (res != RECON_OK) {
        return res;
    }

    size_t base_grid_offset = (nametable_index == 1u) ? 0x40u : 0x00u;
    memset(&grid->data[base_grid_offset], 0, 56);

    /*
     * 7 supertile rows x 8 supertile cols = 56 supertiles per screen.
     * Each supertile produces 2x2 collision points (14 collision rows x 16 collision cols).
     */
    for (uint8_t sr = 0; sr < 7u; ++sr) {
        for (uint8_t sc = 0; sc < 8u; ++sc) {
            uint8_t supertile_id = supertiles[sr * 8u + sc];

            SupertileDef st_def;
            res = level_read_supertile(rom, header->supertile_ptr, supertile_id, &st_def);
            if (res != RECON_OK) return res;

            /* 4 quadrants: (0,0), (0,2), (2,0), (2,2) */
            uint8_t q0 = determine_tile_code(st_def.tiles[0][0], header->collision_limits);
            uint8_t q1 = determine_tile_code(st_def.tiles[0][2], header->collision_limits);
            uint8_t q2 = determine_tile_code(st_def.tiles[2][0], header->collision_limits);
            uint8_t q3 = determine_tile_code(st_def.tiles[2][2], header->collision_limits);

            /* Top half of supertile: row = sr * 2 */
            uint8_t r_top = (uint8_t)(sr * 2u);
            uint8_t c_left = (uint8_t)(sc * 2u);
            uint8_t c_right = (uint8_t)(c_left + 1u);

            size_t byte_idx_top = base_grid_offset + (size_t)r_top * COLLISION_BYTES_PER_ROW + (size_t)(c_left / 4u);
            uint8_t shift_q0 = (uint8_t)((3u - (c_left % 4u)) * 2u);
            uint8_t shift_q1 = (uint8_t)((3u - (c_right % 4u)) * 2u);
            grid->data[byte_idx_top] = (uint8_t)(grid->data[byte_idx_top] | (uint8_t)(q0 << shift_q0));
            grid->data[byte_idx_top] = (uint8_t)(grid->data[byte_idx_top] | (uint8_t)(q1 << shift_q1));

            /* Bottom half of supertile: row = sr * 2 + 1 */
            uint8_t r_bot = (uint8_t)(r_top + 1u);
            size_t byte_idx_bot = base_grid_offset + (size_t)r_bot * COLLISION_BYTES_PER_ROW + (size_t)(c_left / 4u);
            grid->data[byte_idx_bot] = (uint8_t)(grid->data[byte_idx_bot] | (uint8_t)(q2 << shift_q0));
            grid->data[byte_idx_bot] = (uint8_t)(grid->data[byte_idx_bot] | (uint8_t)(q3 << shift_q1));
        }
    }

    grid->screen_indices[nametable_index] = screen_index;
    grid->screen_loaded[nametable_index] = true;

    return RECON_OK;
}

uint8_t collision_grid_get_code(const CollisionGrid *grid, uint16_t world_x, uint16_t world_y) {
    if (!grid) return COLLISION_CODE_EMPTY;

    if (world_y < 16u || world_y >= 240u) {
        return COLLISION_CODE_EMPTY;
    }

    uint8_t row = (uint8_t)((world_y - 16u) / 16u);
    if (row >= COLLISION_ROWS_PER_SCREEN) {
        return COLLISION_CODE_EMPTY;
    }

    uint16_t scroll_x = (uint16_t)(world_x % 512u);
    uint8_t nt_idx = (uint8_t)(scroll_x / 256u);
    uint8_t col_in_screen = (uint8_t)((scroll_x % 256u) / 16u);

    uint8_t target_screen = (uint8_t)(world_x / 256u);
    if (!grid->screen_loaded[nt_idx] || grid->screen_indices[nt_idx] != target_screen) {
        return COLLISION_CODE_EMPTY;
    }

    size_t base_offset = (nt_idx == 1u) ? 0x40u : 0x00u;
    size_t byte_idx = base_offset + (size_t)row * COLLISION_BYTES_PER_ROW + (size_t)(col_in_screen / 4u);
    if (byte_idx >= BG_COLLISION_DATA_SIZE) {
        return COLLISION_CODE_EMPTY;
    }

    uint8_t shift = (uint8_t)((3u - (col_in_screen % 4u)) * 2u);
    return (uint8_t)((grid->data[byte_idx] >> shift) & 0x03u);
}

bool collision_grid_can_drop_down(const CollisionGrid *grid, uint16_t world_x, uint16_t world_y) {
    if (!grid || world_y < 16u || world_y >= 240u) {
        return false;
    }

    uint8_t cur_row = (uint8_t)((world_y - 16u) / 16u);
    for (uint8_t r = (uint8_t)(cur_row + 1u); r < COLLISION_ROWS_PER_SCREEN; ++r) {
        uint16_t check_y = (uint16_t)(16u + (uint16_t)r * 16u + 8u);
        uint8_t code = collision_grid_get_code(grid, world_x, check_y);
        if (code == COLLISION_CODE_FLOOR) {
            return true;
        }
        if (code == COLLISION_CODE_SOLID) {
            return false;
        }
    }
    return false;
}

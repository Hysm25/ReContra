#include "rom/level_loader.h"
#include <string.h>

ReconResult level_load_header(const RomData *rom, uint8_t level, LevelHeader *out_header) {
    if (rom == NULL || out_header == NULL) {
        return RECON_ERR_NULL_PTR;
    }
    if (level >= LEVEL_COUNT) {
        return RECON_ERR_OUT_OF_BOUNDS;
    }

    uint16_t base_addr = (uint16_t)(LEVEL_HEADERS_CPU_ADDR + (uint16_t)(level * LEVEL_HEADER_SIZE));
    uint8_t raw[LEVEL_HEADER_SIZE];

    for (uint16_t i = 0; i < LEVEL_HEADER_SIZE; ++i) {
        ReconResult res = rom_read_prg_byte(rom, LEVEL_HEADER_BANK, (uint16_t)(base_addr + i), &raw[i]);
        if (res != RECON_OK) {
            return res;
        }
    }

    out_header->level_index = level;
    out_header->location_type = raw[0];
    out_header->scrolling_type = raw[1];
    out_header->screen_ptr = (uint16_t)(((uint16_t)raw[3] << 8) | (uint16_t)raw[2]);
    out_header->supertile_ptr = (uint16_t)(((uint16_t)raw[5] << 8) | (uint16_t)raw[4]);
    out_header->palette_ptr = (uint16_t)(((uint16_t)raw[7] << 8) | (uint16_t)raw[6]);
    out_header->alt_graphics_pos = raw[8];
    out_header->collision_limits[0] = raw[9];
    out_header->collision_limits[1] = raw[10];
    out_header->collision_limits[2] = raw[11];

    memcpy(out_header->palette_cycle_indexes, &raw[12], 4);
    memcpy(out_header->bg_palette_indexes, &raw[16], 4);
    memcpy(out_header->sprite_palette_indexes, &raw[20], 4);
    out_header->stop_scrolling_pos = raw[24];
    out_header->bullet_solid_collision = raw[25];

    return RECON_OK;
}

ReconResult level_get_palette_colors(const RomData *rom, uint8_t palette_idx, uint8_t out_colors[3]) {
    if (rom == NULL || out_colors == NULL) {
        return RECON_ERR_NULL_PTR;
    }
    if (palette_idx >= GAME_PALETTE_COUNT) {
        return RECON_ERR_OUT_OF_BOUNDS;
    }

    /* Read pointer to game_palettes from Bank 7 $D225 */
    uint16_t game_palettes_addr = 0;
    ReconResult res = rom_read_prg_word(rom, 7, GAME_PALETTE_PTR_TBL_ADDR, &game_palettes_addr);
    if (res != RECON_OK) {
        game_palettes_addr = GAME_PALETTES_DEFAULT_ADDR;
    }

    uint16_t pal_addr = (uint16_t)(game_palettes_addr + (uint16_t)(palette_idx * 3u));
    for (uint16_t i = 0; i < 3u; ++i) {
        res = rom_read_prg_byte(rom, 7, (uint16_t)(pal_addr + i), &out_colors[i]);
        if (res != RECON_OK) {
            return res;
        }
    }
    return RECON_OK;
}

ReconResult level_load_palettes(const RomData *rom, uint8_t level, uint8_t palette_buffer[PALETTE_RAM_SIZE]) {
    if (rom == NULL || palette_buffer == NULL) {
        return RECON_ERR_NULL_PTR;
    }
    LevelHeader hdr;
    ReconResult res = level_load_header(rom, level, &hdr);
    if (res != RECON_OK) {
        return res;
    }

    /*
     * Authentic NES palette setup:
     * - Universal background color: $0F (black) at indices 0, 4, 8, 12, 16, 20, 24, 28.
     * - Background palettes 0..3: 3 colors each from hdr.bg_palette_indexes[0..3]
     * - Sprite palettes 0..3: 3 colors each from hdr.sprite_palette_indexes[0..3]
     */
    for (size_t p = 0; p < 4; ++p) {
        size_t bg_base = p * 4;
        palette_buffer[bg_base] = 0x0Fu; /* NES Universal background color (Black) */
        uint8_t colors[3];
        res = level_get_palette_colors(rom, hdr.bg_palette_indexes[p], colors);
        if (res != RECON_OK) return res;
        palette_buffer[bg_base + 1] = colors[0];
        palette_buffer[bg_base + 2] = colors[1];
        palette_buffer[bg_base + 3] = colors[2];

        size_t sp_base = 16 + p * 4;
        palette_buffer[sp_base] = 0x0Fu; /* Transparent / black */
        res = level_get_palette_colors(rom, hdr.sprite_palette_indexes[p], colors);
        if (res != RECON_OK) return res;
        palette_buffer[sp_base + 1] = colors[0];
        palette_buffer[sp_base + 2] = colors[1];
        palette_buffer[sp_base + 3] = colors[2];
    }

    return RECON_OK;
}

ReconResult level_read_supertile(const RomData *rom, uint16_t supertile_base_ptr, uint8_t supertile_id, SupertileDef *out_supertile) {
    if (rom == NULL || out_supertile == NULL) {
        return RECON_ERR_NULL_PTR;
    }

    /* Each supertile is 16 bytes: 4 columns x 4 rows */
    uint16_t addr = (uint16_t)(supertile_base_ptr + (uint16_t)((uint16_t)supertile_id * 16u));
    for (size_t row = 0; row < 4; ++row) {
        for (size_t col = 0; col < 4; ++col) {
            uint16_t byte_addr = (uint16_t)(addr + (uint16_t)(row * 4 + col));
            ReconResult res = rom_read_prg_byte(rom, 3, byte_addr, &out_supertile->tiles[row][col]);
            if (res != RECON_OK) {
                return res;
            }
        }
    }

    return RECON_OK;
}

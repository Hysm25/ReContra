#include "render/nametable.h"
#include <string.h>

ReconResult nametable_unpack_screen_horizontal(
    Ppu2C02 *ppu,
    uint8_t nametable_idx,
    const RomData *rom,
    const LevelHeader *hdr,
    uint8_t screen_index
) {
    if (ppu == NULL || rom == NULL || hdr == NULL) {
        return RECON_ERR_NULL_PTR;
    }

    uint16_t nt_base = (nametable_idx == 1u) ? 0x2400u : 0x2000u;
    uint8_t supertiles[56];
    ReconResult res = level_decompress_screen_supertiles(rom, hdr, screen_index, supertiles, sizeof(supertiles));
    if (res != RECON_OK) {
        return res;
    }

    /* Clear entire 1024-byte nametable and attribute table (rows 28-29 empty) */
    for (uint16_t i = 0; i < 1024u; ++i) {
        ppu_write_vram(ppu, (uint16_t)(nt_base + i), 0x00u);
    }

    /*
     * Horizontal levels: 8 columns x 7 rows = 56 supertiles per screen.
     * Authentic NES Contra writes supertiles starting at row 0 (PPU $2000 / $2400).
     */
    for (uint16_t sr = 0; sr < HORIZONTAL_SUPERTILE_ROWS; ++sr) {
        for (uint16_t sc = 0; sc < SUPERTILES_PER_ROW; ++sc) {
            uint8_t supertile_id = supertiles[sr * SUPERTILES_PER_ROW + sc];

            SupertileDef st_def;
            res = level_read_supertile(rom, hdr->supertile_ptr, supertile_id, &st_def);
            if (res != RECON_OK) return res;

            /* Read supertile palette attribute byte from Bank 3 */
            uint8_t st_attr = 0;
            res = rom_read_prg_byte(rom, 3, (uint16_t)(hdr->palette_ptr + supertile_id), &st_attr);
            if (res != RECON_OK) return res;

            /* Write 4x4 tiles to Nametable */
            for (uint16_t r = 0; r < SUPERTILE_HEIGHT_TILES; ++r) {
                uint16_t nt_row = (uint16_t)(sr * SUPERTILE_HEIGHT_TILES + r);
                if (nt_row >= 30u) break;

                for (uint16_t c = 0; c < SUPERTILE_WIDTH_TILES; ++c) {
                    uint16_t nt_col = (uint16_t)(sc * SUPERTILE_WIDTH_TILES + c);
                    uint16_t dest_addr = (uint16_t)(nt_base + nt_row * 32u + nt_col);
                    ppu_write_vram(ppu, dest_addr, st_def.tiles[r][c]);
                }
            }

            /*
             * Populate Attribute Table ($23C0 or $27C0).
             * Each supertile spans 4x4 tiles (1 attribute byte).
             */
            if (sr < 7u) {
                uint16_t attr_addr = (uint16_t)(nt_base + 960u + sr * 8u + sc);
                ppu_write_vram(ppu, attr_addr, st_attr);
            }
        }
    }

    return RECON_OK;
}

ReconResult nametable_unpack_screen_vertical(
    Ppu2C02 *ppu,
    uint8_t nametable_idx,
    const RomData *rom,
    const LevelHeader *hdr,
    uint8_t screen_index
) {
    if (ppu == NULL || rom == NULL || hdr == NULL) {
        return RECON_ERR_NULL_PTR;
    }

    uint16_t nt_base = (nametable_idx == 1u) ? 0x2400u : 0x2000u;
    uint8_t supertiles[64];
    ReconResult res = level_decompress_screen_supertiles(rom, hdr, screen_index, supertiles, sizeof(supertiles));
    if (res != RECON_OK) {
        return res;
    }

    /* Clear entire 1024-byte nametable and attribute table */
    for (uint16_t i = 0; i < 1024u; ++i) {
        ppu_write_vram(ppu, (uint16_t)(nt_base + i), 0x00u);
    }

    /*
     * Vertical levels: 8 columns x 8 rows = 64 supertiles per screen.
     */
    for (uint16_t sr = 0; sr < VERTICAL_SUPERTILE_ROWS; ++sr) {
        for (uint16_t sc = 0; sc < SUPERTILES_PER_ROW; ++sc) {
            uint8_t supertile_id = supertiles[sr * SUPERTILES_PER_ROW + sc];

            SupertileDef st_def;
            res = level_read_supertile(rom, hdr->supertile_ptr, supertile_id, &st_def);
            if (res != RECON_OK) return res;

            uint8_t st_attr = 0;
            res = rom_read_prg_byte(rom, 3, (uint16_t)(hdr->palette_ptr + supertile_id), &st_attr);
            if (res != RECON_OK) return res;

            for (uint16_t r = 0; r < SUPERTILE_HEIGHT_TILES; ++r) {
                uint16_t nt_row = (uint16_t)(sr * SUPERTILE_HEIGHT_TILES + r);
                if (nt_row >= 30u) break;

                for (uint16_t c = 0; c < SUPERTILE_WIDTH_TILES; ++c) {
                    uint16_t nt_col = (uint16_t)(sc * SUPERTILE_WIDTH_TILES + c);
                    uint16_t dest_addr = (uint16_t)(nt_base + nt_row * 32u + nt_col);
                    ppu_write_vram(ppu, dest_addr, st_def.tiles[r][c]);
                }
            }

            if (sr < 8u) {
                uint16_t attr_addr = (uint16_t)(nt_base + 960u + sr * 8u + sc);
                ppu_write_vram(ppu, attr_addr, st_attr);
            }
        }
    }

    return RECON_OK;
}

ReconResult nametable_unpack_corridor_perspective(
    Ppu2C02 *ppu,
    uint8_t nametable_idx,
    uint8_t room_depth_step
) {
    if (ppu == NULL) {
        return RECON_ERR_NULL_PTR;
    }

    uint16_t nt_base = (nametable_idx == 1) ? 0x2400u : 0x2000u;
    (void)room_depth_step;

    /* Fill background with basic grid pattern for corridor perspective */
    for (uint16_t row = 0; row < 30u; ++row) {
        for (uint16_t col = 0; col < 32u; ++col) {
            uint16_t dest_addr = (uint16_t)(nt_base + row * 32u + col);
            uint8_t tile = 0x00u;
            if (row < 4 || row > 25) {
                tile = 0x01u; /* Ceiling / floor border */
            } else if (col < 4 || col > 27) {
                tile = 0x02u; /* Side wall border */
            }
            ppu_write_vram(ppu, dest_addr, tile);
        }
    }

    /* Set attribute table to uniform subpalette 0 */
    for (uint16_t a = 0; a < 64u; ++a) {
        ppu_write_vram(ppu, (uint16_t)(nt_base + 960u + a), 0x00u);
    }

    return RECON_OK;
}

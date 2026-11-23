#include "render/ppu.h"
#include "render/palette.h"
#include <string.h>

void ppu_init(Ppu2C02 *ppu) {
    if (ppu == NULL) return;
    memset(ppu, 0, sizeof(Ppu2C02));
    ppu_reset(ppu);
}

void ppu_reset(Ppu2C02 *ppu) {
    if (ppu == NULL) return;
    memset(ppu->vram, 0, sizeof(ppu->vram));
    memset(ppu->oam, 0, sizeof(ppu->oam));
    memset(ppu->framebuffer, 0, sizeof(ppu->framebuffer));

    /* Initialize palette RAM to default black ($0F) */
    memset(ppu->palette_ram, 0x0F, sizeof(ppu->palette_ram));

    ppu->scroll_x = 0;
    ppu->scroll_y = 0;

    /* Authentic 8-bit defaults: 8x16 sprites, BG pattern table at $1000 */
    ppu->ctrl = PPUCTRL_SPRITE_8X16 | PPUCTRL_BG_TABLE_1000;
    ppu->mask = PPUMASK_SHOW_BG | PPUMASK_SHOW_SPRITES | PPUMASK_SHOW_BG_LEFT8 | PPUMASK_SHOW_SPRITES_LEFT8;
    ppu->status = 0;

    ppu->mirroring = PPU_MIRROR_VERTICAL;
    ppu->flicker_free_sprites = true; /* Clean flicker-free rendering default */
    ppu->oam_shift_offset = 0;
    ppu->frame_count = 0;
}

void ppu_set_mirroring(Ppu2C02 *ppu, PpuMirroringMode mode) {
    if (ppu == NULL) return;
    ppu->mirroring = mode;
}

static inline uint16_t mirror_palette_addr(uint16_t addr) {
    uint16_t pal = (uint16_t)(addr & 0x001Fu);
    /* $3F10, $3F14, $3F18, $3F1C mirror $3F00, $3F04, $3F08, $3F0C */
    if (pal >= 0x10u && (pal & 0x03u) == 0) {
        pal = (uint16_t)(pal - 0x10u);
    }
    return pal;
}

void ppu_write_vram(Ppu2C02 *ppu, uint16_t addr, uint8_t val) {
    if (ppu == NULL) return;
    addr = (uint16_t)(addr & 0x3FFFu);

    if (addr >= 0x3F00u) {
        uint16_t pal_idx = mirror_palette_addr(addr);
        ppu->palette_ram[pal_idx] = val;
        ppu->vram[0x3F00u + pal_idx] = val;
        return;
    }

    if (addr >= 0x3000u && addr < 0x3F00u) {
        addr = (uint16_t)(addr - 0x1000u); /* Mirror $2000-$2EFF */
    }

    if (addr >= 0x2000u && addr < 0x3000u) {
        /* Nametable mirroring */
        uint16_t nt_offset = (uint16_t)(addr & 0x03FFu);
        uint16_t nt_index = (uint16_t)((addr >> 10) & 0x03u);

        switch (ppu->mirroring) {
            case PPU_MIRROR_VERTICAL:
                /* Vertical mirroring: NT 0 & 2 -> $2000; NT 1 & 3 -> $2400 */
                addr = (uint16_t)(0x2000u + ((nt_index & 1u) ? 0x0400u : 0u) + nt_offset);
                break;
            case PPU_MIRROR_HORIZONTAL:
                /* Horizontal mirroring: NT 0 & 1 -> $2000; NT 2 & 3 -> $2800 */
                addr = (uint16_t)(0x2000u + ((nt_index >= 2u) ? 0x0400u : 0u) + nt_offset);
                break;
            case PPU_MIRROR_SINGLE_0:
                addr = (uint16_t)(0x2000u + nt_offset);
                break;
            case PPU_MIRROR_SINGLE_1:
                addr = (uint16_t)(0x2400u + nt_offset);
                break;
        }
    }

    ppu->vram[addr] = val;
}

uint8_t ppu_read_vram(const Ppu2C02 *ppu, uint16_t addr) {
    if (ppu == NULL) return 0;
    addr = (uint16_t)(addr & 0x3FFFu);

    if (addr >= 0x3F00u) {
        uint16_t pal_idx = mirror_palette_addr(addr);
        return ppu->palette_ram[pal_idx];
    }

    if (addr >= 0x3000u && addr < 0x3F00u) {
        addr = (uint16_t)(addr - 0x1000u);
    }

    if (addr >= 0x2000u && addr < 0x3000u) {
        uint16_t nt_offset = (uint16_t)(addr & 0x03FFu);
        uint16_t nt_index = (uint16_t)((addr >> 10) & 0x03u);

        switch (ppu->mirroring) {
            case PPU_MIRROR_VERTICAL:
                addr = (uint16_t)(0x2000u + ((nt_index & 1u) ? 0x0400u : 0u) + nt_offset);
                break;
            case PPU_MIRROR_HORIZONTAL:
                addr = (uint16_t)(0x2000u + ((nt_index >= 2u) ? 0x0400u : 0u) + nt_offset);
                break;
            case PPU_MIRROR_SINGLE_0:
                addr = (uint16_t)(0x2000u + nt_offset);
                break;
            case PPU_MIRROR_SINGLE_1:
                addr = (uint16_t)(0x2400u + nt_offset);
                break;
        }
    }

    return ppu->vram[addr];
}

void ppu_write_oam_buffer(Ppu2C02 *ppu, const uint8_t *oam_src) {
    if (ppu == NULL || oam_src == NULL) return;
    memcpy(ppu->oam, oam_src, OAM_BUFFER_SIZE);
}

void ppu_load_palettes(Ppu2C02 *ppu, const uint8_t palette_src[PALETTE_RAM_SIZE]) {
    if (ppu == NULL || palette_src == NULL) return;
    for (uint16_t i = 0; i < PALETTE_RAM_SIZE; ++i) {
        ppu_write_vram(ppu, (uint16_t)(0x3F00u + i), palette_src[i]);
    }
}

uint8_t ppu_decode_tile_pixel(const uint8_t *pattern_table_base, uint8_t tile_idx, int u, int v) {
    size_t tile_offset = (size_t)tile_idx * 16u + (size_t)(v & 7);
    uint8_t plane0 = pattern_table_base[tile_offset];
    uint8_t plane1 = pattern_table_base[tile_offset + 8u];

    int shift = 7 - (u & 7);
    uint8_t bit0 = (uint8_t)((plane0 >> shift) & 1u);
    uint8_t bit1 = (uint8_t)((plane1 >> shift) & 1u);

    return (uint8_t)((bit1 << 1) | bit0);
}

uint16_t ppu_get_nametable_address(const Ppu2C02 *ppu, uint16_t tx, uint16_t ty) {
    uint16_t nt_x = (tx / 32u) & 1u;
    uint16_t nt_y = (ty / 30u) & 1u;
    uint16_t col = tx % 32u;
    uint16_t row = ty % 30u;
    uint16_t base_addr = 0x2000u;

    if (ppu->mirroring == PPU_MIRROR_VERTICAL) {
        base_addr = (uint16_t)(0x2000u + nt_x * 0x0400u);
    } else if (ppu->mirroring == PPU_MIRROR_HORIZONTAL) {
        base_addr = (uint16_t)(0x2000u + nt_y * 0x0400u);
    }

    return (uint16_t)(base_addr + row * 32u + col);
}

void ppu_render_scanline(Ppu2C02 *ppu, int scanline) {
    if (ppu == NULL || scanline < 0 || scanline >= DISPLAY_HEIGHT) return;

    uint8_t bg_pixel_val[DISPLAY_WIDTH];
    memset(bg_pixel_val, 0, sizeof(bg_pixel_val));

    uint32_t *fb_line = &ppu->framebuffer[scanline * DISPLAY_WIDTH];
    uint32_t universal_bg = nes_color_to_rgba(ppu->palette_ram[0]);

    /* --- Background Layer Rendering --- */
    if (ppu->mask & PPUMASK_SHOW_BG) {
        uint16_t eff_y = (uint16_t)((ppu->scroll_y + (uint16_t)scanline) % 480u);
        uint16_t ty = (uint16_t)(eff_y / 8u);
        int py = (int)(eff_y % 8u);

        const uint8_t *pattern_base = &ppu->vram[(ppu->ctrl & PPUCTRL_BG_TABLE_1000) ? 0x1000u : 0x0000u];

        for (int x = 0; x < DISPLAY_WIDTH; ++x) {
            if (x < 8 && !(ppu->mask & PPUMASK_SHOW_BG_LEFT8)) {
                fb_line[x] = universal_bg;
                continue;
            }

            uint16_t eff_x = (uint16_t)((ppu->scroll_x + (uint16_t)x) % 512u);
            uint16_t tx = (uint16_t)(eff_x / 8u);
            int px = (int)(eff_x % 8u);

            /* Fetch Nametable tile */
            uint16_t tile_addr = ppu_get_nametable_address(ppu, tx, ty);
            uint8_t tile_id = ppu->vram[tile_addr];

            /* Fetch Attribute Table quadrant */
            uint16_t nt_base = (uint16_t)(tile_addr & 0xFC00u);
            uint16_t attr_col = (uint16_t)((tx % 32u) / 4u);
            uint16_t attr_row = (uint16_t)((ty % 30u) / 4u);
            uint16_t attr_addr = (uint16_t)(nt_base + 960u + attr_row * 8u + attr_col);
            uint8_t attr_byte = ppu->vram[attr_addr];

            int quad_x = (int)(((tx % 32u) % 4u) / 2u);
            int quad_y = (int)(((ty % 30u) % 4u) / 2u);
            int shift = (quad_y * 2 + quad_x) * 2;
            uint8_t subpalette = (uint8_t)((attr_byte >> shift) & 0x03u);

            /* Decode 2bpp tile pixel */
            uint8_t pixel_val = ppu_decode_tile_pixel(pattern_base, tile_id, px, py);
            bg_pixel_val[x] = pixel_val;

            if (pixel_val == 0) {
                fb_line[x] = universal_bg;
            } else {
                uint8_t nes_color = ppu->palette_ram[(size_t)subpalette * 4u + pixel_val];
                fb_line[x] = nes_color_to_rgba(nes_color);
            }
        }
    } else {
        for (int x = 0; x < DISPLAY_WIDTH; ++x) {
            fb_line[x] = universal_bg;
        }
    }

    /* --- 8x16 OAM Sprite Layer Rendering --- */
    if (ppu->mask & PPUMASK_SHOW_SPRITES) {
        uint8_t active_sprites[PPU_OAM_SPRITE_COUNT];
        uint8_t active_count = 0;

        /* Scan OAM for active sprites on this scanline */
        if (ppu->flicker_free_sprites) {
            /* Unlimited Sprite Mode: natural sequential scan */
            for (uint8_t i = 0; i < PPU_OAM_SPRITE_COUNT; ++i) {
                int sy = (int)ppu->oam[(size_t)i * 4u] + 1;
                if (scanline >= sy && scanline < sy + 16) {
                    active_sprites[active_count++] = i;
                }
            }
        } else {
            /* Authentic NES cyclic priority scan ($4C priority offset) */
            uint8_t start_sprite = (uint8_t)((ppu->oam_shift_offset >> 2) % PPU_OAM_SPRITE_COUNT);
            for (uint8_t step = 0; step < PPU_OAM_SPRITE_COUNT; ++step) {
                uint8_t i = (uint8_t)((start_sprite + step) % PPU_OAM_SPRITE_COUNT);
                int sy = (int)ppu->oam[(size_t)i * 4u] + 1;
                if (scanline >= sy && scanline < sy + 16) {
                    active_sprites[active_count++] = i;
                    if (active_count >= PPU_MAX_SPRITES_PER_SCANLINE) {
                        break; /* 8-sprite per scanline hardware limit reached */
                    }
                }
            }
        }

        uint8_t sprite_drawn[DISPLAY_WIDTH];
        memset(sprite_drawn, 0, sizeof(sprite_drawn));

        /*
         * Render active sprites: lower index in active_sprites has higher priority.
         */
        for (uint8_t k = 0; k < active_count; ++k) {
            uint8_t i = active_sprites[k];
            size_t oam_base = (size_t)i * 4u;
            int sy = (int)ppu->oam[oam_base] + 1;
            uint8_t tile_code = ppu->oam[oam_base + 1u];
            uint8_t attr = ppu->oam[oam_base + 2u];
            int sx = (int)ppu->oam[oam_base + 3u];

            int row = scanline - sy;
            if (attr & 0x80u) {
                row = 15 - row; /* Vertical Flip */
            }

            /* 8x16 Mode: bit 0 selects pattern table, bits 1..7 select even tile */
            const uint8_t *pattern_base = &ppu->vram[(tile_code & 1u) ? 0x1000u : 0x0000u];
            uint8_t tile_base = (uint8_t)(tile_code & 0xFEu);
            uint8_t actual_tile = (row < 8) ? tile_base : (uint8_t)(tile_base + 1u);
            int actual_row = (row < 8) ? row : (row - 8);

            uint8_t subpalette = (uint8_t)(attr & 0x03u);
            bool behind_bg = ((attr & 0x20u) != 0);

            for (int col = 0; col < 8; ++col) {
                int screen_x = sx + col;
                if (screen_x < 0 || screen_x >= DISPLAY_WIDTH) continue;
                if (screen_x < 8 && !(ppu->mask & PPUMASK_SHOW_SPRITES_LEFT8)) continue;
                if (sprite_drawn[screen_x]) continue; /* Higher priority sprite already rendered */

                int u = (attr & 0x40u) ? (7 - col) : col; /* Horizontal Flip */
                uint8_t pixel_val = ppu_decode_tile_pixel(pattern_base, actual_tile, u, actual_row);

                if (pixel_val == 0) continue; /* Transparent pixel */

                sprite_drawn[screen_x] = 1;

                /* Priority masking: if behind background and background is non-zero, do not draw */
                if (behind_bg && bg_pixel_val[screen_x] != 0) {
                    continue;
                }

                uint8_t nes_color = ppu->palette_ram[16u + (size_t)subpalette * 4u + pixel_val];
                fb_line[screen_x] = nes_color_to_rgba(nes_color);
            }
        }
    }
}

void ppu_render_frame(Ppu2C02 *ppu) {
    if (ppu == NULL) return;

    for (int y = 0; y < DISPLAY_HEIGHT; ++y) {
        ppu_render_scanline(ppu, y);
    }

    /* Advance cyclic priority shift offset ($4C) for authentic flicker cycle */
    ppu->oam_shift_offset = (uint8_t)((ppu->oam_shift_offset + PPU_AUTHENTIC_CYCLIC_SHIFT) & 0xFFu);
    ppu->frame_count++;
}

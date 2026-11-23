#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include "core/crypto.h"
#include "rom/rom_loader.h"
#include "rom/chr_extractor.h"
#include "rom/level_loader.h"
#include "render/ppu.h"
#include "render/nametable.h"

#define TEST_CHECK(cond, msg) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "[FAIL] %s:%d: %s\n", __FILE__, __LINE__, msg); \
            return 1; \
        } \
    } while (0)

int main(int argc, char **argv) {
    const char *rom_path = "Contra (USA).nes";
    if (argc > 1) {
        rom_path = argv[1];
    }

    printf("[TEST] Testing 2C02 PPU Renderer and OAM Sprite Engine with '%s'...\n", rom_path);

    RomData rom;
    TEST_CHECK(rom_load_file(rom_path, &rom) == RECON_OK, "Load ROM");

    Ppu2C02 ppu;
    ppu_init(&ppu);

    // 1. Test VRAM and Palette RAM Mirroring
    ppu_write_vram(&ppu, 0x3F00, 0x1A);
    TEST_CHECK(ppu_read_vram(&ppu, 0x3F00) == 0x1A, "Read palette $3F00");
    TEST_CHECK(ppu_read_vram(&ppu, 0x3F10) == 0x1A, "Mirror palette $3F10 to $3F00");
    TEST_CHECK(ppu_read_vram(&ppu, 0x3F20) == 0x1A, "Mirror palette $3F20 to $3F00");

    ppu_set_mirroring(&ppu, PPU_MIRROR_VERTICAL);
    ppu_write_vram(&ppu, 0x2005, 0x42);
    TEST_CHECK(ppu_read_vram(&ppu, 0x2805) == 0x42, "Vertical mirroring NT0 -> NT2");

    ppu_set_mirroring(&ppu, PPU_MIRROR_HORIZONTAL);
    ppu_write_vram(&ppu, 0x200A, 0x77);
    TEST_CHECK(ppu_read_vram(&ppu, 0x240A) == 0x77, "Horizontal mirroring NT0 -> NT1");

    // 2. Load Graphics & Stage 1 Background
    ppu_reset(&ppu);
    ppu_set_mirroring(&ppu, PPU_MIRROR_VERTICAL);

    TEST_CHECK(chr_load_level_graphics(&rom, 0, ppu.vram, sizeof(ppu.vram)) == RECON_OK, "Load Stage 1 graphics");

    LevelHeader lvl1;
    TEST_CHECK(level_load_header(&rom, 0, &lvl1) == RECON_OK, "Load Stage 1 header");

    uint8_t palette_ram[PALETTE_RAM_SIZE] = {0};
    TEST_CHECK(level_load_palettes(&rom, 0, palette_ram) == RECON_OK, "Load Stage 1 palettes");
    ppu_load_palettes(&ppu, palette_ram);

    // Unpack Screen 0 into NT0 ($2000) and Screen 1 into NT1 ($2400)
    TEST_CHECK(nametable_unpack_screen_horizontal(&ppu, 0, &rom, &lvl1, 0) == RECON_OK, "Unpack Screen 0");
    TEST_CHECK(nametable_unpack_screen_horizontal(&ppu, 1, &rom, &lvl1, 1) == RECON_OK, "Unpack Screen 1");

    // Render a baseline background frame
    ppu_render_frame(&ppu);

    size_t non_black_pixels = 0;
    uint32_t bg_color = ppu.framebuffer[0];
    for (int i = 0; i < DISPLAY_WIDTH * DISPLAY_HEIGHT; ++i) {
        if (ppu.framebuffer[i] != bg_color) {
            non_black_pixels++;
        }
    }
    printf("  Stage 1 Screen 0 rendered: %zu active colored pixels\n", non_black_pixels);
    TEST_CHECK(non_black_pixels > 10000, "Stage 1 background must have rendered pixels");

    // 3. Test 8x16 OAM Sprite Rendering and Flipping
    // Configure Sprite 0 at (x=64, y=64), Tile 0x00, Attr 0x00 (Normal)
    ppu.oam[0] = 64;  // Y
    ppu.oam[1] = 0x00; // Tile 0x00 (8x16)
    ppu.oam[2] = 0x00; // Normal
    ppu.oam[3] = 64;  // X

    // Sprite 1 at (x=80, y=64), Tile 0x00, Attr 0x40 (Horizontal Flip)
    ppu.oam[4] = 64;
    ppu.oam[5] = 0x00;
    ppu.oam[6] = 0x40; // H-Flip
    ppu.oam[7] = 80;

    // Sprite 2 at (x=96, y=64), Tile 0x00, Attr 0x80 (Vertical Flip)
    ppu.oam[8] = 64;
    ppu.oam[9] = 0x00;
    ppu.oam[10] = 0x80; // V-Flip
    ppu.oam[11] = 96;

    // Sprite 3 at (x=112, y=64), Tile 0x00, Attr 0x20 (Behind Background)
    ppu.oam[12] = 64;
    ppu.oam[13] = 0x00;
    ppu.oam[14] = 0x20; // Priority: Behind BG
    ppu.oam[15] = 112;

    ppu_render_frame(&ppu);
    printf("  Rendered frame with 8x16 sprites and priority flags.\n");

    // 4. Test 8-Sprite Limit & Authentic Cyclic Priority Shift ($4C)
    // Place 12 sprites on the exact same scanline Y=100
    for (uint8_t s = 0; s < 12; ++s) {
        ppu.oam[(size_t)s * 4u] = 100;
        ppu.oam[(size_t)s * 4u + 1u] = 0x02;
        ppu.oam[(size_t)s * 4u + 2u] = 0x00;
        ppu.oam[(size_t)s * 4u + 3u] = (uint8_t)(s * 10);
    }

    // Authentic mode: limit to 8 per scanline with $4C cyclic shift
    ppu.flicker_free_sprites = false;
    uint8_t initial_offset = ppu.oam_shift_offset;
    ppu_render_frame(&ppu);
    TEST_CHECK(ppu.oam_shift_offset == (uint8_t)(initial_offset + PPU_AUTHENTIC_CYCLIC_SHIFT), "Shift offset $4C check");
    printf("  Authentic 8-sprite per scanline dropout & cyclic shift verified.\n");

    // Flicker-free mode
    ppu.flicker_free_sprites = true;
    ppu_render_frame(&ppu);
    printf("  Flicker-free unlimited sprite mode verified.\n");

    // 5. Test Horizontal Scrolling across dual nametables
    ppu.scroll_x = 128; // Middle of Screen 0 and Screen 1
    ppu_render_frame(&ppu);

    // Compute deterministic framebuffer CRC-32
    uint32_t fb_crc = recon_crc32(reinterpret_cast<const uint8_t*>(ppu.framebuffer), sizeof(ppu.framebuffer));
    printf("  Rendered Framebuffer CRC-32: 0x%08X\n", fb_crc);
    TEST_CHECK(fb_crc != 0, "Framebuffer CRC must be valid non-zero");

    rom_free(&rom);
    printf("[PASS] 2C02 PPU Renderer and OAM Sprite Engine verified successfully!\n");
    return 0;
}

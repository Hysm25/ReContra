#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "rom/rom_loader.h"
#include "rom/level_loader.h"

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

    printf("[TEST] Testing Level loader and palettes with '%s'...\n", rom_path);

    RomData rom;
    TEST_CHECK(rom_load_file(rom_path, &rom) == RECON_OK, "Load ROM");

    // Verify all 8 Level Headers
    for (uint8_t lvl = 0; lvl < LEVEL_COUNT; ++lvl) {
        LevelHeader hdr = {};
        TEST_CHECK(level_load_header(&rom, lvl, &hdr) == RECON_OK, "Load level header");
        TEST_CHECK(hdr.level_index == lvl, "Level index matches");

        printf("  Stage %u: loc_type=%u, scroll_type=%u, screen_ptr=0x%04X, supertile_ptr=0x%04X, pal_ptr=0x%04X, alt_pos=%u\n",
               lvl + 1, hdr.location_type, hdr.scrolling_type, hdr.screen_ptr, hdr.supertile_ptr, hdr.palette_ptr, hdr.alt_graphics_pos);

        // Verification of known level types:
        if (lvl == 0) { // Stage 1 (Jungle): Outdoor, Horizontal
            TEST_CHECK(hdr.location_type == 0, "Stage 1 location type 0");
            TEST_CHECK(hdr.scrolling_type == 0, "Stage 1 scrolling type 0");
            TEST_CHECK(hdr.supertile_ptr == 0x8001, "Stage 1 supertile_ptr 0x8001");
            TEST_CHECK(hdr.alt_graphics_pos == 11, "Stage 1 alt_graphics_pos 11");
        } else if (lvl == 1) { // Stage 2 (Base 1): Indoor
            TEST_CHECK(hdr.location_type == 1, "Stage 2 location type 1");
            TEST_CHECK(hdr.alt_graphics_pos == 4, "Stage 2 alt_graphics_pos 4");
        } else if (lvl == 2) { // Stage 3 (Waterfall): Outdoor, Vertical
            TEST_CHECK(hdr.location_type == 0, "Stage 3 location type 0");
            TEST_CHECK(hdr.scrolling_type == 1, "Stage 3 scrolling type 1");
            TEST_CHECK(hdr.alt_graphics_pos == 7, "Stage 3 alt_graphics_pos 7");
        } else if (lvl == 3) { // Stage 4 (Base 2): Indoor
            TEST_CHECK(hdr.location_type == 1, "Stage 4 location type 1");
        }

        // Test loading palettes for this level
        uint8_t palette_buf[PALETTE_RAM_SIZE] = {0};
        TEST_CHECK(level_load_palettes(&rom, lvl, palette_buf) == RECON_OK, "Load palettes");
        // Palette index 0 and 16 should be universal background color 0x0F
        TEST_CHECK(palette_buf[0] == 0x0F, "Background color black at index 0");
        TEST_CHECK(palette_buf[16] == 0x0F, "Sprite transparent black at index 16");

        // Test reading first 4 supertiles for this level
        for (uint8_t st = 0; st < 4; ++st) {
            SupertileDef def = {};
            TEST_CHECK(level_read_supertile(&rom, hdr.supertile_ptr, st, &def) == RECON_OK, "Read supertile");
        }

        // Test RLE screen supertile decompression for Screen 0
        uint8_t supertiles[64] = {0};
        size_t expected_count = (hdr.scrolling_type == 1) ? 64 : 56;
        TEST_CHECK(level_decompress_screen_supertiles(&rom, &hdr, 0, supertiles, sizeof(supertiles)) == RECON_OK, "Decompress Screen 0 supertiles");
        if (lvl == 0) {
            // Stage 1 Screen 0 authentic RLE layout check
            TEST_CHECK(supertiles[0] == 0x21, "Stage 1 Screen 0 ST 0");
            TEST_CHECK(supertiles[1] == 0x20, "Stage 1 Screen 0 ST 1");
            TEST_CHECK(supertiles[2] == 0x21, "Stage 1 Screen 0 ST 2");
            TEST_CHECK(supertiles[3] == 0x2B, "Stage 1 Screen 0 ST 3");
            // Row 3 repeat count zeroes
            for (size_t z = 25; z < 32; ++z) {
                TEST_CHECK(supertiles[z] == 0x00, "Stage 1 Screen 0 Row 3 RLE zeroes");
            }
            // Row 6 water surface tiles
            for (size_t w = 48; w < 52; ++w) {
                TEST_CHECK(supertiles[w] == 0x10, "Stage 1 Screen 0 Row 6 water surface");
            }
            printf("  Stage 1 Screen 0 supertiles decompressed (%zu supertiles): RLE verified.\n", expected_count);
        }
    }

    rom_free(&rom);
    printf("[PASS] Level loader verified successfully!\n");
    return 0;
}

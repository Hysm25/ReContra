#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include "rom/rom_loader.h"
#include "rom/chr_extractor.h"

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

    printf("[TEST] Testing CHR dynamic RLE extractor with '%s'...\n", rom_path);

    RomData rom;
    TEST_CHECK(rom_load_file(rom_path, &rom) == RECON_OK, "Load ROM");

    std::vector<uint8_t> vram(PPU_VRAM_SIZE, 0);

    // Test all 27 individual graphic data entries (0x00..0x1A)
    for (uint8_t code = 0; code < GRAPHIC_DATA_COUNT; ++code) {
        GraphicDataEntry entry = {};
        TEST_CHECK(chr_get_graphic_entry(&rom, code, &entry) == RECON_OK, "Get graphic entry");
        TEST_CHECK(entry.code == code, "Code match");

        size_t written = 0;
        std::fill(vram.begin(), vram.end(), 0);
        ReconResult res = chr_decompress_graphic_code(&rom, code, vram.data(), vram.size(), &written);
        TEST_CHECK(res == RECON_OK, "Decompress graphic code");
        TEST_CHECK(written > 0, "Written bytes > 0");

        printf("  Code 0x%02X: Bank %u, CPU 0x%04X, Initial PPU 0x%04X, Flip=%s, Written=%zu bytes\n",
               code, entry.bank, entry.cpu_addr, entry.initial_ppu_addr,
               entry.horizontal_flip ? "true" : "false", written);

        if (code == 0x01) {
            // Intro pattern tables: should write exactly 4768 bytes in [$0CE0-$1F80)
            TEST_CHECK(written == 4768, "Code 0x01 expected 4768 bytes");
        } else if (code == 0x10) {
            // Horizontally flipped corridor tiles: should write exactly 1056 bytes in [$1600-$1A20)
            TEST_CHECK(entry.horizontal_flip == true, "Code 0x10 must have horizontal flip");
            TEST_CHECK(entry.initial_ppu_addr == 0x1600, "Code 0x10 initial PPU address 0x1600");
            TEST_CHECK(written == 1056, "Code 0x10 expected 1056 bytes");
        }
    }

    // Test Level Graphic Sets (0..12)
    for (uint8_t set_idx = 0; set_idx < LEVEL_GRAPHIC_COUNT; ++set_idx) {
        uint8_t codes[16] = {0};
        uint8_t count = 0;
        TEST_CHECK(chr_get_level_graphic_codes(&rom, set_idx, codes, &count) == RECON_OK, "Get level codes");
        TEST_CHECK(count > 0, "Level code count > 0");

        std::fill(vram.begin(), vram.end(), 0);
        TEST_CHECK(chr_load_level_graphics(&rom, set_idx, vram.data(), vram.size()) == RECON_OK, "Load level graphics");

        size_t non_zero_bytes = 0;
        for (uint8_t b : vram) {
            if (b != 0) non_zero_bytes++;
        }
        printf("  Level Set %u: %u graphic codes, %zu non-zero bytes loaded to VRAM\n",
               set_idx, count, non_zero_bytes);
        TEST_CHECK(non_zero_bytes > 0, "Non-zero VRAM bytes > 0");
    }

    rom_free(&rom);
    printf("[PASS] CHR RLE dynamic extractor verified successfully!\n");
    return 0;
}

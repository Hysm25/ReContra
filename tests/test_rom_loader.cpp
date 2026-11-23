#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "rom/rom_loader.h"

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

    printf("[TEST] Testing ROM loader with '%s'...\n", rom_path);

    RomData rom;
    ReconResult res = rom_load_file(rom_path, &rom);
    TEST_CHECK(res == RECON_OK, "Failed to load ROM file");

    // Header checks
    TEST_CHECK(rom.prg_banks == 8, "Expected 8 PRG banks");
    TEST_CHECK(rom.prg_size == 131072, "Expected 128KB PRG size");
    TEST_CHECK(rom.mapper == 2, "Expected Mapper 2 (UNROM)");
    TEST_CHECK(rom.vertical_mirroring == true, "Expected vertical mirroring");
    TEST_CHECK(rom.is_authentic == true, "Expected authentic Contra ROM");

    printf("  ROM Mapper: %u\n", rom.mapper);
    printf("  PRG Banks: %u (%zu bytes)\n", rom.prg_banks, rom.prg_size);
    printf("  File SHA-256: %s\n", rom.file_sha256_hex);
    printf("  File CRC-32:  0x%08X\n", rom.file_crc32);
    printf("  PRG SHA-256:  %s\n", rom.prg_sha256_hex);
    printf("  PRG CRC-32:   0x%08X\n", rom.prg_crc32);

    // Bank 7 vector checks (NMI, Reset, IRQ at $FFFA-$FFFF)
    uint16_t nmi_vector = 0;
    uint16_t reset_vector = 0;
    uint16_t irq_vector = 0;
    TEST_CHECK(rom_read_prg_word(&rom, 7, 0xFFFA, &nmi_vector) == RECON_OK, "Read NMI vector");
    TEST_CHECK(rom_read_prg_word(&rom, 7, 0xFFFC, &reset_vector) == RECON_OK, "Read Reset vector");
    TEST_CHECK(rom_read_prg_word(&rom, 7, 0xFFFE, &irq_vector) == RECON_OK, "Read IRQ vector");

    printf("  Bank 7 Vectors: NMI=0x%04X, Reset=0x%04X, IRQ=0x%04X\n", nmi_vector, reset_vector, irq_vector);
    TEST_CHECK(reset_vector >= 0xC000, "Reset vector must be in Bank 7 address space");
    TEST_CHECK(nmi_vector >= 0xC000, "NMI vector must be in Bank 7 address space");

    // Test bank boundary safety
    uint8_t dummy = 0;
    TEST_CHECK(rom_read_prg_byte(&rom, 0, 0x7FFF, &dummy) == RECON_ERR_OUT_OF_BOUNDS, "Underflow check");
    TEST_CHECK(rom_read_prg_byte(&rom, 0, 0xC000, &dummy) == RECON_ERR_OUT_OF_BOUNDS, "Switchable upper bound check");
    TEST_CHECK(rom_read_prg_byte(&rom, 7, 0xBFFF, &dummy) == RECON_ERR_OUT_OF_BOUNDS, "Bank 7 lower bound check");
    TEST_CHECK(rom_read_prg_byte(&rom, 8, 0x8000, &dummy) == RECON_ERR_OUT_OF_BOUNDS, "Invalid bank check");

    // Test invalid memory buffer loading
    RomData bad_rom;
    uint8_t garbage[16] = {0};
    TEST_CHECK(rom_load_memory(garbage, sizeof(garbage), &bad_rom) == RECON_ERR_INVALID_HEADER, "Garbage header check");

    rom_free(&rom);
    printf("[PASS] ROM loader verified successfully!\n");
    return 0;
}

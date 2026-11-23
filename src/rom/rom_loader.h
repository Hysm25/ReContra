#ifndef RECON_ROM_LOADER_H
#define RECON_ROM_LOADER_H

#include "core/types.h"
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint8_t header[INES_HEADER_SIZE];
    uint8_t *raw_data;
    size_t raw_size;

    const uint8_t *prg_data;
    size_t prg_size;
    uint8_t prg_banks;

    uint8_t mapper;
    bool vertical_mirroring;
    bool battery_ram;
    bool trainer;

    uint32_t file_crc32;
    uint8_t file_sha256[32];
    char file_sha256_hex[65];

    uint32_t prg_crc32;
    uint8_t prg_sha256[32];
    char prg_sha256_hex[65];

    bool is_authentic;
} RomData;

/*
 * Load and validate a Contra NES ROM from a file path.
 */
ReconResult rom_load_file(const char *filepath, RomData *out_rom);

/*
 * Load and validate a Contra NES ROM from an in-memory buffer.
 */
ReconResult rom_load_memory(const uint8_t *buffer, size_t size, RomData *out_rom);

/*
 * Free allocated ROM memory.
 */
void rom_free(RomData *rom);

/*
 * Returns a pointer to the start of a 16KB PRG ROM bank (bank 0..7).
 * Returns NULL if bank is out of bounds or rom is invalid.
 */
const uint8_t *rom_get_bank(const RomData *rom, uint8_t bank);

/*
 * Translates a CPU address ($8000-$BFFF for switchable banks 0..6, $C000-$FFFF for bank 7)
 * to an absolute PRG ROM offset (0..131071).
 * Returns (size_t)-1 on invalid input.
 */
size_t rom_cpu_addr_to_prg_offset(uint8_t bank, uint16_t cpu_addr);

/*
 * Read a single byte from PRG ROM by bank and CPU address.
 */
ReconResult rom_read_prg_byte(const RomData *rom, uint8_t bank, uint16_t cpu_addr, uint8_t *out_byte);

/*
 * Read a little-endian 16-bit word from PRG ROM by bank and CPU address.
 */
ReconResult rom_read_prg_word(const RomData *rom, uint8_t bank, uint16_t cpu_addr, uint16_t *out_word);

/*
 * Checks if the loaded ROM is verified authentic Contra (US) NES release.
 */
bool rom_is_authentic_contra(const RomData *rom);

#ifdef __cplusplus
}
#endif

#endif /* RECON_ROM_LOADER_H */

#ifndef RECON_CHR_EXTRACTOR_H
#define RECON_CHR_EXTRACTOR_H

#include "rom/rom_loader.h"
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Disassembly Bank 7 constants:
 * - graphic_data_ptr_tbl: CPU $C950 (27 entries * 3 bytes)
 * - level_graphic_data_tbl: CPU $C8E3 (13 pointer entries)
 */
#define GRAPHIC_DATA_PTR_TBL_ADDR     0xC950u
#define GRAPHIC_DATA_COUNT            27u
#define LEVEL_GRAPHIC_DATA_TBL_ADDR   0xC8E3u
#define LEVEL_GRAPHIC_COUNT           13u

typedef struct {
    uint8_t code;
    uint8_t bank;
    uint16_t cpu_addr;
    bool horizontal_flip;
    uint16_t initial_ppu_addr;
} GraphicDataEntry;

/*
 * Reads the entry definition for graphic code (0..26) dynamically from Bank 7.
 */
ReconResult chr_get_graphic_entry(const RomData *rom, uint8_t code, GraphicDataEntry *out_entry);

/*
 * Decompresses a single graphic data code (0..26) dynamically into PPU VRAM.
 * Matching NES routine `write_graphic_data_to_ppu`.
 */
ReconResult chr_decompress_graphic_code(const RomData *rom, uint8_t code, uint8_t *vram, size_t vram_size, size_t *out_bytes_written);

/*
 * Reads the list of graphic data codes for a level set (0..12) dynamically from Bank 7.
 */
ReconResult chr_get_level_graphic_codes(const RomData *rom, uint8_t level_set, uint8_t out_codes[16], uint8_t *out_count);

/*
 * Decompresses all graphic codes for a level set (0..12) into PPU VRAM.
 * Matching NES routine `load_level_graphic_data`.
 */
ReconResult chr_load_level_graphics(const RomData *rom, uint8_t level_set, uint8_t *vram, size_t vram_size);

#ifdef __cplusplus
}
#endif

#endif /* RECON_CHR_EXTRACTOR_H */

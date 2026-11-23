#include "rom/chr_extractor.h"
#include <string.h>

ReconResult chr_get_graphic_entry(const RomData *rom, uint8_t code, GraphicDataEntry *out_entry) {
    if (rom == NULL || out_entry == NULL) {
        return RECON_ERR_NULL_PTR;
    }
    if (code >= GRAPHIC_DATA_COUNT) {
        return RECON_ERR_OUT_OF_BOUNDS;
    }

    uint16_t entry_addr = (uint16_t)(GRAPHIC_DATA_PTR_TBL_ADDR + (uint16_t)(code * 3u));
    uint8_t addr_low = 0;
    uint8_t addr_high = 0;
    uint8_t bank_byte = 0;

    ReconResult res = rom_read_prg_byte(rom, 7, entry_addr, &addr_low);
    if (res != RECON_OK) return res;
    res = rom_read_prg_byte(rom, 7, (uint16_t)(entry_addr + 1u), &addr_high);
    if (res != RECON_OK) return res;
    res = rom_read_prg_byte(rom, 7, (uint16_t)(entry_addr + 2u), &bank_byte);
    if (res != RECON_OK) return res;

    out_entry->code = code;
    out_entry->cpu_addr = (uint16_t)(((uint16_t)addr_high << 8) | (uint16_t)addr_low);
    out_entry->horizontal_flip = ((bank_byte & 0x80u) != 0);

    /* Bits 0..2 specify bank. 0 means bank 7 in NES Contra routine */
    uint8_t bank_num = (uint8_t)(bank_byte & 0x07u);
    out_entry->bank = (bank_num == 0) ? 7u : bank_num;

    /* Read initial 2-byte PPU address from destination bank */
    uint8_t ppu_low = 0;
    uint8_t ppu_high = 0;
    res = rom_read_prg_byte(rom, out_entry->bank, out_entry->cpu_addr, &ppu_low);
    if (res != RECON_OK) return res;
    res = rom_read_prg_byte(rom, out_entry->bank, (uint16_t)(out_entry->cpu_addr + 1u), &ppu_high);
    if (res != RECON_OK) return res;
    out_entry->initial_ppu_addr = (uint16_t)(((uint16_t)ppu_high << 8) | (uint16_t)ppu_low);

    return RECON_OK;
}

ReconResult chr_decompress_graphic_code(const RomData *rom, uint8_t code, uint8_t *vram, size_t vram_size, size_t *out_bytes_written) {
    if (rom == NULL || vram == NULL) {
        return RECON_ERR_NULL_PTR;
    }
    GraphicDataEntry entry;
    ReconResult res = chr_get_graphic_entry(rom, code, &entry);
    if (res != RECON_OK) {
        return res;
    }

    size_t prg_offset = rom_cpu_addr_to_prg_offset(entry.bank, entry.cpu_addr);
    if (prg_offset == (size_t)-1 || prg_offset >= rom->prg_size) {
        return RECON_ERR_OUT_OF_BOUNDS;
    }

    /*
     * begin_ppu_graphics_block_write reads 2-byte PPU address:
     * High byte is read from offset + 1, low byte is read from offset + 0.
     * If horizontal_flip is set, advances 4 bytes (skipping the referenced real PPU address);
     * otherwise advances 2 bytes.
     */
    uint16_t ppu_addr = entry.initial_ppu_addr;
    prg_offset += entry.horizontal_flip ? 4u : 2u;

    size_t written = 0;
    const uint8_t *prg = rom->prg_data;
    size_t total_prg = rom->prg_size;

    while (prg_offset < total_prg) {
        uint8_t cmd = prg[prg_offset];

        if (cmd == 0xFFu) {
            /* Command $FF: End of graphic stream */
            break;
        }

        if (cmd == 0x7Fu) {
            /* Command $7F: Reposition PPU write address */
            if (prg_offset + 2u >= total_prg) {
                return RECON_ERR_CORRUPT_DATA;
            }
            uint8_t low = prg[prg_offset + 1u];
            uint8_t high = prg[prg_offset + 2u];
            ppu_addr = (uint16_t)(((uint16_t)high << 8) | (uint16_t)low);
            prg_offset += 3u;
            continue;
        }

        if ((cmd & 0x80u) != 0) {
            /* Bit 7 set: Literal uncompressed byte sequence of length (cmd & 0x7F) */
            uint8_t count = (uint8_t)(cmd & 0x7Fu);
            prg_offset += 1u;

            if (prg_offset + (size_t)count > total_prg) {
                return RECON_ERR_CORRUPT_DATA;
            }

            for (uint8_t i = 0; i < count; ++i) {
                uint8_t b = prg[prg_offset + (size_t)i];
                if (entry.horizontal_flip) {
                    b = reverse_bits_u8(b);
                }
                if ((size_t)ppu_addr < vram_size) {
                    vram[ppu_addr] = b;
                    written++;
                }
                ppu_addr = (uint16_t)(ppu_addr + 1u);
            }
            prg_offset += (size_t)count;
        } else {
            /* Bit 7 clear: RLE run-length repetition of next byte (cmd times) */
            uint8_t count = cmd;
            if (prg_offset + 1u >= total_prg) {
                return RECON_ERR_CORRUPT_DATA;
            }
            uint8_t val = prg[prg_offset + 1u];
            if (entry.horizontal_flip) {
                val = reverse_bits_u8(val);
            }
            prg_offset += 2u;

            for (uint8_t i = 0; i < count; ++i) {
                if ((size_t)ppu_addr < vram_size) {
                    vram[ppu_addr] = val;
                    written++;
                }
                ppu_addr = (uint16_t)(ppu_addr + 1u);
            }
        }
    }

    if (out_bytes_written != NULL) {
        *out_bytes_written = written;
    }
    return RECON_OK;
}

ReconResult chr_get_level_graphic_codes(const RomData *rom, uint8_t level_set, uint8_t out_codes[16], uint8_t *out_count) {
    if (rom == NULL || out_codes == NULL || out_count == NULL) {
        return RECON_ERR_NULL_PTR;
    }
    if (level_set >= LEVEL_GRAPHIC_COUNT) {
        return RECON_ERR_OUT_OF_BOUNDS;
    }

    /* Read level list pointer from level_graphic_data_tbl at $C8E3 in Bank 7 */
    uint16_t ptr_addr = (uint16_t)(LEVEL_GRAPHIC_DATA_TBL_ADDR + (uint16_t)(level_set * 2u));
    uint16_t list_cpu_addr = 0;
    ReconResult res = rom_read_prg_word(rom, 7, ptr_addr, &list_cpu_addr);
    if (res != RECON_OK) {
        return res;
    }

    uint8_t count = 0;
    while (count < 16u) {
        uint8_t code = 0;
        res = rom_read_prg_byte(rom, 7, (uint16_t)(list_cpu_addr + count), &code);
        if (res != RECON_OK) {
            return res;
        }
        if (code == 0xFFu) {
            break;
        }
        out_codes[count] = code;
        count++;
    }

    *out_count = count;
    return RECON_OK;
}

ReconResult chr_load_level_graphics(const RomData *rom, uint8_t level_set, uint8_t *vram, size_t vram_size) {
    if (rom == NULL || vram == NULL) {
        return RECON_ERR_NULL_PTR;
    }
    uint8_t codes[16];
    uint8_t count = 0;
    ReconResult res = chr_get_level_graphic_codes(rom, level_set, codes, &count);
    if (res != RECON_OK) {
        return res;
    }

    for (uint8_t i = 0; i < count; ++i) {
        res = chr_decompress_graphic_code(rom, codes[i], vram, vram_size, NULL);
        if (res != RECON_OK) {
            return res;
        }
    }
    return RECON_OK;
}

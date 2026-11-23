#include "rom/rom_loader.h"
#include "core/crypto.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define AUTH_US_FILE_SHA256   "26541a5550ee22deeb3d5484e4a96130219b58cff74d068fb1eb6567fa5e5519"
#define AUTH_US_FILE_CRC32    0xC50A8304u
#define AUTH_US_PRG_SHA256    "d41e28b1a33b3b6768e7c39c9fdfb1fda4b49940542d14085911fabd399e1ca9"
#define AUTH_US_PRG_CRC32     0xF6035030u

#define ALT_AUTH_FILE_SHA256  "8a6496924d54da80b72448ca33faec2c4a04d5ff645e54c8feefab7593c2a32c"
#define ALT_AUTH_FILE_CRC32   0x34EE3A27u

size_t rom_cpu_addr_to_prg_offset(uint8_t bank, uint16_t cpu_addr) {
    if (bank >= PRG_BANK_COUNT) {
        return (size_t)-1;
    }

    if (bank == 7) {
        if (cpu_addr < 0xC000u) {
            return (size_t)-1;
        }
        return (size_t)(7u * PRG_BANK_SIZE + (size_t)(cpu_addr - 0xC000u));
    } else {
        if (cpu_addr < 0x8000u || cpu_addr > 0xBFFFu) {
            return (size_t)-1;
        }
        return (size_t)((size_t)bank * PRG_BANK_SIZE + (size_t)(cpu_addr - 0x8000u));
    }
}

const uint8_t *rom_get_bank(const RomData *rom, uint8_t bank) {
    if (rom == NULL || rom->prg_data == NULL || bank >= rom->prg_banks) {
        return NULL;
    }
    return &rom->prg_data[(size_t)bank * PRG_BANK_SIZE];
}

ReconResult rom_read_prg_byte(const RomData *rom, uint8_t bank, uint16_t cpu_addr, uint8_t *out_byte) {
    if (rom == NULL || out_byte == NULL) {
        return RECON_ERR_NULL_PTR;
    }
    size_t offset = rom_cpu_addr_to_prg_offset(bank, cpu_addr);
    if (offset == (size_t)-1 || offset >= rom->prg_size) {
        return RECON_ERR_OUT_OF_BOUNDS;
    }
    *out_byte = rom->prg_data[offset];
    return RECON_OK;
}

ReconResult rom_read_prg_word(const RomData *rom, uint8_t bank, uint16_t cpu_addr, uint16_t *out_word) {
    if (rom == NULL || out_word == NULL) {
        return RECON_ERR_NULL_PTR;
    }
    uint8_t low = 0;
    uint8_t high = 0;
    ReconResult res = rom_read_prg_byte(rom, bank, cpu_addr, &low);
    if (res != RECON_OK) {
        return res;
    }
    res = rom_read_prg_byte(rom, bank, (uint16_t)(cpu_addr + 1u), &high);
    if (res != RECON_OK) {
        return res;
    }
    *out_word = (uint16_t)(((uint16_t)high << 8) | (uint16_t)low);
    return RECON_OK;
}

bool rom_is_authentic_contra(const RomData *rom) {
    if (rom == NULL) {
        return false;
    }
    if (rom->file_crc32 == AUTH_US_FILE_CRC32 && strcmp(rom->file_sha256_hex, AUTH_US_FILE_SHA256) == 0) {
        return true;
    }
    if (rom->prg_crc32 == AUTH_US_PRG_CRC32 && strcmp(rom->prg_sha256_hex, AUTH_US_PRG_SHA256) == 0) {
        return true;
    }
    if (rom->file_crc32 == ALT_AUTH_FILE_CRC32 || strcmp(rom->file_sha256_hex, ALT_AUTH_FILE_SHA256) == 0) {
        return true;
    }
    return false;
}

ReconResult rom_load_memory(const uint8_t *buffer, size_t size, RomData *out_rom) {
    if (buffer == NULL || out_rom == NULL) {
        return RECON_ERR_NULL_PTR;
    }
    memset(out_rom, 0, sizeof(RomData));

    if (size < INES_HEADER_SIZE) {
        return RECON_ERR_INVALID_HEADER;
    }

    if (buffer[0] != 'N' || buffer[1] != 'E' || buffer[2] != 'S' || buffer[3] != 0x1A) {
        return RECON_ERR_INVALID_HEADER;
    }

    memcpy(out_rom->header, buffer, INES_HEADER_SIZE);
    out_rom->prg_banks = buffer[4];
    uint8_t flags6 = buffer[6];
    uint8_t flags7 = buffer[7];

    out_rom->mapper = (uint8_t)(((flags6 >> 4) & 0x0Fu) | (flags7 & 0xF0u));
    out_rom->vertical_mirroring = ((flags6 & 0x01u) != 0);
    out_rom->battery_ram = ((flags6 & 0x02u) != 0);
    out_rom->trainer = ((flags6 & 0x04u) != 0);

    /* Contra US is Mapper 2 (UNROM), 8 PRG banks (128KB), 0 CHR banks (8KB CHR RAM) */
    if (out_rom->mapper != 2) {
        return RECON_ERR_UNSUPPORTED_MAPPER;
    }

    size_t prg_start = INES_HEADER_SIZE + (out_rom->trainer ? 512u : 0u);
    out_rom->prg_size = (size_t)out_rom->prg_banks * PRG_BANK_SIZE;

    if (size < prg_start + out_rom->prg_size) {
        return RECON_ERR_CORRUPT_DATA;
    }

    /* Allocate owned buffer */
    out_rom->raw_data = (uint8_t *)malloc(size);
    if (out_rom->raw_data == NULL) {
        return RECON_ERR_ALLOC_FAILED;
    }
    memcpy(out_rom->raw_data, buffer, size);
    out_rom->raw_size = size;
    out_rom->prg_data = out_rom->raw_data + prg_start;

    /* Compute Checksums */
    out_rom->file_crc32 = recon_crc32(buffer, size);
    recon_sha256(buffer, size, out_rom->file_sha256);
    recon_sha256_to_hex(out_rom->file_sha256, out_rom->file_sha256_hex);

    out_rom->prg_crc32 = recon_crc32(out_rom->prg_data, out_rom->prg_size);
    recon_sha256(out_rom->prg_data, out_rom->prg_size, out_rom->prg_sha256);
    recon_sha256_to_hex(out_rom->prg_sha256, out_rom->prg_sha256_hex);

    out_rom->is_authentic = rom_is_authentic_contra(out_rom);

    return RECON_OK;
}

ReconResult rom_load_file(const char *filepath, RomData *out_rom) {
    if (filepath == NULL || out_rom == NULL) {
        return RECON_ERR_NULL_PTR;
    }
    memset(out_rom, 0, sizeof(RomData));

    FILE *f = fopen(filepath, "rb");
    if (f == NULL) {
        return RECON_ERR_FILE_NOT_FOUND;
    }

    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return RECON_ERR_FILE_IO;
    }

    long file_size = ftell(f);
    if (file_size <= 0) {
        fclose(f);
        return RECON_ERR_FILE_IO;
    }
    rewind(f);

    uint8_t *buf = (uint8_t *)malloc((size_t)file_size);
    if (buf == NULL) {
        fclose(f);
        return RECON_ERR_ALLOC_FAILED;
    }

    size_t read_bytes = fread(buf, 1, (size_t)file_size, f);
    fclose(f);

    if (read_bytes != (size_t)file_size) {
        free(buf);
        return RECON_ERR_FILE_IO;
    }

    ReconResult res = rom_load_memory(buf, (size_t)file_size, out_rom);
    free(buf);
    return res;
}

void rom_free(RomData *rom) {
    if (rom != NULL) {
        if (rom->raw_data != NULL) {
            free(rom->raw_data);
            rom->raw_data = NULL;
        }
        rom->prg_data = NULL;
        rom->raw_size = 0;
        rom->prg_size = 0;
    }
}

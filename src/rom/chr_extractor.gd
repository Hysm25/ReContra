class_name ChrExtractor
extends RefCounted

## Generic Dynamic CHR Pattern Table Extractor & RLE Decompressor
## Resolves graphics pointer tables dynamically from Bank 7 ($C950 and $C8E3)
## and decompresses RLE pattern graphics into an 8 KB CHR-RAM buffer (PPU $0000-$1FFF).

# --- Constants: Memory & Disassembly Table Offsets ---
const GRAPHIC_DATA_PTR_TBL_ADDR: int = 0xC950  # Bank 7 (27 entries * 3 bytes)
const GRAPHIC_DATA_COUNT: int = 27             # Graphic codes 0x00..0x1A
const LEVEL_GRAPHIC_DATA_TBL_ADDR: int = 0xC8E3 # Bank 7 (13 level set pointers)
const LEVEL_GRAPHIC_COUNT: int = 13            # Graphic sets 0..12
const CHR_RAM_SIZE: int = 8192                 # 8 KB PPU Pattern RAM ($0000-$1FFF)
const PPU_VRAM_SIZE: int = 16384               # 16 KB Full PPU Address Space ($0000-$3FFF)


## Entry descriptor for a single compressed graphic data stream
class GraphicEntry extends RefCounted:
	var code: int = 0
	var bank: int = 0
	var cpu_addr: int = 0
	var horizontal_flip: bool = false
	var initial_ppu_addr: int = 0


## Bit-reversal helper for horizontally mirrored/flipped pattern graphics
static func reverse_bits_u8(b: int) -> int:
	b = ((b & 0xF0) >> 4) | ((b & 0x0F) << 4)
	b = ((b & 0xCC) >> 2) | ((b & 0x33) << 2)
	b = ((b & 0xAA) >> 1) | ((b & 0x55) << 1)
	return b & 0xFF


## Allocates a zero-initialized 8 KB CHR-RAM buffer (PPU $0000-$1FFF)
static func allocate_chr_ram() -> PackedByteArray:
	var vram: PackedByteArray = PackedByteArray()
	vram.resize(CHR_RAM_SIZE)
	return vram


## Allocates a zero-initialized 16 KB Full PPU VRAM buffer (PPU $0000-$3FFF)
static func allocate_ppu_vram() -> PackedByteArray:
	var vram: PackedByteArray = PackedByteArray()
	vram.resize(PPU_VRAM_SIZE)
	return vram


## Reads the entry definition for graphic code (0..26) dynamically from Bank 7
static func get_graphic_entry(loader: RefCounted, code: int) -> GraphicEntry:
	if code < 0 or code >= GRAPHIC_DATA_COUNT:
		return null

	var entry_addr: int = GRAPHIC_DATA_PTR_TBL_ADDR + (code * 3)
	var addr_low: int = loader.read_cpu(entry_addr, 7)
	var addr_high: int = loader.read_cpu(entry_addr + 1, 7)
	var bank_byte: int = loader.read_cpu(entry_addr + 2, 7)
	if addr_low < 0 or addr_high < 0 or bank_byte < 0:
		return null

	var entry: GraphicEntry = GraphicEntry.new()
	entry.code = code
	entry.cpu_addr = (addr_high << 8) | addr_low
	entry.horizontal_flip = (bank_byte & 0x80) != 0

	# Bits 0..2 specify PRG bank number (0 means Bank 7 in UNROM graphics dispatch)
	var bank_num: int = bank_byte & 0x07
	entry.bank = 7 if bank_num == 0 else bank_num

	# Read initial 2-byte PPU destination address from the source PRG bank
	var ppu_low: int = loader.read_cpu(entry.cpu_addr, entry.bank)
	var ppu_high: int = loader.read_cpu(entry.cpu_addr + 1, entry.bank)
	if ppu_low < 0 or ppu_high < 0:
		return null

	entry.initial_ppu_addr = (ppu_high << 8) | ppu_low
	return entry


## Decompresses a single graphic data code (0..26) into an 8 KB VRAM buffer.
## Implements the 4 stream commands:
##   - Command $FF: End of graphic stream
##   - Command $7F: Reposition destination PPU address
##   - Byte > $7F: Literal uncompressed byte sequence of length (byte & 0x7F)
##   - Byte < $7F: RLE run-length repetition of next byte (byte times)
## Returns the total number of bytes written to VRAM, or -1 on error.
static func decompress_graphic_code(loader: RefCounted, code: int, vram: PackedByteArray) -> int:
	var entry: GraphicEntry = get_graphic_entry(loader, code)
	if entry == null:
		return -1

	var prg_offset: int = loader.cpu_addr_to_prg_offset(entry.cpu_addr, entry.bank)
	if prg_offset < 0:
		return -1

	var prg: PackedByteArray = loader.get_prg_rom()
	var total_prg: int = prg.size()

	# If horizontal_flip is enabled, skip 4 bytes (skipping reference PPU address);
	# otherwise skip 2 bytes (the initial PPU address).
	var ppu_addr: int = entry.initial_ppu_addr
	prg_offset += 4 if entry.horizontal_flip else 2

	var written: int = 0
	var vram_size: int = vram.size()

	while prg_offset < total_prg:
		var cmd: int = prg[prg_offset]

		if cmd == 0xFF:
			# Command $FF: End of graphic stream
			break

		if cmd == 0x7F:
			# Command $7F: Reposition PPU write address
			if prg_offset + 2 >= total_prg:
				return -1
			var low: int = prg[prg_offset + 1]
			var high: int = prg[prg_offset + 2]
			ppu_addr = (high << 8) | low
			prg_offset += 3
			continue

		if (cmd & 0x80) != 0:
			# Bit 7 set: Literal uncompressed byte sequence of length (cmd & 0x7F)
			var count: int = cmd & 0x7F
			prg_offset += 1
			if prg_offset + count > total_prg:
				return -1

			for i in range(count):
				var b: int = prg[prg_offset + i]
				if entry.horizontal_flip:
					b = reverse_bits_u8(b)
				if ppu_addr < vram_size:
					vram[ppu_addr] = b
					written += 1
				ppu_addr += 1
			prg_offset += count
		else:
			# Bit 7 clear: RLE run-length repetition of next byte (cmd times)
			var count: int = cmd
			if prg_offset + 1 >= total_prg:
				return -1
			var val: int = prg[prg_offset + 1]
			if entry.horizontal_flip:
				val = reverse_bits_u8(val)
			prg_offset += 2

			for _i in range(count):
				if ppu_addr < vram_size:
					vram[ppu_addr] = val
					written += 1
				ppu_addr += 1

	return written


## Reads the list of graphic data codes for a level set (0..12) dynamically from Bank 7
static func get_level_graphic_codes(loader: RefCounted, level_set: int) -> PackedByteArray:
	var result: PackedByteArray = PackedByteArray()
	if level_set < 0 or level_set >= LEVEL_GRAPHIC_COUNT:
		return result

	var ptr_addr: int = LEVEL_GRAPHIC_DATA_TBL_ADDR + (level_set * 2)
	var list_cpu_addr: int = loader.read_cpu_word(ptr_addr, 7)
	if list_cpu_addr < 0:
		return result

	for i in range(16):
		var code: int = loader.read_cpu(list_cpu_addr + i, 7)
		if code < 0 or code == 0xFF:
			break
		result.append(code)

	return result


## Decompresses all graphic codes for a level set (0..12) into an 8 KB VRAM buffer.
## Returns total bytes written, or -1 on error.
static func load_level_graphics(loader: RefCounted, level_set: int, vram: PackedByteArray) -> int:
	var codes: PackedByteArray = get_level_graphic_codes(loader, level_set)
	if codes.is_empty():
		return -1

	var total_written: int = 0
	for code in codes:
		var w: int = decompress_graphic_code(loader, code, vram)
		if w < 0:
			return -1
		total_written += w

	return total_written

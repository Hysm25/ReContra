class_name RomLoader
extends RefCounted

## Generic iNES ROM Loader & Memory Mapper
## Supports Mapper 2 (UNROM) cartridges with 128 KB PRG ROM and 8 KB CHR RAM.
## Validates header constraints, computes cryptographic checksums, and provides
## CPU bus address translation for switchable PRG banks ($8000-$BFFF) and fixed Bank 7 ($C000-$FFFF).

# --- Constants: Memory Architecture ---
const INES_HEADER_SIZE: int = 16
const PRG_BANK_SIZE: int = 16384  # 16 KB ($4000 bytes)
const PRG_BANK_COUNT: int = 8      # 8 banks (128 KB total)
const TOTAL_PRG_SIZE: int = 131072 # 8 * 16384
const EXPECTED_MAPPER: int = 2     # UNROM
const TRAINER_SIZE: int = 512

# --- Constants: Verified Reference Checksums ---
# Primary authentic target release (Headered File & PRG-only)
const AUTH_FILE_SHA256: String = "26541a5550ee22deeb3d5484e4a96130219b58cff74d068fb1eb6567fa5e5519"
const AUTH_FILE_CRC32: int = 0xC50A8304
const AUTH_PRG_SHA256: String = "d41e28b1a33b3b6768e7c39c9fdfb1fda4b49940542d14085911fabd399e1ca9"
const AUTH_PRG_CRC32: int = 0xF6035030

# Alternate verified reference release
const ALT_AUTH_FILE_SHA256: String = "8a6496924d54da80b72448ca33faec2c4a04d5ff645e54c8feefab7593c2a32c"
const ALT_AUTH_FILE_CRC32: int = 0x34EE3A27

# --- CRC32 Lookup Table Cache ---
static var _crc32_table: PackedInt64Array = []

# --- ROM Properties ---
var raw_data: PackedByteArray = PackedByteArray()
var header: PackedByteArray = PackedByteArray()
var prg_rom: PackedByteArray = PackedByteArray()

var prg_banks: int = 0
var chr_banks: int = 0
var mapper: int = -1
var vertical_mirroring: bool = false
var battery_ram: bool = false
var has_trainer: bool = false

var file_sha256: String = ""
var file_crc32: int = 0
var prg_sha256: String = ""
var prg_crc32: int = 0
var is_authentic: bool = false


## Precomputes IEEE 802.3 CRC32 lookup table (polynomial 0xEDB88320)
static func _init_crc32_table() -> void:
	if not _crc32_table.is_empty():
		return
	_crc32_table.resize(256)
	for i in range(256):
		var entry: int = i
		for _bit in range(8):
			if (entry & 1) != 0:
				entry = (entry >> 1) ^ 0xEDB88320
			else:
				entry = entry >> 1
		_crc32_table[i] = entry & 0xFFFFFFFF


## Computes 32-bit CRC checksum for a byte array
static func compute_crc32(data: PackedByteArray) -> int:
	_init_crc32_table()
	var crc: int = 0xFFFFFFFF
	for byte in data:
		var idx: int = (crc ^ byte) & 0xFF
		crc = (crc >> 8) ^ _crc32_table[idx]
	return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF


## Computes hexadecimal SHA-256 hash string for a byte array
static func compute_sha256(data: PackedByteArray) -> String:
	var ctx: HashingContext = HashingContext.new()
	var err: Error = ctx.start(HashingContext.HASH_SHA256)
	if err != OK:
		return ""
	ctx.update(data)
	var digest: PackedByteArray = ctx.finish()
	return digest.hex_encode().to_lower()


## Loads and validates a ROM image from a file path
func load_from_file(filepath: String) -> Error:
	var file: FileAccess = FileAccess.open(filepath, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var data: PackedByteArray = file.get_buffer(file.get_length())
	return load_from_buffer(data)


## Loads and validates a ROM image from an in-memory byte buffer
func load_from_buffer(buffer: PackedByteArray) -> Error:
	_reset()
	if buffer.size() < INES_HEADER_SIZE:
		return ERR_INVALID_DATA

	# Validate iNES magic identifier: 'N', 'E', 'S', 0x1A
	if buffer[0] != 0x4E or buffer[1] != 0x45 or buffer[2] != 0x53 or buffer[3] != 0x1A:
		return ERR_INVALID_DATA

	raw_data = buffer
	header = buffer.slice(0, INES_HEADER_SIZE)

	prg_banks = header[4]
	chr_banks = header[5]
	var flags6: int = header[6]
	var flags7: int = header[7]

	vertical_mirroring = (flags6 & 0x01) != 0
	battery_ram = (flags6 & 0x02) != 0
	has_trainer = (flags6 & 0x04) != 0
	mapper = ((flags6 >> 4) & 0x0F) | (flags7 & 0xF0)

	# Validate Mapper 2 (UNROM), 8 PRG banks (128 KB), 0 CHR ROM banks (8 KB CHR RAM)
	if mapper != EXPECTED_MAPPER:
		return ERR_UNAVAILABLE

	if prg_banks != PRG_BANK_COUNT:
		return ERR_INVALID_DATA

	if chr_banks != 0:
		return ERR_INVALID_DATA

	var prg_start_offset: int = INES_HEADER_SIZE + (TRAINER_SIZE if has_trainer else 0)
	var expected_total_size: int = prg_start_offset + TOTAL_PRG_SIZE
	if raw_data.size() < expected_total_size:
		return ERR_FILE_CORRUPT

	prg_rom = raw_data.slice(prg_start_offset, prg_start_offset + TOTAL_PRG_SIZE)

	# Compute and verify cryptographic hashes
	file_crc32 = compute_crc32(raw_data)
	file_sha256 = compute_sha256(raw_data)

	prg_crc32 = compute_crc32(prg_rom)
	prg_sha256 = compute_sha256(prg_rom)

	is_authentic = _verify_authenticity()
	return OK


## Checks computed hashes against verified reference entries
func _verify_authenticity() -> bool:
	if file_crc32 == AUTH_FILE_CRC32 and file_sha256 == AUTH_FILE_SHA256:
		return true
	if prg_crc32 == AUTH_PRG_CRC32 and prg_sha256 == AUTH_PRG_SHA256:
		return true
	if file_crc32 == ALT_AUTH_FILE_CRC32 or file_sha256 == ALT_AUTH_FILE_SHA256:
		return true
	return false


## Translates a CPU bus address ($8000-$FFFF) and bank index (0..6) to absolute PRG ROM offset (0..131071)
## $8000-$BFFF maps to switchable PRG banks 0..6
## $C000-$FFFF is fixed to Bank 7
## Returns -1 if address or bank is out of range.
func cpu_addr_to_prg_offset(cpu_addr: int, bank: int = 0) -> int:
	if cpu_addr >= 0xC000 and cpu_addr <= 0xFFFF:
		# Fixed Bank 7
		return (7 * PRG_BANK_SIZE) + (cpu_addr - 0xC000)
	elif cpu_addr >= 0x8000 and cpu_addr <= 0xBFFF:
		# Switchable Banks 0..6
		if bank < 0 or bank >= PRG_BANK_COUNT:
			return -1
		return (bank * PRG_BANK_SIZE) + (cpu_addr - 0x8000)
	return -1


## Reads an 8-bit unsigned byte from PRG ROM by CPU address and bank.
## Returns the byte value (0..255), or -1 if address or bank is invalid.
func read_cpu(cpu_addr: int, bank: int = 0) -> int:
	var offset: int = cpu_addr_to_prg_offset(cpu_addr, bank)
	if offset < 0 or offset >= prg_rom.size():
		return -1
	return prg_rom[offset]


## Reads a 16-bit little-endian unsigned word from PRG ROM by CPU address and bank.
## Returns the word value (0..65535), or -1 if address or bank is invalid.
func read_cpu_word(cpu_addr: int, bank: int = 0) -> int:
	var low: int = read_cpu(cpu_addr, bank)
	if low < 0:
		return -1
	var high: int = read_cpu(cpu_addr + 1, bank)
	if high < 0:
		return -1
	return (high << 8) | low


## Returns a 16 KB slice corresponding to a requested PRG bank (0..7).
## Returns an empty PackedByteArray if bank index is invalid.
func get_bank(bank: int) -> PackedByteArray:
	if bank < 0 or bank >= PRG_BANK_COUNT or prg_rom.size() < TOTAL_PRG_SIZE:
		return PackedByteArray()
	var start: int = bank * PRG_BANK_SIZE
	return prg_rom.slice(start, start + PRG_BANK_SIZE)


## Returns the complete 128 KB PRG ROM buffer.
func get_prg_rom() -> PackedByteArray:
	return prg_rom


## Returns the 16-byte iNES file header.
func get_header() -> PackedByteArray:
	return header


## Internal state reset
func _reset() -> void:
	raw_data = PackedByteArray()
	header = PackedByteArray()
	prg_rom = PackedByteArray()
	prg_banks = 0
	chr_banks = 0
	mapper = -1
	vertical_mirroring = false
	battery_ram = false
	has_trainer = false
	file_sha256 = ""
	file_crc32 = 0
	prg_sha256 = ""
	prg_crc32 = 0
	is_authentic = false

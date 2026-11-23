class_name TestRomLoader
extends RefCounted

## Modular Test Suite: ROM Loader & UNROM Mapper 2 Architecture (30 Tests)

const RomLoaderScript = preload("res://src/rom/rom_loader.gd")


static func run(runner: Object, loader: RefCounted, rom_path: String) -> bool:
	print("\n--- 1. ROM Loader & UNROM Mapper 2 Architecture ---")

	var err: Error = loader.load_from_file(rom_path)
	runner.assert_test("ROM File Read & Ingestion", err == OK, "FileAccess error code: %d" % err)
	if err != OK:
		return false

	runner.assert_test("Total File Size >= 131,088 bytes", loader.raw_data.size() >= 131088, "Size: %d" % loader.raw_data.size())
	runner.assert_test("Header Size == 16 bytes", loader.header.size() == 16, "Header size: %d" % loader.header.size())
	runner.assert_test("Header Magic 'NES\\x1A'", loader.header[0] == 0x4E and loader.header[1] == 0x45 and loader.header[2] == 0x53 and loader.header[3] == 0x1A)
	runner.assert_test("Mapper 2 (UNROM)", loader.mapper == 2, "Reported Mapper: %d" % loader.mapper)
	runner.assert_test("PRG ROM Banks == 8 (128 KB)", loader.prg_banks == 8, "PRG Banks: %d" % loader.prg_banks)
	runner.assert_test("CHR ROM Banks == 0 (Uses CHR RAM)", loader.chr_banks == 0, "CHR Banks: %d" % loader.chr_banks)
	runner.assert_test("PRG ROM Extracted Size == 131,072 bytes", loader.prg_rom.size() == 131072, "PRG ROM Size: %d" % loader.prg_rom.size())

	runner.assert_test("Authentic Reference ROM Flag", loader.is_authentic, "ROM checksums failed authenticity validation")
	runner.assert_test("File SHA-256 Verification", loader.file_sha256 == RomLoaderScript.AUTH_FILE_SHA256 or loader.file_sha256 == RomLoaderScript.ALT_AUTH_FILE_SHA256)
	runner.assert_test("File CRC-32 Verification", loader.file_crc32 == RomLoaderScript.AUTH_FILE_CRC32 or loader.file_crc32 == RomLoaderScript.ALT_AUTH_FILE_CRC32)
	runner.assert_test("PRG SHA-256 Verification", loader.prg_sha256 == RomLoaderScript.AUTH_PRG_SHA256)
	runner.assert_test("PRG CRC-32 Verification", loader.prg_crc32 == RomLoaderScript.AUTH_PRG_CRC32)

	# Fixed Bank 7 & Hardware Vectors
	runner.assert_test("Fixed Bank 7 at $C000 (when bank 0 requested)", loader.read_cpu(0xC000, 0) == 0x07)
	runner.assert_test("Fixed Bank 7 at $C000 (when bank 3 requested)", loader.read_cpu(0xC000, 3) == 0x07)
	runner.assert_test("Fixed Bank 7 at $C000 (when bank 6 requested)", loader.read_cpu(0xC000, 6) == 0x07)

	var nmi_vec: int = loader.read_cpu_word(0xFFFA, 7)
	var reset_vec: int = loader.read_cpu_word(0xFFFC, 7)
	var irq_vec: int = loader.read_cpu_word(0xFFFE, 7)
	runner.assert_test("NMI Vector Resolution ($FFFA == 0xC060)", nmi_vec == 0xC060, "Got: 0x%04X" % nmi_vec)
	runner.assert_test("Reset Vector Resolution ($FFFC == 0xC001)", reset_vec == 0xC001, "Got: 0x%04X" % reset_vec)
	runner.assert_test("IRQ Vector Resolution ($FFFE == 0xC0B5)", irq_vec == 0xC0B5, "Got: 0x%04X" % irq_vec)

	# Switchable Banks 0..6
	for b in range(7):
		runner.assert_test("Bank %d Marker at $8000 == 0x%02X" % [b, b], loader.read_cpu(0x8000, b) == b)

	runner.assert_test("Address below $8000 ($7FFF) returns -1", loader.read_cpu(0x7FFF, 0) == -1)
	runner.assert_test("Address above $FFFF ($10000) returns -1", loader.read_cpu(0x10000, 0) == -1)
	runner.assert_test("Negative Bank Index (-1) returns -1", loader.read_cpu(0x8000, -1) == -1)
	runner.assert_test("Out of bounds Bank Index (8) returns -1", loader.read_cpu(0x8000, 8) == -1)

	return true

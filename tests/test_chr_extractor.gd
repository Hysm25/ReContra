class_name TestChrExtractor
extends RefCounted

## Modular Test Suite: CHR Extractor & Pattern Table RLE Decompressor (16 Tests)

const ChrExtractorScript = preload("res://src/rom/chr_extractor.gd")


static func run(runner: Object, loader: RefCounted) -> bool:
	print("\n--- 2. CHR Extractor & RLE Pattern Table Decompressor ---")
	var chr_ram: PackedByteArray = ChrExtractorScript.allocate_chr_ram()
	var vram16k: PackedByteArray = ChrExtractorScript.allocate_ppu_vram()
	runner.assert_test("CHR-RAM Allocation == 8192 bytes", chr_ram.size() == 8192)
	runner.assert_test("Full PPU VRAM Allocation == 16384 bytes", vram16k.size() == 16384)

	# Verify bit reversal utility
	runner.assert_test("Bit Reversal (0x80 -> 0x01)", ChrExtractorScript.reverse_bits_u8(0x80) == 0x01)
	runner.assert_test("Bit Reversal (0xF0 -> 0x0F)", ChrExtractorScript.reverse_bits_u8(0xF0) == 0x0F)
	runner.assert_test("Bit Reversal (0xAA -> 0x55)", ChrExtractorScript.reverse_bits_u8(0xAA) == 0x55)

	# Test all 27 individual graphic data entries (0x00..0x1A)
	var all_entries_valid: bool = true
	var all_decompress_valid: bool = true
	for code in range(ChrExtractorScript.GRAPHIC_DATA_COUNT):
		var entry = ChrExtractorScript.get_graphic_entry(loader, code)
		if entry == null or entry.code != code or entry.bank < 1 or entry.bank > 7:
			all_entries_valid = false
			break

		vram16k.fill(0)
		var written: int = ChrExtractorScript.decompress_graphic_code(loader, code, vram16k)
		if written <= 0:
			all_decompress_valid = false
			break

		if code == 0x01:
			runner.assert_test("Graphic Code 0x01 Initial PPU Addr == 0x0CE0", entry.initial_ppu_addr == 0x0CE0)
			runner.assert_test("Graphic Code 0x01 Horizontal Flip == false", entry.horizontal_flip == false)
			runner.assert_test("Graphic Code 0x01 Decompress Size == 4768 bytes", written == 4768, "Got: %d" % written)
			chr_ram.fill(0)
			var chr_written: int = ChrExtractorScript.decompress_graphic_code(loader, code, chr_ram)
			runner.assert_test("Graphic Code 0x01 into 8KB CHR-RAM == 4768 bytes", chr_written == 4768)
		elif code == 0x10:
			runner.assert_test("Graphic Code 0x10 Initial PPU Addr == 0x1600", entry.initial_ppu_addr == 0x1600)
			runner.assert_test("Graphic Code 0x10 Horizontal Flip == true", entry.horizontal_flip == true)
			runner.assert_test("Graphic Code 0x10 Decompress Size == 1056 bytes", written == 1056, "Got: %d" % written)
			chr_ram.fill(0)
			var chr_written: int = ChrExtractorScript.decompress_graphic_code(loader, code, chr_ram)
			runner.assert_test("Graphic Code 0x10 into 8KB CHR-RAM == 1056 bytes", chr_written == 1056)

	runner.assert_test("All 27 Graphic Data Entries Valid (0x00..0x1A)", all_entries_valid)
	runner.assert_test("All 27 Graphic Codes Decompressed Successfully", all_decompress_valid)

	# Test all 13 Level Graphic Sets (0..12)
	var all_level_sets_valid: bool = true
	for set_idx in range(ChrExtractorScript.LEVEL_GRAPHIC_COUNT):
		var codes: PackedByteArray = ChrExtractorScript.get_level_graphic_codes(loader, set_idx)
		if codes.is_empty():
			all_level_sets_valid = false
			break
		chr_ram.fill(0)
		var total_w: int = ChrExtractorScript.load_level_graphics(loader, set_idx, chr_ram)
		if total_w <= 0:
			all_level_sets_valid = false
			break
	runner.assert_test("All 13 Level Graphic Sets Loaded Successfully (0..12)", all_level_sets_valid)

	return true

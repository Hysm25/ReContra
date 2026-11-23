extends SceneTree

## Headless test suite for RomLoader, ChrExtractor, and LevelLoader.
## Supports `--rom <path>` command-line option with automatic fallback discovery.

const RomLoaderScript = preload("res://scripts/rom/rom_loader.gd")
const ChrExtractorScript = preload("res://scripts/rom/chr_extractor.gd")
const LevelLoaderScript = preload("res://scripts/rom/level_loader.gd")

var _total_tests: int = 0
var _passed_tests: int = 0
var _failed_tests: int = 0


func _init() -> void:
	var success: bool = _run_test_suite()
	quit(0 if success else 1)


func _run_test_suite() -> bool:
	print("==================================================================")
	print("        RECONTRA HEADLESS VERIFICATION & TEST SUITE               ")
	print("==================================================================")

	var rom_path: String = _find_rom_path()
	if rom_path.is_empty():
		_log_failure("ROM Discovery", "No valid ROM file found. Pass with --rom <path>")
		_print_summary()
		return false

	print("Discovered ROM file: %s" % rom_path)

	var loader = RomLoaderScript.new()
	var err: Error = loader.load_from_file(rom_path)

	# --- PART 1: ROM LOADER TESTS ---
	print("\n--- 1. ROM Loader & UNROM Mapper 2 Architecture ---")
	_assert_test("ROM File Read & Ingestion", err == OK, "FileAccess error code: %d" % err)
	if err != OK:
		_print_summary()
		return false

	_assert_test("Total File Size >= 131,088 bytes", loader.raw_data.size() >= 131088, "Size: %d" % loader.raw_data.size())
	_assert_test("Header Size == 16 bytes", loader.header.size() == 16, "Header size: %d" % loader.header.size())
	_assert_test("Header Magic 'NES\\x1A'", loader.header[0] == 0x4E and loader.header[1] == 0x45 and loader.header[2] == 0x53 and loader.header[3] == 0x1A)
	_assert_test("Mapper 2 (UNROM)", loader.mapper == 2, "Reported Mapper: %d" % loader.mapper)
	_assert_test("PRG ROM Banks == 8 (128 KB)", loader.prg_banks == 8, "PRG Banks: %d" % loader.prg_banks)
	_assert_test("CHR ROM Banks == 0 (Uses CHR RAM)", loader.chr_banks == 0, "CHR Banks: %d" % loader.chr_banks)
	_assert_test("PRG ROM Extracted Size == 131,072 bytes", loader.prg_rom.size() == 131072, "PRG ROM Size: %d" % loader.prg_rom.size())

	_assert_test("Authentic Reference ROM Flag", loader.is_authentic, "ROM checksums failed authenticity validation")
	_assert_test("File SHA-256 Verification", loader.file_sha256 == RomLoaderScript.AUTH_FILE_SHA256 or loader.file_sha256 == RomLoaderScript.ALT_AUTH_FILE_SHA256)
	_assert_test("File CRC-32 Verification", loader.file_crc32 == RomLoaderScript.AUTH_FILE_CRC32 or loader.file_crc32 == RomLoaderScript.ALT_AUTH_FILE_CRC32)
	_assert_test("PRG SHA-256 Verification", loader.prg_sha256 == RomLoaderScript.AUTH_PRG_SHA256)
	_assert_test("PRG CRC-32 Verification", loader.prg_crc32 == RomLoaderScript.AUTH_PRG_CRC32)

	# Fixed Bank 7 & Hardware Vectors
	_assert_test("Fixed Bank 7 at $C000 (when bank 0 requested)", loader.read_cpu(0xC000, 0) == 0x07)
	_assert_test("Fixed Bank 7 at $C000 (when bank 3 requested)", loader.read_cpu(0xC000, 3) == 0x07)
	_assert_test("Fixed Bank 7 at $C000 (when bank 6 requested)", loader.read_cpu(0xC000, 6) == 0x07)

	var nmi_vec: int = loader.read_cpu_word(0xFFFA, 7)
	var reset_vec: int = loader.read_cpu_word(0xFFFC, 7)
	var irq_vec: int = loader.read_cpu_word(0xFFFE, 7)
	_assert_test("NMI Vector Resolution ($FFFA == 0xC060)", nmi_vec == 0xC060, "Got: 0x%04X" % nmi_vec)
	_assert_test("Reset Vector Resolution ($FFFC == 0xC001)", reset_vec == 0xC001, "Got: 0x%04X" % reset_vec)
	_assert_test("IRQ Vector Resolution ($FFFE == 0xC0B5)", irq_vec == 0xC0B5, "Got: 0x%04X" % irq_vec)

	# Switchable Banks 0..6
	for b in range(7):
		_assert_test("Bank %d Marker at $8000 == 0x%02X" % [b, b], loader.read_cpu(0x8000, b) == b)

	_assert_test("Address below $8000 ($7FFF) returns -1", loader.read_cpu(0x7FFF, 0) == -1)
	_assert_test("Address above $FFFF ($10000) returns -1", loader.read_cpu(0x10000, 0) == -1)
	_assert_test("Negative Bank Index (-1) returns -1", loader.read_cpu(0x8000, -1) == -1)
	_assert_test("Out of bounds Bank Index (8) returns -1", loader.read_cpu(0x8000, 8) == -1)

	# --- PART 2: CHR EXTRACTOR & RLE DECOMPRESSOR TESTS ---
	print("\n--- 2. CHR Extractor & RLE Pattern Table Decompressor ---")
	var chr_ram: PackedByteArray = ChrExtractorScript.allocate_chr_ram()
	var vram16k: PackedByteArray = ChrExtractorScript.allocate_ppu_vram()
	_assert_test("CHR-RAM Allocation == 8192 bytes", chr_ram.size() == 8192)
	_assert_test("Full PPU VRAM Allocation == 16384 bytes", vram16k.size() == 16384)

	# Verify bit reversal utility
	_assert_test("Bit Reversal (0x80 -> 0x01)", ChrExtractorScript.reverse_bits_u8(0x80) == 0x01)
	_assert_test("Bit Reversal (0xF0 -> 0x0F)", ChrExtractorScript.reverse_bits_u8(0xF0) == 0x0F)
	_assert_test("Bit Reversal (0xAA -> 0x55)", ChrExtractorScript.reverse_bits_u8(0xAA) == 0x55)

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
			_assert_test("Graphic Code 0x01 Initial PPU Addr == 0x0CE0", entry.initial_ppu_addr == 0x0CE0)
			_assert_test("Graphic Code 0x01 Horizontal Flip == false", entry.horizontal_flip == false)
			_assert_test("Graphic Code 0x01 Decompress Size == 4768 bytes", written == 4768, "Got: %d" % written)
			# Verify decompression into 8KB CHR-RAM buffer
			chr_ram.fill(0)
			var chr_written: int = ChrExtractorScript.decompress_graphic_code(loader, code, chr_ram)
			_assert_test("Graphic Code 0x01 into 8KB CHR-RAM == 4768 bytes", chr_written == 4768)
		elif code == 0x10:
			_assert_test("Graphic Code 0x10 Initial PPU Addr == 0x1600", entry.initial_ppu_addr == 0x1600)
			_assert_test("Graphic Code 0x10 Horizontal Flip == true", entry.horizontal_flip == true)
			_assert_test("Graphic Code 0x10 Decompress Size == 1056 bytes", written == 1056, "Got: %d" % written)
			chr_ram.fill(0)
			var chr_written: int = ChrExtractorScript.decompress_graphic_code(loader, code, chr_ram)
			_assert_test("Graphic Code 0x10 into 8KB CHR-RAM == 1056 bytes", chr_written == 1056)

	_assert_test("All 27 Graphic Data Entries Valid (0x00..0x1A)", all_entries_valid)
	_assert_test("All 27 Graphic Codes Decompressed Successfully", all_decompress_valid)

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
	_assert_test("All 13 Level Graphic Sets Loaded Successfully (0..12)", all_level_sets_valid)

	# --- PART 3: LEVEL LOADER, PALETTES & SUPERTILES TESTS ---
	print("\n--- 3. Level Loader, Supertiles & Palettes Subsystem ---")
	var all_headers_valid: bool = true
	for lvl in range(LevelLoaderScript.LEVEL_COUNT):
		var hdr = LevelLoaderScript.load_level_header(loader, lvl)
		if hdr == null or hdr.level_index != lvl:
			all_headers_valid = false
			break

		if lvl == 0:
			_assert_test("Stage 1 (Level 0): Outdoor Location (0)", hdr.location_type == 0)
			_assert_test("Stage 1 (Level 0): Horizontal Scrolling (0)", hdr.scrolling_type == 0)
			_assert_test("Stage 1 (Level 0): Supertile Pointer == 0x8001", hdr.supertile_ptr == 0x8001)
			_assert_test("Stage 1 (Level 0): Alt Graphics Pos == 11", hdr.alt_graphics_pos == 11)
		elif lvl == 1:
			_assert_test("Stage 2 (Level 1): Indoor Location (1)", hdr.location_type == 1)
			_assert_test("Stage 2 (Level 1): Alt Graphics Pos == 4", hdr.alt_graphics_pos == 4)
		elif lvl == 2:
			_assert_test("Stage 3 (Level 2): Outdoor Location (0)", hdr.location_type == 0)
			_assert_test("Stage 3 (Level 2): Vertical Scrolling (1)", hdr.scrolling_type == 1)
			_assert_test("Stage 3 (Level 2): Alt Graphics Pos == 7", hdr.alt_graphics_pos == 7)
		elif lvl == 3:
			_assert_test("Stage 4 (Level 3): Indoor Location (1)", hdr.location_type == 1)

		# Palette verification
		var pal_buf: PackedByteArray = LevelLoaderScript.load_palettes(loader, lvl)
		_assert_test("Stage %d Palette RAM Buffer Size == 32 bytes" % (lvl + 1), pal_buf.size() == 32)
		_assert_test("Stage %d Universal Background Color 0x0F at Index 0" % (lvl + 1), pal_buf[0] == 0x0F)
		_assert_test("Stage %d Universal Sprite Color 0x0F at Index 16" % (lvl + 1), pal_buf[16] == 0x0F)

		# RGBA8 palette conversion verification
		var rgba_pal: PackedInt64Array = LevelLoaderScript.load_palettes_rgba8(loader, lvl)
		_assert_test("Stage %d RGBA8 Palette Size == 32" % (lvl + 1), rgba_pal.size() == 32)
		_assert_test("Stage %d Universal BG RGBA8 == 0x000000FF (Black)" % (lvl + 1), rgba_pal[0] == 0x000000FF)

		var color_pal: PackedColorArray = LevelLoaderScript.load_palettes_colors(loader, lvl)
		_assert_test("Stage %d Color Objects Palette Size == 32" % (lvl + 1), color_pal.size() == 32)

	_assert_test("All 8 Level Headers Loaded Successfully (0..7)", all_headers_valid)

	# Supertile reading verification (Stage 1 / Level 0)
	var hdr0 = LevelLoaderScript.load_level_header(loader, 0)
	for st_id in range(4):
		var st_tiles: PackedByteArray = LevelLoaderScript.read_supertile(loader, hdr0.supertile_ptr, st_id)
		_assert_test("Supertile %d Size == 16 bytes (4x4 matrix)" % st_id, st_tiles.size() == 16)

	# 3-Case RLE Screen Supertile Decompression Verification (Stage 1 Screen 0)
	var scr0_st: PackedByteArray = LevelLoaderScript.decompress_screen_supertiles(loader, hdr0, 0)
	_assert_test("Stage 1 Screen 0 Decompressed Count == 56 Supertiles", scr0_st.size() == 56, "Got: %d" % scr0_st.size())
	_assert_test("Stage 1 Screen 0 Supertile 0 == 0x21", scr0_st[0] == 0x21, "Got: 0x%02X" % scr0_st[0])
	_assert_test("Stage 1 Screen 0 Supertile 1 == 0x20", scr0_st[1] == 0x20, "Got: 0x%02X" % scr0_st[1])
	_assert_test("Stage 1 Screen 0 Supertile 2 == 0x21", scr0_st[2] == 0x21, "Got: 0x%02X" % scr0_st[2])
	_assert_test("Stage 1 Screen 0 Supertile 3 == 0x2B", scr0_st[3] == 0x2B, "Got: 0x%02X" % scr0_st[3])

	# Row 3 repeat count zeroes (indices 25..31)
	var row3_zeroes_pass: bool = true
	for z in range(25, 32):
		if scr0_st[z] != 0x00:
			row3_zeroes_pass = false
			break
	_assert_test("Stage 1 Screen 0 Row 3 RLE Repeat Zeroes (25..31)", row3_zeroes_pass)

	# Row 6 water surface tiles (indices 48..51 == 0x10)
	var row6_water_pass: bool = true
	for w in range(48, 52):
		if scr0_st[w] != 0x10:
			row6_water_pass = false
			break
	_assert_test("Stage 1 Screen 0 Row 6 Water Surface Supertiles (48..51 == 0x10)", row6_water_pass)

	_print_summary()
	return _failed_tests == 0


func _find_rom_path() -> String:
	# 1. Check user command-line arguments: --rom <path> or --rom=<path>
	var args: PackedStringArray = OS.get_cmdline_args()
	for i in range(args.size()):
		var arg: String = args[i]
		if arg == "--rom" and i + 1 < args.size():
			return args[i + 1]
		elif arg.begins_with("--rom="):
			return arg.substr(6)

	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(user_args.size()):
		var arg: String = user_args[i]
		if arg == "--rom" and i + 1 < user_args.size():
			return user_args[i + 1]
		elif arg.begins_with("--rom="):
			return arg.substr(6)

	# 2. Check standard fallback filenames in working directory
	var candidates: Array[String] = [
		"Contra.nes",
		"contra.nes",
		"Contra (USA).nes",
		"roms/Contra.nes",
		"roms/contra.nes"
	]
	for candidate in candidates:
		if FileAccess.file_exists(candidate):
			return candidate

	return ""


func _assert_test(test_name: String, condition: bool, extra_info: String = "") -> void:
	_total_tests += 1
	if condition:
		_passed_tests += 1
		print("  [PASS] %s" % test_name)
	else:
		_failed_tests += 1
		var msg: String = "  [FAIL] %s" % test_name
		if not extra_info.is_empty():
			msg += " (%s)" % extra_info
		printerr(msg)


func _log_failure(test_name: String, reason: String) -> void:
	_total_tests += 1
	_failed_tests += 1
	printerr("  [FAIL] %s: %s" % [test_name, reason])


func _print_summary() -> void:
	print("==================================================================")
	print("TEST RESULTS: %d Total | %d Passed | %d Failed" % [_total_tests, _passed_tests, _failed_tests])
	print("STATUS: %s" % ("ALL TESTS PASSED" if _failed_tests == 0 else "FAILURES DETECTED"))
	print("==================================================================")

extends SceneTree

## Headless test suite for RomLoader and UNROM Mapper 2 ingestion.
## Supports `--rom <path>` command-line option with automatic fallback discovery.

const RomLoaderScript = preload("res://scripts/rom/rom_loader.gd")

var _total_tests: int = 0
var _passed_tests: int = 0
var _failed_tests: int = 0


func _init() -> void:
	var success: bool = _run_test_suite()
	quit(0 if success else 1)


func _run_test_suite() -> bool:
	print("==================================================================")
	print("                 ROM LOADER HEADLESS TEST SUITE                   ")
	print("==================================================================")

	var rom_path: String = _find_rom_path()
	if rom_path.is_empty():
		_log_failure("ROM Discovery", "No valid ROM file found. Pass with --rom <path>")
		_print_summary()
		return false

	print("Discovered ROM file: %s" % rom_path)

	var loader = RomLoaderScript.new()
	var err: Error = loader.load_from_file(rom_path)

	# Test 1: File Loading
	_assert_test("ROM File Read & Ingestion", err == OK, "FileAccess error code: %d" % err)
	if err != OK:
		_print_summary()
		return false

	# Test 2: File Size & Header Magic
	_assert_test("Total File Size >= 131,088 bytes", loader.raw_data.size() >= 131088, "Size: %d" % loader.raw_data.size())
	_assert_test("Header Size == 16 bytes", loader.header.size() == 16, "Header size: %d" % loader.header.size())
	_assert_test("Header Magic 'NES\\x1A'", loader.header[0] == 0x4E and loader.header[1] == 0x45 and loader.header[2] == 0x53 and loader.header[3] == 0x1A)

	# Test 3: UNROM Architecture Constraints
	_assert_test("Mapper 2 (UNROM)", loader.mapper == 2, "Reported Mapper: %d" % loader.mapper)
	_assert_test("PRG ROM Banks == 8 (128 KB)", loader.prg_banks == 8, "PRG Banks: %d" % loader.prg_banks)
	_assert_test("CHR ROM Banks == 0 (Uses CHR RAM)", loader.chr_banks == 0, "CHR Banks: %d" % loader.chr_banks)
	_assert_test("PRG ROM Extracted Size == 131,072 bytes", loader.prg_rom.size() == 131072, "PRG ROM Size: %d" % loader.prg_rom.size())

	# Test 4: Cryptographic Checksums Verification
	print("\n--- Cryptographic Hashes ---")
	print("File SHA-256: %s" % loader.file_sha256)
	print("File CRC-32:  0x%08X" % loader.file_crc32)
	print("PRG  SHA-256: %s" % loader.prg_sha256)
	print("PRG  CRC-32:  0x%08X" % loader.prg_crc32)

	_assert_test("Authentic Reference ROM Flag", loader.is_authentic, "ROM checksums failed authenticity validation")
	_assert_test("File SHA-256 Verification", loader.file_sha256 == RomLoaderScript.AUTH_FILE_SHA256 or loader.file_sha256 == RomLoaderScript.ALT_AUTH_FILE_SHA256)
	_assert_test("File CRC-32 Verification", loader.file_crc32 == RomLoaderScript.AUTH_FILE_CRC32 or loader.file_crc32 == RomLoaderScript.ALT_AUTH_FILE_CRC32)
	_assert_test("PRG SHA-256 Verification", loader.prg_sha256 == RomLoaderScript.AUTH_PRG_SHA256)
	_assert_test("PRG CRC-32 Verification", loader.prg_crc32 == RomLoaderScript.AUTH_PRG_CRC32)

	# Test 5: Bank 7 Fixed Memory Mapping ($C000-$FFFF)
	print("\n--- CPU Bus Mapping: Bank 7 Fixed ($C000-$FFFF) ---")
	var bank7_marker_bank0: int = loader.read_cpu(0xC000, 0)
	var bank7_marker_bank3: int = loader.read_cpu(0xC000, 3)
	var bank7_marker_bank6: int = loader.read_cpu(0xC000, 6)
	_assert_test("Fixed Bank 7 at $C000 (when bank 0 requested)", bank7_marker_bank0 == 0x07, "Got: 0x%02X" % bank7_marker_bank0)
	_assert_test("Fixed Bank 7 at $C000 (when bank 3 requested)", bank7_marker_bank3 == 0x07, "Got: 0x%02X" % bank7_marker_bank3)
	_assert_test("Fixed Bank 7 at $C000 (when bank 6 requested)", bank7_marker_bank6 == 0x07, "Got: 0x%02X" % bank7_marker_bank6)

	# Hardware Interrupt Vectors at $FFFA-$FFFF
	var nmi_vec: int = loader.read_cpu_word(0xFFFA, 7)
	var reset_vec: int = loader.read_cpu_word(0xFFFC, 7)
	var irq_vec: int = loader.read_cpu_word(0xFFFE, 7)
	print("NMI Vector:   $FFFA -> 0x%04X (Expected: 0xC060)" % nmi_vec)
	print("Reset Vector: $FFFC -> 0x%04X (Expected: 0xC001)" % reset_vec)
	print("IRQ Vector:   $FFFE -> 0x%04X (Expected: 0xC0B5)" % irq_vec)
	_assert_test("NMI Vector Resolution ($FFFA == 0xC060)", nmi_vec == 0xC060, "Got: 0x%04X" % nmi_vec)
	_assert_test("Reset Vector Resolution ($FFFC == 0xC001)", reset_vec == 0xC001, "Got: 0x%04X" % reset_vec)
	_assert_test("IRQ Vector Resolution ($FFFE == 0xC0B5)", irq_vec == 0xC0B5, "Got: 0x%04X" % irq_vec)

	# Test 6: Switchable Banks 0..6 Memory Mapping ($8000-$BFFF)
	print("\n--- CPU Bus Mapping: Switchable Banks 0..6 ($8000-$BFFF) ---")
	for b in range(7):
		var marker: int = loader.read_cpu(0x8000, b)
		_assert_test("Bank %d Marker at $8000 == 0x%02X" % [b, b], marker == b, "Got: 0x%02X" % marker)

	# Verify distinct data between banks
	var bank0_slice: PackedByteArray = loader.get_bank(0)
	var bank1_slice: PackedByteArray = loader.get_bank(1)
	_assert_test("Bank 0 Slice Size == 16,384 bytes", bank0_slice.size() == 16384)
	_assert_test("Bank 1 Slice Size == 16,384 bytes", bank1_slice.size() == 16384)
	_assert_test("Bank 0 != Bank 1 Data", bank0_slice != bank1_slice)

	# Test 7: Address Boundary Checks & Error Handling
	print("\n--- Boundary Checks & Error Handling ---")
	_assert_test("Address below $8000 ($7FFF) returns -1", loader.read_cpu(0x7FFF, 0) == -1)
	_assert_test("Address above $FFFF ($10000) returns -1", loader.read_cpu(0x10000, 0) == -1)
	_assert_test("Negative Bank Index (-1) returns -1", loader.read_cpu(0x8000, -1) == -1)
	_assert_test("Out of bounds Bank Index (8) returns -1", loader.read_cpu(0x8000, 8) == -1)
	_assert_test("Word Read across $7FFF boundary returns -1", loader.read_cpu_word(0x7FFF, 0) == -1)
	_assert_test("Word Read at $FFFF returns -1 (high byte at $10000)", loader.read_cpu_word(0xFFFF, 7) == -1)

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

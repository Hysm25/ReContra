extends SceneTree

## Unified Headless Verification & Test Suite Runner
## Orchestrates modular test suites under `tests/`:
##   - test_rom_loader.gd: ROM Loader & UNROM Mapper 2 Architecture (30 tests)
##   - test_chr_extractor.gd: CHR Extractor & RLE Pattern Table Decompressor (16 tests)
##   - test_level_loader.gd: Level Loader, Palettes & Supertiles (70 tests)
##   - test_ppu_renderer.gd: 2C02 PPU Software Framebuffer & OAM Sprite Engine (20 tests)
##   - test_apu_sound.gd: Ricoh 2A03 APU Synthesizer & 6-Slot Audio Engine (23 tests)
##   - test_gameplay_simulation.gd: Gameplay Physics, Bullet Pool & GameLoop Simulation (31 tests)

const RomLoaderScript = preload("res://src/rom/rom_loader.gd")
const TestRomLoader = preload("res://tests/test_rom_loader.gd")
const TestChrExtractor = preload("res://tests/test_chr_extractor.gd")
const TestLevelLoader = preload("res://tests/test_level_loader.gd")
const TestPpuRenderer = preload("res://tests/test_ppu_renderer.gd")
const TestApuSound = preload("res://tests/test_apu_sound.gd")
const TestGameplaySimulation = preload("res://tests/test_gameplay_simulation.gd")

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
		log_failure("ROM Discovery", "No valid ROM file found. Pass with --rom <path>")
		_print_summary()
		return false

	print("Discovered ROM file: %s" % rom_path)

	var loader = RomLoaderScript.new()

	# Suite 1: ROM Loader
	var suite1_ok: bool = TestRomLoader.run(self, loader, rom_path)
	if not suite1_ok:
		_print_summary()
		return false

	# Suite 2: CHR Extractor & RLE Pattern Table Decompressor
	TestChrExtractor.run(self, loader)

	# Suite 3: Level Loader, Supertiles & Palettes Subsystem
	TestLevelLoader.run(self, loader)

	# Suite 4: 2C02 PPU Software Framebuffer & OAM Sprite Engine
	TestPpuRenderer.run(self, loader)

	# Suite 5: Ricoh 2A03 APU Synthesizer & 6-Slot Audio Engine
	TestApuSound.run(self, loader)

	# Suite 6: Gameplay Physics, Bullet Pool & GameLoop Simulation
	TestGameplaySimulation.run(self, loader)

	_print_summary()
	return _failed_tests == 0


func assert_test(test_name: String, condition: bool, extra_info: String = "") -> void:
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


func log_failure(test_name: String, reason: String) -> void:
	_total_tests += 1
	_failed_tests += 1
	printerr("  [FAIL] %s: %s" % [test_name, reason])


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

	# 2. Check standard fallback filenames in working directory and subdirectories
	var candidates: Array[String] = [
		"Contra.nes",
		"contra.nes",
		"Contra (USA).nes",
		"roms/Contra.nes",
		"roms/contra.nes",
		"src/Contra.nes"
	]
	for candidate in candidates:
		if FileAccess.file_exists(candidate):
			return candidate

	return ""


func _print_summary() -> void:
	print("==================================================================")
	print("TEST RESULTS: %d Total | %d Passed | %d Failed" % [_total_tests, _passed_tests, _failed_tests])
	print("STATUS: %s" % ("ALL TESTS PASSED" if _failed_tests == 0 else "FAILURES DETECTED"))
	print("==================================================================")

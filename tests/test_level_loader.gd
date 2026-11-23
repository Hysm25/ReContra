class_name TestLevelLoader
extends RefCounted

## Modular Test Suite: Level Loader, Palettes & Supertiles (70 Tests)

const LevelLoaderScript = preload("res://src/rom/level_loader.gd")


static func run(runner: Object, loader: RefCounted) -> bool:
	print("\n--- 3. Level Loader, Supertiles & Palettes Subsystem ---")
	var all_headers_valid: bool = true
	for lvl in range(LevelLoaderScript.LEVEL_COUNT):
		var hdr = LevelLoaderScript.load_level_header(loader, lvl)
		if hdr == null or hdr.level_index != lvl:
			all_headers_valid = false
			break

		if lvl == 0:
			runner.assert_test("Stage 1 (Level 0): Outdoor Location (0)", hdr.location_type == 0)
			runner.assert_test("Stage 1 (Level 0): Horizontal Scrolling (0)", hdr.scrolling_type == 0)
			runner.assert_test("Stage 1 (Level 0): Supertile Pointer == 0x8001", hdr.supertile_ptr == 0x8001)
			runner.assert_test("Stage 1 (Level 0): Alt Graphics Pos == 11", hdr.alt_graphics_pos == 11)
		elif lvl == 1:
			runner.assert_test("Stage 2 (Level 1): Indoor Location (1)", hdr.location_type == 1)
			runner.assert_test("Stage 2 (Level 1): Alt Graphics Pos == 4", hdr.alt_graphics_pos == 4)
		elif lvl == 2:
			runner.assert_test("Stage 3 (Level 2): Outdoor Location (0)", hdr.location_type == 0)
			runner.assert_test("Stage 3 (Level 2): Vertical Scrolling (1)", hdr.scrolling_type == 1)
			runner.assert_test("Stage 3 (Level 2): Alt Graphics Pos == 7", hdr.alt_graphics_pos == 7)
		elif lvl == 3:
			runner.assert_test("Stage 4 (Level 3): Indoor Location (1)", hdr.location_type == 1)

		# Palette verification (6 tests per level * 8 levels = 48 tests)
		var pal_buf: PackedByteArray = LevelLoaderScript.load_palettes(loader, lvl)
		runner.assert_test("Stage %d Palette RAM Buffer Size == 32 bytes" % (lvl + 1), pal_buf.size() == 32)
		runner.assert_test("Stage %d Universal Background Color 0x0F at Index 0" % (lvl + 1), pal_buf[0] == 0x0F)
		runner.assert_test("Stage %d Universal Sprite Color 0x0F at Index 16" % (lvl + 1), pal_buf[16] == 0x0F)

		var rgba_pal: PackedInt64Array = LevelLoaderScript.load_palettes_rgba8(loader, lvl)
		runner.assert_test("Stage %d RGBA8 Palette Size == 32" % (lvl + 1), rgba_pal.size() == 32)
		runner.assert_test("Stage %d Universal BG RGBA8 == 0x000000FF (Black)" % (lvl + 1), rgba_pal[0] == 0x000000FF)

		var color_pal: PackedColorArray = LevelLoaderScript.load_palettes_colors(loader, lvl)
		runner.assert_test("Stage %d Color Objects Palette Size == 32" % (lvl + 1), color_pal.size() == 32)

	runner.assert_test("All 8 Level Headers Loaded Successfully (0..7)", all_headers_valid)

	# Supertile reading verification (Stage 1 / Level 0)
	var hdr0 = LevelLoaderScript.load_level_header(loader, 0)
	for st_id in range(4):
		var st_tiles: PackedByteArray = LevelLoaderScript.read_supertile(loader, hdr0.supertile_ptr, st_id)
		runner.assert_test("Supertile %d Size == 16 bytes (4x4 matrix)" % st_id, st_tiles.size() == 16)

	# 3-Case RLE Screen Supertile Decompression Verification (Stage 1 Screen 0)
	var scr0_st: PackedByteArray = LevelLoaderScript.decompress_screen_supertiles(loader, hdr0, 0)
	runner.assert_test("Stage 1 Screen 0 Decompressed Count == 56 Supertiles", scr0_st.size() == 56, "Got: %d" % scr0_st.size())
	runner.assert_test("Stage 1 Screen 0 Supertile 0 == 0x21", scr0_st[0] == 0x21, "Got: 0x%02X" % scr0_st[0])
	runner.assert_test("Stage 1 Screen 0 Supertile 1 == 0x20", scr0_st[1] == 0x20, "Got: 0x%02X" % scr0_st[1])
	runner.assert_test("Stage 1 Screen 0 Supertile 2 == 0x21", scr0_st[2] == 0x21, "Got: 0x%02X" % scr0_st[2])
	runner.assert_test("Stage 1 Screen 0 Supertile 3 == 0x2B", scr0_st[3] == 0x2B, "Got: 0x%02X" % scr0_st[3])

	# Row 3 repeat count zeroes (indices 25..31)
	var row3_zeroes_pass: bool = true
	for z in range(25, 32):
		if scr0_st[z] != 0x00:
			row3_zeroes_pass = false
			break
	runner.assert_test("Stage 1 Screen 0 Row 3 RLE Repeat Zeroes (25..31)", row3_zeroes_pass)

	# Row 6 water surface tiles (indices 48..51 == 0x10)
	var row6_water_pass: bool = true
	for w in range(48, 52):
		if scr0_st[w] != 0x10:
			row6_water_pass = false
			break
	runner.assert_test("Stage 1 Screen 0 Row 6 Water Surface Supertiles (48..51 == 0x10)", row6_water_pass)

	return true

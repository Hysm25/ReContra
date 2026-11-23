extends SceneTree

## Headless test suite for RomLoader, ChrExtractor, and LevelLoader.
## Supports `--rom <path>` command-line option with automatic fallback discovery.

const RomLoaderScript = preload("res://scripts/rom/rom_loader.gd")
const ChrExtractorScript = preload("res://scripts/rom/chr_extractor.gd")
const LevelLoaderScript = preload("res://scripts/rom/level_loader.gd")
const PpuRendererScript = preload("res://scripts/render/ppu_renderer.gd")
const ApuSynthesizerScript = preload("res://scripts/audio/apu_synthesizer.gd")
const SoundEngineScript = preload("res://scripts/audio/sound_engine.gd")

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

	# --- PART 4: 2C02 PPU SOFTWARE FRAMEBUFFER & OAM SPRITE ENGINE TESTS ---
	print("\n--- 4. 2C02 PPU Software Framebuffer & OAM Sprite Engine ---")
	var ppu = PpuRendererScript.new()

	# VRAM & Palette RAM Mirroring
	ppu.write_vram(0x3F00, 0x1A)
	_assert_test("Palette Read $3F00 == 0x1A", ppu.read_vram(0x3F00) == 0x1A)
	_assert_test("Palette Mirror $3F10 -> $3F00", ppu.read_vram(0x3F10) == 0x1A)
	_assert_test("Palette Mirror $3F20 -> $3F00", ppu.read_vram(0x3F20) == 0x1A)

	ppu.set_mirroring(PpuRendererScript.MIRROR_VERTICAL)
	ppu.write_vram(0x2005, 0x42)
	_assert_test("Vertical Mirroring NT0 -> NT2 ($2005 -> $2805)", ppu.read_vram(0x2805) == 0x42)

	ppu.set_mirroring(PpuRendererScript.MIRROR_HORIZONTAL)
	ppu.write_vram(0x200A, 0x77)
	_assert_test("Horizontal Mirroring NT0 -> NT1 ($200A -> $240A)", ppu.read_vram(0x240A) == 0x77)

	# Background Rendering with Stage 1 Graphics & Palettes
	ppu.reset()
	ppu.set_mirroring(PpuRendererScript.MIRROR_VERTICAL)
	ChrExtractorScript.load_level_graphics(loader, 0, ppu.vram)

	var lvl1_hdr = LevelLoaderScript.load_level_header(loader, 0)
	var lvl1_pal = LevelLoaderScript.load_palettes(loader, 0)
	ppu.load_palettes(lvl1_pal)

	var ok_nt0: bool = ppu.unpack_screen_horizontal(0, loader, lvl1_hdr, 0)
	var ok_nt1: bool = ppu.unpack_screen_horizontal(1, loader, lvl1_hdr, 1)
	_assert_test("Unpack Screen 0 into NT0 ($2000)", ok_nt0)
	_assert_test("Unpack Screen 1 into NT1 ($2400)", ok_nt1)

	ppu.render_frame()

	var active_colored_pixels: int = 0
	var fb: PackedByteArray = ppu.get_framebuffer()
	for i in range(256 * 240):
		if fb[i * 4] != 0 or fb[i * 4 + 1] != 0 or fb[i * 4 + 2] != 0:
			active_colored_pixels += 1
	_assert_test("Stage 1 Background Active Colored Pixels > 10,000", active_colored_pixels > 10000, "Active: %d" % active_colored_pixels)

	# 8x16 OAM Sprite Rendering & Flip Flags
	ppu.oam[0] = 64
	ppu.oam[1] = 0x00
	ppu.oam[2] = 0x00  # Normal
	ppu.oam[3] = 64

	ppu.oam[4] = 64
	ppu.oam[5] = 0x00
	ppu.oam[6] = 0x40  # H-Flip
	ppu.oam[7] = 80

	ppu.oam[8] = 64
	ppu.oam[9] = 0x00
	ppu.oam[10] = 0x80 # V-Flip
	ppu.oam[11] = 96

	ppu.oam[12] = 64
	ppu.oam[13] = 0x00
	ppu.oam[14] = 0x20 # Priority Behind BG
	ppu.oam[15] = 112

	ppu.render_frame()
	_assert_test("Rendered Frame with 8x16 OAM Sprites & Flip Flags", ppu.frame_count >= 2)

	# 8-Sprite per scanline limit & authentic $4C cyclic priority shift
	for s in range(12):
		ppu.oam[s * 4] = 100
		ppu.oam[s * 4 + 1] = 0x02
		ppu.oam[s * 4 + 2] = 0x00
		ppu.oam[s * 4 + 3] = s * 10

	ppu.flicker_free_sprites = false
	var pre_shift: int = ppu.oam_shift_offset
	ppu.render_frame()
	var expected_shift: int = (pre_shift + PpuRendererScript.AUTHENTIC_CYCLIC_SHIFT) & 0xFF
	_assert_test("Authentic Cyclic Priority Offset Advance ($4C)", ppu.oam_shift_offset == expected_shift)

	# Flicker-free unlimited sprite mode
	ppu.flicker_free_sprites = true
	ppu.render_frame()
	_assert_test("Flicker-Free Mode Frame Rendered", ppu.frame_count >= 4)

	# Dual-Nametable Horizontal Scrolling & Deterministic Framebuffer CRC-32
	ppu.scroll_x = 128
	ppu.render_frame()

	var fb_crc: int = RomLoaderScript.compute_crc32(ppu.framebuffer)
	print("Rendered Framebuffer Deterministic CRC-32: 0x%08X" % fb_crc)
	_assert_test("Deterministic Framebuffer CRC-32 Non-Zero", fb_crc != 0)
	_assert_test("Deterministic Framebuffer CRC-32 Match (0x820ABB35)", fb_crc == 0x820ABB35, "Got: 0x%08X" % fb_crc)

	# Godot Image and ImageTexture Conversion
	var fb_img: Image = ppu.get_framebuffer_image()
	_assert_test("Image Dimensions 256x240", fb_img.get_width() == 256 and fb_img.get_height() == 240)
	_assert_test("Image Format RGBA8", fb_img.get_format() == Image.FORMAT_RGBA8)

	var fb_tex: ImageTexture = ppu.get_framebuffer_texture()
	_assert_test("ImageTexture Dimensions 256x240", fb_tex.get_width() == 256 and fb_tex.get_height() == 240)

	# Corridor perspective unpacking
	var ok_corridor: bool = ppu.unpack_corridor_perspective(0)
	_assert_test("Corridor Perspective Nametable Unpack", ok_corridor)

	# --- PART 5: RICOH 2A03 APU SYNTHESIZER & 6-SLOT AUDIO ENGINE ---
	print("\n--- 5. Ricoh 2A03 APU Synthesizer & 6-Slot Audio Engine ---")
	var apu = ApuSynthesizerScript.new()
	_assert_test("APU Initialized at 48000 Hz", apu.sample_rate == 48000)

	# 1. Pulse 1 Channel Tone Generation
	apu.write_register(ApuSynthesizerScript.APU_REG_STATUS, 0x01) # Enable Pulse 1
	apu.write_register(ApuSynthesizerScript.APU_REG_PULSE1_CTRL, 0xB8) # Duty 50% (2), constant vol 8
	apu.write_register(ApuSynthesizerScript.APU_REG_PULSE1_TIMER_LO, 0xCF)
	apu.write_register(ApuSynthesizerScript.APU_REG_PULSE1_TIMER_HI, 0x02) # Period = 0x02CF (~155 Hz, D#3)

	var pulse_samples: PackedFloat32Array = apu.generate_samples_float(800)
	var pulse_energy: float = 0.0
	for s in pulse_samples:
		pulse_energy += s * s
	print("  Pulse 1 Tone Energy: %f" % pulse_energy)
	_assert_test("Pulse 1 Non-Silent Tone Generation", pulse_energy > 0.05, "Energy: %f" % pulse_energy)

	# 2. Triangle Channel Tone Generation
	apu.reset()
	apu.write_register(ApuSynthesizerScript.APU_REG_STATUS, 0x04) # Enable Triangle
	apu.write_register(ApuSynthesizerScript.APU_REG_TRI_CTRL, 0xFF) # Linear counter reload = 127
	apu.write_register(ApuSynthesizerScript.APU_REG_TRI_TIMER_LO, 0xCF)
	apu.write_register(ApuSynthesizerScript.APU_REG_TRI_TIMER_HI, 0x01) # Period = 0x01CF

	var tri_samples: PackedFloat32Array = apu.generate_samples_float(800)
	var tri_energy: float = 0.0
	for s in tri_samples:
		tri_energy += s * s
	print("  Triangle Tone Energy: %f" % tri_energy)
	_assert_test("Triangle Non-Silent Tone Generation", tri_energy > 0.05, "Energy: %f" % tri_energy)

	# 3. Noise Channel Tone Generation
	apu.reset()
	apu.write_register(ApuSynthesizerScript.APU_REG_STATUS, 0x08) # Enable Noise
	apu.write_register(ApuSynthesizerScript.APU_REG_NOISE_CTRL, 0x3A) # Constant vol 10
	apu.write_register(ApuSynthesizerScript.APU_REG_NOISE_PERIOD, 0x04) # Period index 4
	apu.write_register(ApuSynthesizerScript.APU_REG_NOISE_LENGTH, 0x08) # Length counter

	var noise_samples: PackedFloat32Array = apu.generate_samples_float(800)
	var noise_energy: float = 0.0
	for s in noise_samples:
		noise_energy += s * s
	print("  Noise Tone Energy: %f" % noise_energy)
	_assert_test("Noise Non-Silent Waveform Generation", noise_energy > 0.05, "Energy: %f" % noise_energy)

	# 4. DPCM Sample Extraction & DMC Playback
	apu.reset()
	var bank7_prg: PackedByteArray = loader.get_bank(7)
	apu.set_dmc_memory(bank7_prg)

	var sound_engine = SoundEngineScript.new()
	var engine_ok: bool = sound_engine.init_engine(loader)
	_assert_test("Sound Engine Initialized with ROM", engine_ok)

	var play_dmc_ok: bool = sound_engine.play_sound(apu, 0x5B) # Snare drum sample
	_assert_test("Trigger DPCM Percussion 0x5B", play_dmc_ok)
	_assert_test("DMC Channel Enabled", apu.dmc.enabled)
	_assert_test("DPCM Sample 0x5B Byte Length == 593", apu.dmc.bytes_remaining == 593, "Got: %d" % apu.dmc.bytes_remaining)

	var dmc_samples: PackedFloat32Array = apu.generate_samples_float(800)
	var dmc_energy: float = 0.0
	for s in dmc_samples:
		dmc_energy += s * s
	print("  DMC Playback Energy: %f (remaining bytes: %d)" % [dmc_energy, apu.dmc.bytes_remaining])
	_assert_test("DMC Sample Playback Audio Energy", dmc_energy > 0.01, "Energy: %f" % dmc_energy)
	_assert_test("DMC Bytes Remaining Decreased", apu.dmc.bytes_remaining < 593, "Remaining: %d" % apu.dmc.bytes_remaining)

	# 5. Sound Engine Bytecode Execution: Stage 1 Jungle BGM (Sound 0x2A)
	apu.reset()
	apu.set_dmc_memory(bank7_prg)
	sound_engine.reset_engine()

	var bgm_ok: bool = sound_engine.play_sound(apu, 0x2A)
	_assert_test("Trigger Stage 1 BGM 0x2A", bgm_ok)
	_assert_test("Slot 0 BGM Pulse 1 Assigned", sound_engine.slots[SoundEngineScript.SOUND_SLOT_BGM_PULSE1].sound_code == 0x2A)
	_assert_test("Slot 1 BGM Pulse 2 Assigned", sound_engine.slots[SoundEngineScript.SOUND_SLOT_BGM_PULSE2].sound_code == 0x2A)
	_assert_test("Slot 2 BGM Triangle Assigned", sound_engine.slots[SoundEngineScript.SOUND_SLOT_BGM_TRI].sound_code == 0x2A)
	_assert_test("Slot 3 BGM Percussion Assigned", sound_engine.slots[SoundEngineScript.SOUND_SLOT_BGM_PERC].sound_code == 0x2A)

	# Simulate 120 frames (~2 seconds) of BGM playback
	var total_bgm_energy: float = 0.0
	for _f in range(120):
		sound_engine.update_frame(apu)
		var fbuf: PackedFloat32Array = apu.generate_samples_float(799)
		for s in fbuf:
			total_bgm_energy += s * s

	print("  Stage 1 BGM (120 frames) Total Synthesized Energy: %f" % total_bgm_energy)
	_assert_test("BGM Substantial Audio Energy Across 120 Frames", total_bgm_energy > 10.0, "Energy: %f" % total_bgm_energy)

	# 6. Slot Priority Arbitration: SFX Slot 4 over BGM Slot 0
	var sfx_ok: bool = sound_engine.play_sound(apu, 0x0A) # Weapon SFX
	_assert_test("Trigger SFX 0x0A on Slot 4", sfx_ok)
	_assert_test("Slot 4 Active with SFX 0x0A", sound_engine.slots[SoundEngineScript.SOUND_SLOT_SFX_PULSE1].sound_code == 0x0A)

	sound_engine.update_frame(apu)
	_assert_test("Slot 4 Remains Active During Execution", sound_engine.slots[SoundEngineScript.SOUND_SLOT_SFX_PULSE1].sound_code == 0x0A)

	# 7. AudioStreamGenerator Stereo Vector2 Format
	var stereo_frames: PackedVector2Array = apu.generate_samples(100)
	_assert_test("AudioStreamGenerator Frame Count == 100", stereo_frames.size() == 100)
	_assert_test("Stereo Balanced Channels (L == R)", stereo_frames[0].x == stereo_frames[0].y)

	# 8. Deterministic Audio Simulation Hash Test
	var crc_run1: int = 0
	var crc_run2: int = 0

	# Run 1
	var apu1 = ApuSynthesizerScript.new()
	apu1.set_dmc_memory(bank7_prg)
	var eng1 = SoundEngineScript.new()
	eng1.init_engine(loader)
	eng1.play_sound(apu1, 0x2A)

	var run1_floats: PackedFloat32Array = PackedFloat32Array()
	run1_floats.resize(60 * 799)
	var offset1: int = 0
	for _f in range(60):
		eng1.update_frame(apu1)
		var chunk: PackedFloat32Array = apu1.generate_samples_float(799)
		for i in range(799):
			run1_floats[offset1 + i] = chunk[i]
		offset1 += 799
	crc_run1 = RomLoaderScript.compute_crc32(run1_floats.to_byte_array())

	# Run 2
	var apu2 = ApuSynthesizerScript.new()
	apu2.set_dmc_memory(bank7_prg)
	var eng2 = SoundEngineScript.new()
	eng2.init_engine(loader)
	eng2.play_sound(apu2, 0x2A)

	var run2_floats: PackedFloat32Array = PackedFloat32Array()
	run2_floats.resize(60 * 799)
	var offset2: int = 0
	for _f in range(60):
		eng2.update_frame(apu2)
		var chunk: PackedFloat32Array = apu2.generate_samples_float(799)
		for i in range(799):
			run2_floats[offset2 + i] = chunk[i]
		offset2 += 799
	crc_run2 = RomLoaderScript.compute_crc32(run2_floats.to_byte_array())

	print("  Audio Determinism Check: Run 1 CRC=0x%08X, Run 2 CRC=0x%08X" % [crc_run1, crc_run2])
	_assert_test("Audio Simulation Deterministic Checksum Match", crc_run1 == crc_run2)
	_assert_test("Audio Simulation Checksum Non-Zero", crc_run1 != 0)

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

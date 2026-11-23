class_name TestPpuRenderer
extends RefCounted

## Modular Test Suite: 2C02 PPU Software Framebuffer & OAM Sprite Engine (20 Tests)

const PpuRendererScript = preload("res://src/render/ppu_renderer.gd")
const LevelLoaderScript = preload("res://src/rom/level_loader.gd")
const ChrExtractorScript = preload("res://src/rom/chr_extractor.gd")
const RomLoaderScript = preload("res://src/rom/rom_loader.gd")


static func run(runner: Object, loader: RefCounted) -> bool:
	print("\n--- 4. 2C02 PPU Software Framebuffer & OAM Sprite Engine ---")
	var ppu = PpuRendererScript.new()

	# VRAM & Palette RAM Mirroring
	ppu.write_vram(0x3F00, 0x1A)
	runner.assert_test("Palette Read $3F00 == 0x1A", ppu.read_vram(0x3F00) == 0x1A)
	runner.assert_test("Palette Mirror $3F10 -> $3F00", ppu.read_vram(0x3F10) == 0x1A)
	runner.assert_test("Palette Mirror $3F20 -> $3F00", ppu.read_vram(0x3F20) == 0x1A)

	ppu.set_mirroring(PpuRendererScript.MIRROR_VERTICAL)
	ppu.write_vram(0x2005, 0x42)
	runner.assert_test("Vertical Mirroring NT0 -> NT2 ($2005 -> $2805)", ppu.read_vram(0x2805) == 0x42)

	ppu.set_mirroring(PpuRendererScript.MIRROR_HORIZONTAL)
	ppu.write_vram(0x200A, 0x77)
	runner.assert_test("Horizontal Mirroring NT0 -> NT1 ($200A -> $240A)", ppu.read_vram(0x240A) == 0x77)

	# Background Rendering with Stage 1 Graphics & Palettes
	ppu.reset()
	ppu.set_mirroring(PpuRendererScript.MIRROR_VERTICAL)
	ChrExtractorScript.load_level_graphics(loader, 0, ppu.vram)

	var lvl1_hdr = LevelLoaderScript.load_level_header(loader, 0)
	var lvl1_pal = LevelLoaderScript.load_palettes(loader, 0)
	ppu.load_palettes(lvl1_pal)
	runner.assert_test("Background Uses Pattern Table 1 ($1000)", (ppu.ctrl & PpuRendererScript.PPUCTRL_BG_TABLE_1000) != 0)
	runner.assert_test("Stage 1 Sprite Palette 0 (Player 1 Skin/Blue) Loaded", ppu.read_vram(0x3F11) == 0x37 and ppu.read_vram(0x3F12) == 0x12)
	runner.assert_test("Stage 1 Sprite Palette 1 (Player 2 Skin/Red) Loaded", ppu.read_vram(0x3F15) == 0x36 and ppu.read_vram(0x3F16) == 0x16)

	var ok_nt0: bool = ppu.unpack_screen_horizontal(0, loader, lvl1_hdr, 0)
	var ok_nt1: bool = ppu.unpack_screen_horizontal(1, loader, lvl1_hdr, 1)
	runner.assert_test("Unpack Screen 0 into NT0 ($2000)", ok_nt0)
	runner.assert_test("Unpack Screen 1 into NT1 ($2400)", ok_nt1)

	ppu.render_frame()

	var active_colored_pixels: int = 0
	var fb: PackedByteArray = ppu.get_framebuffer()
	for i in range(256 * 240):
		if fb[i * 4] != 0 or fb[i * 4 + 1] != 0 or fb[i * 4 + 2] != 0:
			active_colored_pixels += 1
	runner.assert_test("Stage 1 Background Active Colored Pixels > 10,000", active_colored_pixels > 10000, "Active: %d" % active_colored_pixels)

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
	runner.assert_test("Rendered Frame with 8x16 OAM Sprites & Flip Flags", ppu.frame_count >= 2)

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
	runner.assert_test("Authentic Cyclic Priority Offset Advance ($4C)", ppu.oam_shift_offset == expected_shift)

	# Flicker-free unlimited sprite mode
	ppu.flicker_free_sprites = true
	ppu.render_frame()
	runner.assert_test("Flicker-Free Mode Frame Rendered", ppu.frame_count >= 4)

	# Dual-Nametable Horizontal Scrolling & Deterministic Framebuffer CRC-32
	ppu.scroll_x = 128
	ppu.render_frame()

	var fb_crc: int = RomLoaderScript.compute_crc32(ppu.framebuffer)
	print("Rendered Framebuffer Deterministic CRC-32: 0x%08X" % fb_crc)
	runner.assert_test("Deterministic Framebuffer CRC-32 Non-Zero", fb_crc != 0)
	runner.assert_test("Deterministic Framebuffer CRC-32 Match (0xE36185A8)", fb_crc == 0xE36185A8, "Got: 0x%08X" % fb_crc)

	# Godot Image and ImageTexture Conversion
	var fb_img: Image = ppu.get_framebuffer_image()
	runner.assert_test("Image Dimensions 256x240", fb_img.get_width() == 256 and fb_img.get_height() == 240)
	runner.assert_test("Image Format RGBA8", fb_img.get_format() == Image.FORMAT_RGBA8)

	var fb_tex: ImageTexture = ppu.get_framebuffer_texture()
	runner.assert_test("ImageTexture Dimensions 256x240", fb_tex.get_width() == 256 and fb_tex.get_height() == 240)

	# Corridor perspective unpacking
	var ok_corridor: bool = ppu.unpack_corridor_perspective(0)
	runner.assert_test("Corridor Perspective Nametable Unpack", ok_corridor)

	return true

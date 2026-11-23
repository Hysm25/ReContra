class_name PpuRenderer
extends RefCounted

const LevelLoaderScript = preload("res://src/rom/level_loader.gd")

## Generic 2C02 PPU Software Framebuffer & 8x16 OAM Sprite Engine
## Outputs a 256x240 RGBA8 framebuffer convertible to Godot Image / ImageTexture.
## Emulates 16 KB VRAM, Vertical/Horizontal nametable mirroring, 32-byte palette RAM
## with $3F10/$3F14/$3F18/$3F1C mirror folding, dual-nametable supertile unpacking,
## and 8x16 OAM sprite rasterization with authentic $4C cyclic dropout vs flicker-free mode.

# --- Display Geometry ---
const DISPLAY_WIDTH: int = 256
const DISPLAY_HEIGHT: int = 240
const FRAMEBUFFER_SIZE: int = 245760  # 256 * 240 * 4 bytes (RGBA8)

# --- Memory Architecture ---
const VRAM_SIZE: int = 16384          # 16 KB PPU memory space
const PALETTE_RAM_SIZE: int = 32      # 32 bytes ($3F00-$3F1F)
const OAM_SIZE: int = 256             # 64 sprites * 4 bytes
const OAM_SPRITE_COUNT: int = 64
const MAX_SPRITES_PER_SCANLINE: int = 8
const AUTHENTIC_CYCLIC_SHIFT: int = 0x4C

# --- Mirroring Modes ---
const MIRROR_VERTICAL: int = 0        # Horizontal scrolling (NT0/NT2, NT1/NT3)
const MIRROR_HORIZONTAL: int = 1      # Vertical scrolling (NT0/NT1, NT2/NT3)
const MIRROR_SINGLE_0: int = 2        # Single screen NT0 ($2000)
const MIRROR_SINGLE_1: int = 3        # Single screen NT1 ($2400)

# --- PPUCTRL ($2000) Bit Flags ---
const PPUCTRL_NAMETABLE_MASK: int = 0x03
const PPUCTRL_VRAM_INCREMENT_32: int = 0x04
const PPUCTRL_SPRITE_TABLE_1000: int = 0x08
const PPUCTRL_BG_TABLE_1000: int = 0x10
const PPUCTRL_SPRITE_8X16: int = 0x20
const PPUCTRL_SLAVE_MODE: int = 0x40
const PPUCTRL_NMI_ENABLE: int = 0x80

# --- PPUMASK ($2001) Bit Flags ---
const PPUMASK_GRAYSCALE: int = 0x01
const PPUMASK_SHOW_BG_LEFT8: int = 0x02
const PPUMASK_SHOW_SPRITES_LEFT8: int = 0x04
const PPUMASK_SHOW_BG: int = 0x08
const PPUMASK_SHOW_SPRITES: int = 0x10

# --- Fast Palette Byte Cache (64 colors * 4 bytes = 256 bytes) ---
static var _palette_rgba_bytes: PackedByteArray = PackedByteArray()

# --- Internal Buffers ---
var vram: PackedByteArray = PackedByteArray()
var oam: PackedByteArray = PackedByteArray()
var palette_ram: PackedByteArray = PackedByteArray()
var framebuffer: PackedByteArray = PackedByteArray()

# --- Scroll Registers ---
var scroll_x: int = 0                 # 0..511
var scroll_y: int = 0                 # 0..479

# --- Control & Status Registers ---
var ctrl: int = PPUCTRL_SPRITE_8X16 | PPUCTRL_BG_TABLE_1000  # PPUCTRL ($2000): 8x16 sprites + $1000 BG table
var mask: int = 0x1E                  # PPUMASK ($2001) default: show BG+sprites+left8
var status: int = 0                   # PPUSTATUS ($2002)

# --- Configuration & Emulation State ---
var mirroring: int = MIRROR_VERTICAL
var flicker_free_sprites: bool = false
var oam_shift_offset: int = 0
var frame_count: int = 0

# --- Per-Scanline Temporary Scratch Buffers ---
var _bg_pixel_val: PackedByteArray = PackedByteArray()
var _sprite_drawn: PackedByteArray = PackedByteArray()

# --- Pre-decoded 2bpp CHR Tile Pixel Cache (512 tiles * 64 pixels = 32 KB) ---
var chr_pixel_cache: PackedByteArray = PackedByteArray()
var _chr_cache_dirty: bool = true

# --- Persistent Framebuffer Image Instance ---
var _framebuffer_image: Image = null


func _init() -> void:
	_init_palette_cache()
	vram.resize(VRAM_SIZE)
	oam.resize(OAM_SIZE)
	palette_ram.resize(PALETTE_RAM_SIZE)
	framebuffer.resize(FRAMEBUFFER_SIZE)
	_bg_pixel_val.resize(DISPLAY_WIDTH)
	_sprite_drawn.resize(DISPLAY_WIDTH)
	chr_pixel_cache.resize(32768)
	_chr_cache_dirty = true
	_framebuffer_image = Image.create_from_data(DISPLAY_WIDTH, DISPLAY_HEIGHT, false, Image.FORMAT_RGBA8, framebuffer)
	reset()


## Initializes 256-byte RGBA8 byte lookup table from canonical 2C02 NTSC master palette
static func _init_palette_cache() -> void:
	if not _palette_rgba_bytes.is_empty():
		return
	_palette_rgba_bytes.resize(64 * 4)
	for i in range(64):
		var rgba: int = LevelLoaderScript.NES_SYSTEM_PALETTE_RGBA8[i]
		_palette_rgba_bytes[i * 4] = (rgba >> 24) & 0xFF
		_palette_rgba_bytes[i * 4 + 1] = (rgba >> 16) & 0xFF
		_palette_rgba_bytes[i * 4 + 2] = (rgba >> 8) & 0xFF
		_palette_rgba_bytes[i * 4 + 3] = rgba & 0xFF


## Resets PPU memory and control registers to power-on defaults
func reset() -> void:
	vram.fill(0)
	oam.fill(0)
	framebuffer.fill(0)
	_chr_cache_dirty = true

	# Initialize default universal background color to black (0x0F)
	palette_ram.fill(0x0F)

	scroll_x = 0
	scroll_y = 0
	ctrl = PPUCTRL_SPRITE_8X16 | PPUCTRL_BG_TABLE_1000  # 8x16 sprites + Pattern Table 1 ($1000) for BG
	mask = PPUMASK_SHOW_BG | PPUMASK_SHOW_SPRITES | PPUMASK_SHOW_BG_LEFT8 | PPUMASK_SHOW_SPRITES_LEFT8
	status = 0
	mirroring = MIRROR_VERTICAL
	flicker_free_sprites = false
	oam_shift_offset = 0
	frame_count = 0


## Sets mirroring configuration (Vertical, Horizontal, Single 0, Single 1)
func set_mirroring(mode: int) -> void:
	mirroring = mode


## Translates raw 14-bit PPU bus address ($0000-$3FFF) with nametable mirroring and palette folding
func get_mirror_address(addr: int) -> int:
	addr = addr & 0x3FFF

	# Palette RAM space ($3F00-$3FFF)
	if addr >= 0x3F00:
		var pal_offset: int = addr & 0x1F
		# $3F10, $3F14, $3F18, $3F1C mirror to $3F00, $3F04, $3F08, $3F0C
		if (pal_offset & 0x13) == 0x10:
			pal_offset &= 0x0F
		return 0x3F00 + pal_offset

	# $3000-$3EFF mirrors $2000-$2EFF
	if addr >= 0x3000:
		return get_mirror_address(addr - 0x1000)

	# Nametables ($2000-$2FFF)
	if addr >= 0x2000:
		var nt_idx: int = (addr - 0x2000) / 0x400
		var offset: int = (addr - 0x2000) % 0x400
		match mirroring:
			MIRROR_VERTICAL:
				# Vertical mirroring: NT0/NT2 map to $2000; NT1/NT3 map to $2400
				return 0x2000 + ((nt_idx & 1) * 0x400) + offset
			MIRROR_HORIZONTAL:
				# Horizontal mirroring: NT0/NT1 map to $2000; NT2/NT3 map to $2800
				return 0x2000 + ((nt_idx >> 1) * 0x800) + offset
			MIRROR_SINGLE_0:
				return 0x2000 + offset
			MIRROR_SINGLE_1:
				return 0x2400 + offset

	return addr


## Writes a byte to PPU memory space, handling mirroring and palette folding
func write_vram(addr: int, val: int) -> void:
	var eff: int = get_mirror_address(addr)
	if eff >= 0x3F00 and eff <= 0x3F1F:
		palette_ram[eff - 0x3F00] = val & 0x3F
	if eff < vram.size():
		vram[eff] = val & 0xFF
		if eff < 0x2000:
			_chr_cache_dirty = true


## Reads a byte from PPU memory space, handling mirroring and palette folding
func read_vram(addr: int) -> int:
	var eff: int = get_mirror_address(addr)
	if eff >= 0x3F00 and eff <= 0x3F1F:
		return palette_ram[eff - 0x3F00]
	if eff < vram.size():
		return vram[eff]
	return 0


## Loads 256 bytes into OAM buffer ($0200-$02FF DMA equivalent)
func write_oam_buffer(oam_src: PackedByteArray) -> void:
	var count: int = mini(oam_src.size(), OAM_SIZE)
	for i in range(count):
		oam[i] = oam_src[i]


## Loads 32 bytes into internal Palette RAM ($3F00-$3F1F)
func load_palettes(palette_src: PackedByteArray) -> void:
	var count: int = mini(palette_src.size(), PALETTE_RAM_SIZE)
	for i in range(count):
		write_vram(0x3F00 + i, palette_src[i])


## Loads 16 bytes into internal Sprite Palette RAM ($3F10-$3F1F)
func load_sprite_palettes(palette_src: PackedByteArray) -> void:
	var count: int = mini(palette_src.size(), 16)
	for i in range(count):
		write_vram(0x3F10 + i, palette_src[i])


## Pre-decodes 2bpp CHR tiles into 0..3 color indices, eliminating inner-loop bit-shifts
func update_chr_cache() -> void:
	if not _chr_cache_dirty:
		return
	_chr_cache_dirty = false
	if chr_pixel_cache.size() != 32768:
		chr_pixel_cache.resize(32768)

	var cache_idx: int = 0
	for t in range(512):
		var tile_base: int = t * 16
		for v in range(8):
			var p0: int = vram[tile_base + v]
			var p1: int = vram[tile_base + v + 8]
			for u in range(8):
				var shift: int = 7 - u
				var b0: int = (p0 >> shift) & 1
				var b1: int = (p1 >> shift) & 1
				chr_pixel_cache[cache_idx] = (b1 << 1) | b0
				cache_idx += 1


## Decodes 2-bit color index (0..3) of an 8x8 tile at pixel coordinate (u, v) [0..7, 0..7]
func decode_tile_pixel(pattern_base: int, tile_idx: int, u: int, v: int) -> int:
	if _chr_cache_dirty:
		update_chr_cache()
	var global_tile: int = ((pattern_base >> 12) & 1) * 256 + (tile_idx & 0xFF)
	var offset: int = (global_tile << 6) | ((v & 7) << 3) | (u & 7)
	if offset < chr_pixel_cache.size():
		return chr_pixel_cache[offset]
	return 0


## Unpacks an 8x7 supertile screen into the specified Nametable (0 or 1: $2000 or $2400)
## for horizontal scrolling stages.
func unpack_screen_horizontal(
	nametable_idx: int,
	loader: RefCounted,
	hdr: RefCounted,
	screen_index: int
) -> bool:
	var nt_base: int = 0x2400 if nametable_idx == 1 else 0x2000
	var supertiles: PackedByteArray = LevelLoaderScript.decompress_screen_supertiles(loader, hdr, screen_index)
	if supertiles.size() < 56:
		return false

	# Clear entire 1024-byte nametable and attribute table (rows 28-29 empty)
	for i in range(1024):
		write_vram(nt_base + i, 0x00)

	# Horizontal levels: 8 columns x 7 rows = 56 supertiles per screen.
	# Writes supertiles starting at row 0 (PPU $2000 / $2400).
	for sr in range(7):
		for sc in range(8):
			var supertile_id: int = supertiles[sr * 8 + sc]

			var st_tiles: PackedByteArray = LevelLoaderScript.read_supertile(loader, hdr.supertile_ptr, supertile_id)
			if st_tiles.size() < 16:
				return false

			# Read supertile palette attribute byte from Bank 3
			var st_attr: int = loader.read_cpu(hdr.palette_ptr + supertile_id, 3)
			if st_attr < 0:
				return false

			# Write 4x4 tiles to Nametable
			for r in range(4):
				var nt_row: int = sr * 4 + r
				if nt_row >= 30:
					break
				for c in range(4):
					var nt_col: int = sc * 4 + c
					var dest_addr: int = nt_base + (nt_row * 32) + nt_col
					write_vram(dest_addr, st_tiles[r * 4 + c])

			# Populate Attribute Table ($23C0 or $27C0)
			# Each supertile spans 4x4 tiles (1 attribute byte).
			if sr < 7:
				var attr_addr: int = nt_base + 960 + (sr * 8) + sc
				write_vram(attr_addr, st_attr)

	return true


## Unpacks an 8x8 supertile screen into the specified Nametable for vertical scrolling stages.
func unpack_screen_vertical(
	nametable_idx: int,
	loader: RefCounted,
	hdr: RefCounted,
	screen_index: int
) -> bool:
	var nt_base: int = 0x2400 if nametable_idx == 1 else 0x2000
	var supertiles: PackedByteArray = LevelLoaderScript.decompress_screen_supertiles(loader, hdr, screen_index)
	if supertiles.size() < 64:
		return false

	for i in range(1024):
		write_vram(nt_base + i, 0x00)

	# Vertical levels: 8 columns x 8 rows = 64 supertiles per screen.
	for sr in range(8):
		for sc in range(8):
			var supertile_id: int = supertiles[sr * 8 + sc]

			var st_tiles: PackedByteArray = LevelLoaderScript.read_supertile(loader, hdr.supertile_ptr, supertile_id)
			if st_tiles.size() < 16:
				return false

			var st_attr: int = loader.read_cpu(hdr.palette_ptr + supertile_id, 3)
			if st_attr < 0:
				return false

			for r in range(4):
				var nt_row: int = sr * 4 + r
				if nt_row >= 30:
					break
				for c in range(4):
					var nt_col: int = sc * 4 + c
					var dest_addr: int = nt_base + (nt_row * 32) + nt_col
					write_vram(dest_addr, st_tiles[r * 4 + c])

			if sr < 8:
				var attr_addr: int = nt_base + 960 + (sr * 8) + sc
				write_vram(attr_addr, st_attr)

	return true


## Unpacks a 3D indoor perspective corridor nametable for base stages.
func unpack_corridor_perspective(nametable_idx: int, _room_depth_step: int = 0) -> bool:
	var nt_base: int = 0x2400 if nametable_idx == 1 else 0x2000

	# Fill background with basic grid pattern for corridor perspective
	for row in range(30):
		for col in range(32):
			var dest_addr: int = nt_base + (row * 32) + col
			var tile: int = 0x00
			if row < 4 or row > 25:
				tile = 0x01  # Ceiling / floor border
			elif col < 4 or col > 27:
				tile = 0x02  # Side wall border
			write_vram(dest_addr, tile)

	# Set attribute table to uniform subpalette 0
	for a in range(64):
		write_vram(nt_base + 960 + a, 0x00)

	return true


## Renders a single scanline (0..239) into the RGBA8 framebuffer
func render_scanline(scanline: int) -> void:
	if scanline < 0 or scanline >= DISPLAY_HEIGHT:
		return
	if _chr_cache_dirty:
		update_chr_cache()

	var line_offset: int = scanline * DISPLAY_WIDTH * 4
	var universal_bg_color: int = palette_ram[0]
	var ub_offset: int = (universal_bg_color & 0x3F) * 4
	var ub_r: int = _palette_rgba_bytes[ub_offset]
	var ub_g: int = _palette_rgba_bytes[ub_offset + 1]
	var ub_b: int = _palette_rgba_bytes[ub_offset + 2]

	_bg_pixel_val.fill(0)

	# --- 1. Background Tile Layer Rendering ---
	if (mask & PPUMASK_SHOW_BG) != 0:
		var pattern_base_tile: int = 256 if (ctrl & PPUCTRL_BG_TABLE_1000) != 0 else 256
		var total_y: int = (scroll_y + scanline) % 480
		var ty: int = total_y / 8
		var py: int = total_y % 8
		var nt_row: int = ty / 30
		var tile_y_in_nt: int = ty % 30
		var nt_row_offset: int = tile_y_in_nt * 32
		var attr_row: int = tile_y_in_nt / 4
		var quad_y: int = (tile_y_in_nt % 4) / 2

		var last_tx: int = -1
		var tile_row_offset: int = 0
		var pal_base: int = 0

		for x in range(DISPLAY_WIDTH):
			var px_out: int = line_offset + (x * 4)

			# Left 8-pixel clipping
			if x < 8 and (mask & PPUMASK_SHOW_BG_LEFT8) == 0:
				framebuffer[px_out] = ub_r
				framebuffer[px_out + 1] = ub_g
				framebuffer[px_out + 2] = ub_b
				framebuffer[px_out + 3] = 0xFF
				continue

			var total_x: int = (scroll_x + x) % 512
			var tx: int = total_x / 8
			var px: int = total_x % 8

			if tx != last_tx:
				last_tx = tx
				var nt_idx: int = (nt_row * 2) + (tx / 32)
				var nt_base: int = 0x2000 + (nt_idx * 0x400)
				var tile_id: int = read_vram(nt_base + nt_row_offset + (tx % 32))

				var attr_col: int = (tx % 32) / 4
				var attr_addr: int = nt_base + 960 + (attr_row * 8) + attr_col
				var attr_byte: int = read_vram(attr_addr)

				var quad_x: int = ((tx % 32) % 4) / 2
				var shift: int = (quad_y * 2 + quad_x) * 2
				var subpalette: int = (attr_byte >> shift) & 0x03

				tile_row_offset = ((pattern_base_tile + tile_id) << 6) | (py << 3)
				pal_base = subpalette * 4

			var pixel_val: int = chr_pixel_cache[tile_row_offset | px]
			_bg_pixel_val[x] = pixel_val

			if pixel_val == 0:
				framebuffer[px_out] = ub_r
				framebuffer[px_out + 1] = ub_g
				framebuffer[px_out + 2] = ub_b
				framebuffer[px_out + 3] = 0xFF
			else:
				var nes_color: int = palette_ram[pal_base + pixel_val]
				var c_off: int = (nes_color & 0x3F) * 4
				framebuffer[px_out] = _palette_rgba_bytes[c_off]
				framebuffer[px_out + 1] = _palette_rgba_bytes[c_off + 1]
				framebuffer[px_out + 2] = _palette_rgba_bytes[c_off + 2]
				framebuffer[px_out + 3] = 0xFF
	else:
		for x in range(DISPLAY_WIDTH):
			var px_out: int = line_offset + (x * 4)
			framebuffer[px_out] = ub_r
			framebuffer[px_out + 1] = ub_g
			framebuffer[px_out + 2] = ub_b
			framebuffer[px_out + 3] = 0xFF

	# --- 2. 8x16 OAM Sprite Layer Rendering ---
	if (mask & PPUMASK_SHOW_SPRITES) != 0:
		var active_sprites: PackedByteArray = PackedByteArray()

		# Scan OAM for active sprites on this scanline
		if flicker_free_sprites:
			# Unlimited Sprite Mode: sequential scan
			for i in range(OAM_SPRITE_COUNT):
				var sy: int = oam[i * 4] + 1
				if scanline >= sy and scanline < sy + 16:
					active_sprites.append(i)
		else:
			# Authentic NES cyclic priority scan ($4C priority offset)
			var start_sprite: int = (oam_shift_offset >> 2) % OAM_SPRITE_COUNT
			for step in range(OAM_SPRITE_COUNT):
				var i: int = (start_sprite + step) % OAM_SPRITE_COUNT
				var sy: int = oam[i * 4] + 1
				if scanline >= sy and scanline < sy + 16:
					active_sprites.append(i)
					if active_sprites.size() >= MAX_SPRITES_PER_SCANLINE:
						break  # 8-sprite per scanline limit reached

		_sprite_drawn.fill(0)

		# Render active sprites in priority order
		for k in range(active_sprites.size()):
			var i: int = active_sprites[k]
			var oam_base: int = i * 4
			var sy: int = oam[oam_base] + 1
			var tile_code: int = oam[oam_base + 1]
			var attr: int = oam[oam_base + 2]
			var sx: int = oam[oam_base + 3]

			var row: int = scanline - sy
			if (attr & 0x80) != 0:
				row = 15 - row  # Vertical Flip

			# 8x16 Mode: bit 0 selects pattern table, bits 1..7 select even tile
			var pattern_base_tile: int = 256 if (tile_code & 1) != 0 else 0
			var tile_base: int = tile_code & 0xFE
			var actual_tile: int = tile_base if row < 8 else tile_base + 1
			var actual_row: int = row if row < 8 else row - 8

			var subpalette: int = attr & 0x03
			var behind_bg: bool = (attr & 0x20) != 0
			var flip_h: bool = (attr & 0x40) != 0

			var sprite_row_offset: int = ((pattern_base_tile + actual_tile) << 6) | (actual_row << 3)
			var pal_base: int = 16 + (subpalette * 4)

			for col in range(8):
				var screen_x: int = sx + col
				if screen_x < 0 or screen_x >= DISPLAY_WIDTH:
					continue
				if screen_x < 8 and (mask & PPUMASK_SHOW_SPRITES_LEFT8) == 0:
					continue
				if _sprite_drawn[screen_x] != 0:
					continue  # Higher priority sprite already rendered

				var u: int = (7 - col) if flip_h else col
				var pixel_val: int = chr_pixel_cache[sprite_row_offset | u]
				if pixel_val == 0:
					continue  # Transparent pixel

				_sprite_drawn[screen_x] = 1

				# Background priority masking
				if behind_bg and _bg_pixel_val[screen_x] != 0:
					continue

				var nes_color: int = palette_ram[pal_base + pixel_val]
				var c_off: int = (nes_color & 0x3F) * 4
				var px_out: int = line_offset + (screen_x * 4)
				framebuffer[px_out] = _palette_rgba_bytes[c_off]
				framebuffer[px_out + 1] = _palette_rgba_bytes[c_off + 1]
				framebuffer[px_out + 2] = _palette_rgba_bytes[c_off + 2]
				framebuffer[px_out + 3] = 0xFF


## Renders a complete 256x240 frame (all 240 scanlines) and advances $4C priority offset
func render_frame() -> void:
	for y in range(DISPLAY_HEIGHT):
		render_scanline(y)

	# Advance cyclic priority shift offset ($4C) for authentic flicker cycle
	oam_shift_offset = (oam_shift_offset + AUTHENTIC_CYCLIC_SHIFT) & 0xFF
	frame_count += 1


## Returns the native 256x240 RGBA8 byte buffer
func get_framebuffer() -> PackedByteArray:
	return framebuffer


## Returns Godot Image for the current framebuffer, reusing internal Image instance
func get_framebuffer_image() -> Image:
	if _framebuffer_image == null:
		_framebuffer_image = Image.create_from_data(DISPLAY_WIDTH, DISPLAY_HEIGHT, false, Image.FORMAT_RGBA8, framebuffer)
	else:
		_framebuffer_image.set_data(DISPLAY_WIDTH, DISPLAY_HEIGHT, false, Image.FORMAT_RGBA8, framebuffer)
	return _framebuffer_image


## Creates an ImageTexture from the current framebuffer
func get_framebuffer_texture() -> ImageTexture:
	var img: Image = get_framebuffer_image()
	return ImageTexture.create_from_image(img)


## Updates an existing ImageTexture in-place reusing the internal Image instance
func update_texture(tex: ImageTexture) -> void:
	if tex == null:
		return
	if _framebuffer_image == null:
		_framebuffer_image = Image.create_from_data(DISPLAY_WIDTH, DISPLAY_HEIGHT, false, Image.FORMAT_RGBA8, framebuffer)
	else:
		_framebuffer_image.set_data(DISPLAY_WIDTH, DISPLAY_HEIGHT, false, Image.FORMAT_RGBA8, framebuffer)
	tex.update(_framebuffer_image)


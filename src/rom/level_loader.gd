class_name LevelLoader
extends RefCounted

## Generic Level Header, Supertile & Palette Subsystem
## Reads 32-byte Level Headers from Bank 2 ($B319), 4x4 Supertiles from Bank 3,
## and 2C02 NTSC master palette RGBA8 mappings from Bank 7 ($D225).
## Implements authentic 3-case RLE screen supertile decompression.

# --- Constants: Memory Layout & Disassembly Offsets ---
const LEVEL_COUNT: int = 8
const LEVEL_HEADER_BANK: int = 2
const LEVEL_HEADERS_CPU_ADDR: int = 0xB319
const LEVEL_HEADER_SIZE: int = 32

const GAME_PALETTE_PTR_TBL_ADDR: int = 0xD225
const GAME_PALETTES_DEFAULT_ADDR: int = 0xD227
const GAME_PALETTE_COUNT: int = 110
const PALETTE_RAM_SIZE: int = 32 # 16 background + 16 sprite NES colors

# Canonical 2C02 NTSC master palette (64 colors) mapped to 32-bit RGBA8888 (0xRRGGBBAA)
const NES_SYSTEM_PALETTE_RGBA8: PackedInt64Array = [
	0x666666FF, 0x002A88FF, 0x1412A7FF, 0x3B00A4FF,
	0x5C007EFF, 0x6E0040FF, 0x6C0600FF, 0x561D00FF,
	0x333500FF, 0x0B4800FF, 0x005200FF, 0x004F08FF,
	0x00404DFF, 0x000000FF, 0x000000FF, 0x000000FF,

	0xADADADFF, 0x155FD9FF, 0x4240FFFF, 0x7527FEFF,
	0xA01ACCFF, 0xB71E7BFF, 0xB53120FF, 0x994E00FF,
	0x6B6D00FF, 0x388700FF, 0x0C9300FF, 0x008F32FF,
	0x007C8DFF, 0x000000FF, 0x000000FF, 0x000000FF,

	0xFFFFFFFF, 0x64B0FFFF, 0x9290FFFF, 0xC676FFFF,
	0xF36AFFFF, 0xFE6ECCFF, 0xFE8170FF, 0xEA9E22FF,
	0xBCBE00FF, 0x88D800FF, 0x5CE430FF, 0x45E082FF,
	0x48CDDEFF, 0x4F4F4FFF, 0x000000FF, 0x000000FF,

	0xFFFFFFFF, 0xC0E1FFFF, 0xD3D2FFFF, 0xE8C5FFFF,
	0xFBC2FFFF, 0xFEC2EFFF, 0xFECAC5FF, 0xF7D7A5FF,
	0xE5E490FF, 0xCEF090FF, 0xB5F7B2FF, 0xABF6D5FF,
	0xACEEF7FF, 0xA8A8A8FF, 0x000000FF, 0x000000FF
]


## Parsed 32-byte Level Header
class LevelHeader extends RefCounted:
	var level_index: int = 0
	var location_type: int = 0   # 0 = Outdoor, 1 = Indoor base
	var scrolling_type: int = 0  # 0 = Horizontal, 1 = Vertical
	var screen_ptr: int = 0      # Bank 2 CPU address for screen supertile pointer table
	var supertile_ptr: int = 0   # Bank 3 CPU address for 4x4 tile makeup
	var palette_ptr: int = 0     # Bank 3 CPU address for supertile palette attributes
	var alt_graphics_pos: int = 0
	var collision_limits: PackedByteArray = PackedByteArray() # 3 bytes
	var palette_cycle_indexes: PackedByteArray = PackedByteArray() # 4 bytes
	var bg_palette_indexes: PackedByteArray = PackedByteArray() # 4 bytes
	var sprite_palette_indexes: PackedByteArray = PackedByteArray() # 4 bytes
	var stop_scrolling_pos: int = 0
	var bullet_solid_collision: int = 0


## Converts an authentic NES color index (0x00..0x3F) to 32-bit RGBA integer
static func nes_color_to_rgba8(nes_color: int) -> int:
	return NES_SYSTEM_PALETTE_RGBA8[nes_color & 0x3F]


## Converts an authentic NES color index (0x00..0x3F) to a Godot Color object
static func nes_color_to_color(nes_color: int) -> Color:
	return Color.hex(NES_SYSTEM_PALETTE_RGBA8[nes_color & 0x3F])


## Reads a 32-byte Level Header dynamically from Bank 2 ($B319 + level * 32)
static func load_level_header(loader: RefCounted, level: int) -> LevelHeader:
	if level < 0 or level >= LEVEL_COUNT:
		return null

	var base_addr: int = LEVEL_HEADERS_CPU_ADDR + (level * LEVEL_HEADER_SIZE)
	var raw: PackedByteArray = PackedByteArray()
	raw.resize(LEVEL_HEADER_SIZE)

	for i in range(LEVEL_HEADER_SIZE):
		var b: int = loader.read_cpu(base_addr + i, LEVEL_HEADER_BANK)
		if b < 0:
			return null
		raw[i] = b

	var hdr: LevelHeader = LevelHeader.new()
	hdr.level_index = level
	hdr.location_type = raw[0]
	hdr.scrolling_type = raw[1]
	hdr.screen_ptr = (raw[3] << 8) | raw[2]
	hdr.supertile_ptr = (raw[5] << 8) | raw[4]
	hdr.palette_ptr = (raw[7] << 8) | raw[6]
	hdr.alt_graphics_pos = raw[8]
	hdr.collision_limits = raw.slice(9, 12)
	hdr.palette_cycle_indexes = raw.slice(12, 16)
	hdr.bg_palette_indexes = raw.slice(16, 20)
	hdr.sprite_palette_indexes = raw.slice(20, 24)
	hdr.stop_scrolling_pos = raw[24]
	hdr.bullet_solid_collision = raw[25]

	return hdr


## Alias for load_level_header
static func load_header(loader: RefCounted, level: int) -> LevelHeader:
	return load_level_header(loader, level)


## Reads a single 3-color palette entry (0..109) from Bank 7 game_palettes
static func get_palette_colors(loader: RefCounted, palette_idx: int) -> PackedByteArray:
	var out_colors: PackedByteArray = PackedByteArray()
	if palette_idx < 0 or palette_idx >= GAME_PALETTE_COUNT:
		return out_colors

	var game_palettes_addr: int = loader.read_cpu_word(GAME_PALETTE_PTR_TBL_ADDR, 7)
	if game_palettes_addr < 0:
		game_palettes_addr = GAME_PALETTES_DEFAULT_ADDR

	var pal_addr: int = game_palettes_addr + (palette_idx * 3)
	for i in range(3):
		var c: int = loader.read_cpu(pal_addr + i, 7)
		if c < 0:
			return PackedByteArray()
		out_colors.append(c)

	return out_colors


## Populates 32-byte PALETTE_CPU_BUFFER (16 background + 16 sprite NES color indices) for a level
static func load_palettes(loader: RefCounted, level: int) -> PackedByteArray:
	var hdr: LevelHeader = load_level_header(loader, level)
	if hdr == null:
		return PackedByteArray()

	var buf: PackedByteArray = PackedByteArray()
	buf.resize(PALETTE_RAM_SIZE)

	# Universal background color: $0F (black) at indices 0, 4, 8, 12, 16, 20, 24, 28
	# Background palettes 0..3: 3 colors each from hdr.bg_palette_indexes[0..3]
	# Sprite palettes 0..3: 3 colors each from hdr.sprite_palette_indexes[0..3]
	for p in range(4):
		var bg_base: int = p * 4
		buf[bg_base] = 0x0F
		var bg_colors: PackedByteArray = get_palette_colors(loader, hdr.bg_palette_indexes[p])
		if bg_colors.size() < 3:
			return PackedByteArray()
		buf[bg_base + 1] = bg_colors[0]
		buf[bg_base + 2] = bg_colors[1]
		buf[bg_base + 3] = bg_colors[2]

		var sp_base: int = 16 + p * 4
		buf[sp_base] = 0x0F
		var sp_colors: PackedByteArray = get_palette_colors(loader, hdr.sprite_palette_indexes[p])
		if sp_colors.size() < 3:
			return PackedByteArray()
		buf[sp_base + 1] = sp_colors[0]
		buf[sp_base + 2] = sp_colors[1]
		buf[sp_base + 3] = sp_colors[2]

	return buf


## Populates 16-byte sprite palette buffer ($3F10-$3F1F) for a level dynamically from Bank 7
static func load_sprite_palettes(loader: RefCounted, level: int) -> PackedByteArray:
	var hdr: LevelHeader = load_level_header(loader, level)
	if hdr == null:
		return PackedByteArray()

	var buf: PackedByteArray = PackedByteArray()
	buf.resize(16)
	for p in range(4):
		var sp_base: int = p * 4
		buf[sp_base] = 0x0F
		var sp_colors: PackedByteArray = get_palette_colors(loader, hdr.sprite_palette_indexes[p])
		if sp_colors.size() < 3:
			return PackedByteArray()
		buf[sp_base + 1] = sp_colors[0]
		buf[sp_base + 2] = sp_colors[1]
		buf[sp_base + 3] = sp_colors[2]
	return buf


## Populates 16-byte background palette buffer ($3F00-$3F0F) for a level dynamically from Bank 7
static func load_bg_palettes(loader: RefCounted, level: int) -> PackedByteArray:
	var hdr: LevelHeader = load_level_header(loader, level)
	if hdr == null:
		return PackedByteArray()

	var buf: PackedByteArray = PackedByteArray()
	buf.resize(16)
	for p in range(4):
		var bg_base: int = p * 4
		buf[bg_base] = 0x0F
		var bg_colors: PackedByteArray = get_palette_colors(loader, hdr.bg_palette_indexes[p])
		if bg_colors.size() < 3:
			return PackedByteArray()
		buf[bg_base + 1] = bg_colors[0]
		buf[bg_base + 2] = bg_colors[1]
		buf[bg_base + 3] = bg_colors[2]
	return buf


## Returns the 32 level palette colors converted to 32-bit RGBA8 integers
static func load_palettes_rgba8(loader: RefCounted, level: int) -> PackedInt64Array:
	var raw_pal: PackedByteArray = load_palettes(loader, level)
	var rgba: PackedInt64Array = PackedInt64Array()
	if raw_pal.is_empty():
		return rgba
	rgba.resize(raw_pal.size())
	for i in range(raw_pal.size()):
		rgba[i] = nes_color_to_rgba8(raw_pal[i])
	return rgba


## Returns the 32 level palette colors converted to Godot Color objects
static func load_palettes_colors(loader: RefCounted, level: int) -> PackedColorArray:
	var raw_pal: PackedByteArray = load_palettes(loader, level)
	var colors: PackedColorArray = PackedColorArray()
	if raw_pal.is_empty():
		return colors
	colors.resize(raw_pal.size())
	for i in range(raw_pal.size()):
		colors[i] = nes_color_to_color(raw_pal[i])
	return colors


## Reads a 4x4 supertile definition (16 bytes) from Bank 3 at supertile_base_ptr
static func read_supertile(loader: RefCounted, supertile_base_ptr: int, supertile_id: int) -> PackedByteArray:
	var tiles: PackedByteArray = PackedByteArray()
	tiles.resize(16)
	var addr: int = supertile_base_ptr + (supertile_id * 16)
	for i in range(16):
		var b: int = loader.read_cpu(addr + i, 3)
		if b < 0:
			return PackedByteArray()
		tiles[i] = b
	return tiles


## Decompresses screen supertile indices (56 for horizontal, 64 for vertical)
## from Bank 2 dynamically using authentic 3-case RLE decompression:
##   - Case 1: b < $80 -> literal supertile index
##   - Case 2: $80 <= b < $F0 -> repeat next byte (b & $7F) times
##   - Case 3: b >= $F0 -> copy 8 supertiles from row (b & $0F) * 8
static func decompress_screen_supertiles(loader: RefCounted, hdr: LevelHeader, screen_index: int) -> PackedByteArray:
	var target_count: int = 64 if hdr.scrolling_type == 1 else 56
	var out_st: PackedByteArray = PackedByteArray()
	out_st.resize(target_count)

	var screen_tbl_addr: int = hdr.screen_ptr + (screen_index * 2)
	var screen_data_addr: int = loader.read_cpu_word(screen_tbl_addr, LEVEL_HEADER_BANK)
	if screen_data_addr < 0:
		return PackedByteArray()

	var out_idx: int = 0
	var in_offset: int = 0

	while out_idx < target_count:
		var b: int = loader.read_cpu(screen_data_addr + in_offset, LEVEL_HEADER_BANK)
		if b < 0:
			return PackedByteArray()
		in_offset += 1

		if b < 0x80:
			out_st[out_idx] = b
			out_idx += 1
		elif b < 0xF0:
			var count: int = b & 0x7F
			var val: int = loader.read_cpu(screen_data_addr + in_offset, LEVEL_HEADER_BANK)
			if val < 0:
				return PackedByteArray()
			in_offset += 1

			for _i in range(count):
				if out_idx < target_count:
					out_st[out_idx] = val
					out_idx += 1
		else:
			var src_row: int = b & 0x0F
			var src_start: int = src_row * 8
			for i in range(8):
				if out_idx < target_count:
					out_st[out_idx] = out_st[src_start + i]
					out_idx += 1

	return out_st

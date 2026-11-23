class_name SoundEngine
extends RefCounted

## Generic Ricoh 2A03 6-Slot Audio Engine & Bytecode Sequencer
## Dynamically parses Bank 1 sound tables ($88E8, $88DB, $82CD, $8001, $86D5) via RomLoader.
## Arbitrates priority across 6 slots (SFX Pulse 1 overrides BGM Pulse 1; SFX Noise overrides BGM Percussion).
## Supports subroutine branching ($FD), loop repetition ($FE), stream termination ($FF), and envelopes.

# --- Constants: Slot Topology ---
const SOUND_SLOT_COUNT: int = 6

const SOUND_SLOT_BGM_PULSE1: int = 0
const SOUND_SLOT_BGM_PULSE2: int = 1
const SOUND_SLOT_BGM_TRI: int = 2
const SOUND_SLOT_BGM_PERC: int = 3
const SOUND_SLOT_SFX_PULSE1: int = 4
const SOUND_SLOT_SFX_NOISE: int = 5

# --- Constants: Bank 1 Table Offsets (PRG ROM Offset from 0x4000) ---
const ROM_SOUND_TABLE_OFFSET: int = 0x48E8      # CPU $88E8
const ROM_DPCM_TABLE_OFFSET: int = 0x48DB       # CPU $88DB
const ROM_PERCUSSION_TABLE_OFFSET: int = 0x42CD # CPU $82CD
const ROM_PULSE_VOL_TABLE_OFFSET: int = 0x4001  # CPU $8001
const ROM_NOTE_PERIOD_OFFSET: int = 0x46D5      # CPU $86D5

# --- Constants: APU Register References ---
const APU_REG_PULSE1_CTRL: int = 0x4000
const APU_REG_PULSE2_CTRL: int = 0x4004
const APU_REG_TRI_CTRL: int = 0x4008
const APU_REG_NOISE_CTRL: int = 0x400C
const APU_REG_DMC_CTRL: int = 0x4010
const APU_REG_DMC_DIRECT: int = 0x4011
const APU_REG_DMC_ADDR: int = 0x4012
const APU_REG_DMC_LENGTH: int = 0x4013
const APU_REG_STATUS: int = 0x4015

# --- Nested Class: Sound Channel Slot ---
class SoundSlot extends RefCounted:
	var sound_code: int = 0
	var cmd_length: int = 0
	var length_multiplier: int = 0
	var flags: int = 0 # Bit 0: low code (< $30), Bit 2: auto decrescendo, Bit 3: shared child call, Bit 4: flatten, Bit 6: mute
	var cmd_addr: int = 0
	var return_addr: int = 0
	var repeat_count: int = 0
	var pulse_length: int = 0
	var pulse_period: int = 0
	var pulse_volume: int = 0
	var vol_duration: int = 0
	var vol_env_index: int = 0
	var vol_step_index: int = 0
	var decrescendo_pause: int = 0
	var pitch_adjust: int = 0
	var period_rotate: int = 0
	var cfg_high: int = 0
	var cfg_low: int = 0
	var triangle_cfg: int = 0
	var vibrato_ctrl: int = 0
	var vibrato_delay: int = 0
	var vibrato_amount: int = 0
	var vol_timer: int = 0

	func reset() -> void:
		sound_code = 0
		cmd_length = 0
		length_multiplier = 0
		flags = 0
		cmd_addr = 0
		return_addr = 0
		repeat_count = 0
		pulse_length = 0
		pulse_period = 0
		pulse_volume = 0
		vol_duration = 0
		vol_env_index = 0
		vol_step_index = 0
		decrescendo_pause = 0
		pitch_adjust = 0
		period_rotate = 0
		cfg_high = 0
		cfg_low = 0
		triangle_cfg = 0
		vibrato_ctrl = 0
		vibrato_delay = 0
		vibrato_amount = 0
		vol_timer = 0


# --- Engine State ---
var rom_loader: RefCounted = null
var prg_rom: PackedByteArray = PackedByteArray()
var is_loaded: bool = false
var is_paused: bool = false
var slots: Array[SoundSlot] = []


func _init(loader: RefCounted = null) -> void:
	slots.resize(SOUND_SLOT_COUNT)
	for i in range(SOUND_SLOT_COUNT):
		slots[i] = SoundSlot.new()
	if loader != null:
		init_engine(loader)


## Initializes sound engine with an authentic RomLoader instance
func init_engine(loader: RefCounted) -> bool:
	if loader == null:
		return false
	rom_loader = loader
	prg_rom = loader.get_prg_rom()
	if prg_rom.is_empty():
		return false
	is_loaded = true
	is_paused = false
	reset_engine()
	return true


## Resets all slots and sequencer state
func reset_engine() -> void:
	for slot in slots:
		slot.reset()


## Sets engine pause state
func set_paused(paused: bool) -> void:
	is_paused = paused


## Reads a byte from PRG ROM translating CPU address (Bank 1: $8000-$BFFF, Bank 7: $C000-$FFFF)
func read_prg_byte(cpu_addr: int) -> int:
	if not is_loaded:
		return 0
	var prg_offset: int = 0
	if cpu_addr >= 0x8000 and cpu_addr <= 0xBFFF:
		prg_offset = 0x4000 + (cpu_addr - 0x8000)
	elif cpu_addr >= 0xC000:
		prg_offset = 0x1C000 + (cpu_addr - 0xC000)
	else:
		prg_offset = cpu_addr

	if prg_offset >= 0 and prg_offset < prg_rom.size():
		return prg_rom[prg_offset]
	return 0


## Reads a byte directly from PRG ROM offset
func read_prg_offset(prg_offset: int) -> int:
	if not is_loaded or prg_offset < 0 or prg_offset >= prg_rom.size():
		return 0
	return prg_rom[prg_offset]


## Mutes an APU channel associated with a slot index
func mute_channel(apu: RefCounted, slot_idx: int) -> void:
	if apu == null:
		return
	match slot_idx:
		SOUND_SLOT_BGM_PULSE1, SOUND_SLOT_SFX_PULSE1:
			apu.write_register(APU_REG_PULSE1_CTRL, 0x30)
		SOUND_SLOT_BGM_PULSE2:
			apu.write_register(APU_REG_PULSE2_CTRL, 0x30)
		SOUND_SLOT_BGM_TRI:
			apu.write_register(APU_REG_TRI_CTRL, 0x00)
		SOUND_SLOT_BGM_PERC, SOUND_SLOT_SFX_NOISE:
			apu.write_register(APU_REG_NOISE_CTRL, 0x30)


## Writes to a channel register with priority arbitration
func write_channel_reg(apu: RefCounted, slot_idx: int, reg_offset: int, val: int) -> void:
	if apu == null or not is_loaded:
		return

	# Slot priority arbitration
	if slot_idx == SOUND_SLOT_BGM_PULSE1 and slots[SOUND_SLOT_SFX_PULSE1].sound_code != 0:
		return # SFX Pulse 1 overrides BGM Pulse 1
	if slot_idx == SOUND_SLOT_BGM_PERC and slots[SOUND_SLOT_SFX_NOISE].sound_code != 0:
		return # SFX Noise overrides BGM Noise

	var base_reg: int = 0
	match slot_idx:
		SOUND_SLOT_BGM_PULSE1, SOUND_SLOT_SFX_PULSE1:
			base_reg = APU_REG_PULSE1_CTRL
		SOUND_SLOT_BGM_PULSE2:
			base_reg = APU_REG_PULSE2_CTRL
		SOUND_SLOT_BGM_TRI:
			base_reg = APU_REG_TRI_CTRL
		SOUND_SLOT_BGM_PERC, SOUND_SLOT_SFX_NOISE:
			base_reg = APU_REG_NOISE_CTRL
		_:
			return

	apu.write_register(base_reg + reg_offset, val)


## Triggers playback of a sound code (SFX, BGM, or DPCM percussion sample)
func play_sound(apu: RefCounted, sound_code: int) -> bool:
	if not is_loaded or sound_code == 0:
		return false

	# 1. Direct DPCM Sample Trigger (sound codes >= 0x5A)
	if sound_code >= 0x5A:
		if apu == null:
			return false
		var dpcm_entry_offset: int = ROM_DPCM_TABLE_OFFSET + (sound_code - 0x5A) * 4
		if dpcm_entry_offset + 3 < prg_rom.size():
			var dmc_cfg: int = read_prg_offset(dpcm_entry_offset)
			var dmc_counter: int = read_prg_offset(dpcm_entry_offset + 1)
			var s_addr: int = read_prg_offset(dpcm_entry_offset + 2)
			var s_len: int = read_prg_offset(dpcm_entry_offset + 3)

			# Enable 5 channels with DMC
			apu.write_register(APU_REG_STATUS, 0x0F)
			apu.write_register(APU_REG_DMC_CTRL, dmc_cfg)
			apu.write_register(APU_REG_DMC_DIRECT, dmc_counter)
			apu.write_register(APU_REG_DMC_ADDR, s_addr)
			apu.write_register(APU_REG_DMC_LENGTH, s_len)
			apu.write_register(APU_REG_STATUS, 0x1F)
		return true

	# 2. Standard Sound Table Lookup ($88E8)
	var base_entry_off: int = ROM_SOUND_TABLE_OFFSET + sound_code * 3
	if base_entry_off + 2 >= prg_rom.size():
		return false

	var ctrl: int = read_prg_offset(base_entry_off)
	var extra_slots: int = (ctrl >> 3) & 0x03

	for e in range(extra_slots + 1):
		var entry_off: int = ROM_SOUND_TABLE_OFFSET + (sound_code + e) * 3
		if entry_off + 2 >= prg_rom.size():
			break

		var c_byte: int = read_prg_offset(entry_off)
		var slot_idx: int = c_byte & 0x07
		if slot_idx >= SOUND_SLOT_COUNT:
			continue

		var alo: int = read_prg_offset(entry_off + 1)
		var ahi: int = read_prg_offset(entry_off + 2)
		var addr: int = alo | (ahi << 8)

		# SFX priority check: do not overwrite higher code if already playing
		if slots[slot_idx].sound_code != 0 and sound_code < slots[slot_idx].sound_code:
			continue

		var slot: SoundSlot = slots[slot_idx]
		slot.reset()
		slot.sound_code = sound_code
		slot.cmd_addr = addr
		slot.pulse_length = 0xF8
		slot.cmd_length = 1
		slot.repeat_count = 0
		slot.pitch_adjust = 0

		var byte0: int = read_prg_byte(addr)
		slot.flags = 0x01 if byte0 < 0x30 else 0x00

		# Initial channel mute and sweep reset
		if apu != null:
			match slot_idx:
				SOUND_SLOT_BGM_PULSE1, SOUND_SLOT_SFX_PULSE1:
					write_channel_reg(apu, slot_idx, 0, 0x30)
					write_channel_reg(apu, slot_idx, 1, 0x7F)
				SOUND_SLOT_BGM_PULSE2:
					write_channel_reg(apu, slot_idx, 0, 0x30)
					write_channel_reg(apu, slot_idx, 1, 0x7F)
				SOUND_SLOT_BGM_TRI:
					write_channel_reg(apu, slot_idx, 0, 0x00)
				SOUND_SLOT_BGM_PERC, SOUND_SLOT_SFX_NOISE:
					write_channel_reg(apu, slot_idx, 0, 0x30)

	return true


## Parses low sound bytecode (< $30)
func parse_low_sound_cmd(apu: RefCounted, slot_idx: int) -> void:
	var slot: SoundSlot = slots[slot_idx]

	while slot.sound_code != 0:
		var byte: int = read_prg_byte(slot.cmd_addr)
		slot.cmd_addr += 1

		if byte >= 0xFD:
			if byte == 0xFD:
				# Subroutine / child call
				var lo: int = read_prg_byte(slot.cmd_addr)
				slot.cmd_addr += 1
				var hi: int = read_prg_byte(slot.cmd_addr)
				slot.cmd_addr += 1
				slot.return_addr = slot.cmd_addr
				slot.flags |= 0x08
				slot.cmd_addr = lo | (hi << 8)
				continue
			elif byte == 0xFE:
				# Repeat loop
				slot.repeat_count += 1
				var limit: int = read_prg_byte(slot.cmd_addr)
				slot.cmd_addr += 1
				var lo: int = read_prg_byte(slot.cmd_addr)
				slot.cmd_addr += 1
				var hi: int = read_prg_byte(slot.cmd_addr)
				slot.cmd_addr += 1
				if slot.repeat_count < limit:
					slot.cmd_addr = lo | (hi << 8)
				else:
					slot.repeat_count = 0
				continue
			elif byte == 0xFF:
				# Return from child or end of stream
				if (slot.flags & 0x08) != 0:
					slot.cmd_addr = slot.return_addr
					slot.flags &= ~0x08
					continue
				else:
					slot.sound_code = 0
					mute_channel(apu, slot_idx)
					break

		var hi_nib: int = byte & 0xF0
		if hi_nib == 0x20:
			# Case 1: Length multiplier and APU config high
			var lo: int = byte & 0x0F
			if lo == 0x0F:
				slot.length_multiplier = read_prg_byte(slot.cmd_addr)
				slot.cmd_addr += 1
			else:
				slot.length_multiplier = lo
			slot.cfg_high = read_prg_byte(slot.cmd_addr)
			slot.cmd_addr += 1
			continue
		elif hi_nib == 0x10:
			# Case 2: Sweep control
			if byte == 0x10:
				var sweep_val: int = read_prg_byte(slot.cmd_addr)
				slot.cmd_addr += 1
				if sweep_val != 0:
					write_channel_reg(apu, slot_idx, 1, sweep_val)
					if slot_idx == SOUND_SLOT_SFX_PULSE1:
						slot.vol_duration = sweep_val
				else:
					write_channel_reg(apu, slot_idx, 1, 0x7F)
			continue
		else:
			# Case 4: Note pitch and duration
			var vol: int = (byte >> 4) & 0x0F
			slot.cmd_length = slot.length_multiplier
			var lo: int = read_prg_byte(slot.cmd_addr)
			slot.cmd_addr += 1
			var hi: int = read_prg_byte(slot.cmd_addr)
			slot.cmd_addr += 1

			var cfg: int = slot.cfg_high | vol
			write_channel_reg(apu, slot_idx, 0, cfg)
			write_channel_reg(apu, slot_idx, 2, lo)
			write_channel_reg(apu, slot_idx, 3, hi)
			break


## Parses percussion bytecode on slot 3
func parse_percussion_cmd(apu: RefCounted, slot_idx: int) -> void:
	var slot: SoundSlot = slots[slot_idx]

	while slot.sound_code != 0:
		var byte: int = read_prg_byte(slot.cmd_addr)
		slot.cmd_addr += 1
		var hi_nib: int = byte & 0xF0

		if hi_nib == 0xF0:
			var lo: int = byte & 0x0F
			if lo == 0x0D:
				# Subroutine / child call
				var alo: int = read_prg_byte(slot.cmd_addr)
				slot.cmd_addr += 1
				var ahi: int = read_prg_byte(slot.cmd_addr)
				slot.cmd_addr += 1
				slot.return_addr = slot.cmd_addr
				slot.flags |= 0x08
				slot.cmd_addr = alo | (ahi << 8)
				continue
			elif lo == 0x0E:
				# Repeat loop
				slot.repeat_count += 1
				var limit: int = read_prg_byte(slot.cmd_addr)
				slot.cmd_addr += 1
				var alo: int = read_prg_byte(slot.cmd_addr)
				slot.cmd_addr += 1
				var ahi: int = read_prg_byte(slot.cmd_addr)
				slot.cmd_addr += 1
				if slot.repeat_count < limit:
					slot.cmd_addr = alo | (ahi << 8)
				else:
					slot.repeat_count = 0
				continue
			elif lo == 0x0F:
				if (slot.flags & 0x08) != 0:
					slot.cmd_addr = slot.return_addr
					slot.flags &= ~0x08
					continue
				else:
					slot.sound_code = 0
					mute_channel(apu, slot_idx)
					break
		elif hi_nib == 0xD0:
			slot.length_multiplier = byte & 0x0F
			continue
		else:
			# Case 3: Play percussion sound and calculate delay
			var factor: int = byte & 0x0F
			slot.cmd_length = slot.length_multiplier * (factor + 1)
			var perc_idx: int = (byte >> 4) & 0x0F
			if perc_idx < 8:
				var s_code: int = read_prg_offset(ROM_PERCUSSION_TABLE_OFFSET + perc_idx)
				play_sound(apu, s_code)
				if perc_idx >= 3:
					play_sound(apu, 0x02) # Percussive tick on noise channel
			break


## Parses high sound bytecode (BGM melodies >= $30)
func parse_high_sound_cmd(apu: RefCounted, slot_idx: int) -> void:
	var slot: SoundSlot = slots[slot_idx]

	while slot.sound_code != 0:
		var byte: int = read_prg_byte(slot.cmd_addr)
		slot.cmd_addr += 1
		var hi_nib: int = byte & 0xF0

		if hi_nib < 0xC0:
			# Simple sound command: Note pitch and length multiplier
			var factor: int = byte & 0x0F
			slot.cmd_length = slot.length_multiplier * (factor + 1)
			slot.decrescendo_pause = (factor * slot.cmd_length) >> 4

			if slot_idx == SOUND_SLOT_BGM_TRI:
				write_channel_reg(apu, slot_idx, 0, slot.triangle_cfg)
			else:
				# Pulse 1 / 2: Load volume envelope
				slot.vol_step_index = 0
				var env_ptr: int = ROM_PULSE_VOL_TABLE_OFFSET + slot.vol_env_index * 2
				var elo: int = read_prg_offset(env_ptr)
				var ehi: int = read_prg_offset(env_ptr + 1)
				var env_cpu: int = elo | (ehi << 8)
				var first_vol: int = read_prg_byte(env_cpu)
				slot.pulse_volume = first_vol & 0x1F
				write_channel_reg(apu, slot_idx, 0, slot.cfg_high | slot.pulse_volume)

			# Read note pitch from note_period_tbl
			var note_idx: int = ((byte & 0xF0) >> 3) + slot.pitch_adjust
			var note_off: int = ROM_NOTE_PERIOD_OFFSET + note_idx
			var lo: int = read_prg_offset(note_off)
			var hi: int = read_prg_offset(note_off + 1)
			var period: int = lo | (hi << 8)

			if slot.period_rotate != 4:
				period = period >> slot.period_rotate
			if (slot.flags & 0x10) != 0:
				period += 1

			write_channel_reg(apu, slot_idx, 2, period & 0xFF)
			write_channel_reg(apu, slot_idx, 3, (period >> 8) | 0x08)
			break
		else:
			# Regular sound command >= 0xC0
			var routine: int = (byte & 0x30) >> 4
			if routine == 0:
				# Routine 00: Mute channel
				var factor: int = byte & 0x0F
				slot.cmd_length = slot.length_multiplier * (factor + 1)
				slot.flags |= 0x40
				write_channel_reg(apu, slot_idx, 0, 0x00 if slot_idx == SOUND_SLOT_BGM_TRI else 0x30)
				break
			elif routine == 1:
				# Routine 01: Set Config
				slot.length_multiplier = byte & 0x0F
				var cfg_byte: int = read_prg_byte(slot.cmd_addr)
				slot.cmd_addr += 1
				if slot_idx == SOUND_SLOT_BGM_TRI:
					slot.triangle_cfg = cfg_byte
				else:
					slot.cfg_low = cfg_byte & 0x0F
					slot.cfg_high = cfg_byte & 0xF0
					slot.vol_env_index = read_prg_byte(slot.cmd_addr)
					slot.cmd_addr += 1
					var _unk: int = read_prg_byte(slot.cmd_addr)
					slot.cmd_addr += 1
				continue
			elif routine == 2:
				# Routine 02: Adjust pitch / vibrato
				var sub: int = byte & 0x0F
				if sub < 5:
					slot.period_rotate = sub
				elif sub == 8:
					slot.flags |= 0x10
				elif sub == 0x0B:
					slot.vibrato_ctrl = read_prg_byte(slot.cmd_addr)
					slot.cmd_addr += 1
				elif sub == 0x0C:
					slot.pitch_adjust = (read_prg_byte(slot.cmd_addr) * 2) & 0xFF
					slot.cmd_addr += 1
				continue
			elif routine == 3:
				# Routine 03: Flow control
				var sub: int = byte & 0x0F
				if sub == 0x0E:
					# Repeat loop
					slot.repeat_count += 1
					var limit: int = read_prg_byte(slot.cmd_addr)
					slot.cmd_addr += 1
					var lo: int = read_prg_byte(slot.cmd_addr)
					slot.cmd_addr += 1
					var hi: int = read_prg_byte(slot.cmd_addr)
					slot.cmd_addr += 1
					if slot.repeat_count < limit:
						slot.cmd_addr = lo | (hi << 8)
					else:
						slot.repeat_count = 0
					continue
				elif sub < 0x0E:
					# Child call
					var lo: int = read_prg_byte(slot.cmd_addr)
					slot.cmd_addr += 1
					var hi: int = read_prg_byte(slot.cmd_addr)
					slot.cmd_addr += 1
					slot.return_addr = slot.cmd_addr
					slot.flags |= 0x08
					slot.cmd_addr = lo | (hi << 8)
					continue
				else:
					# End of stream (0x0F)
					if (slot.flags & 0x08) != 0:
						slot.cmd_addr = slot.return_addr
						slot.flags &= ~0x08
						continue
					else:
						slot.sound_code = 0
						mute_channel(apu, slot_idx)
						break


## Updates sound sequencer state by one 60 Hz frame
func update_frame(apu: RefCounted) -> void:
	if not is_loaded:
		return

	for x in range(SOUND_SLOT_COUNT):
		var slot: SoundSlot = slots[x]
		if slot.sound_code == 0:
			continue

		if is_paused and slot.sound_code != 0x54:
			continue

		if slot.cmd_length > 0:
			slot.cmd_length -= 1

		if slot.cmd_length == 0:
			# Command finished: advance sequencer
			if (slot.flags & 0x01) != 0:
				parse_low_sound_cmd(apu, x)
			elif x == SOUND_SLOT_BGM_PERC:
				parse_percussion_cmd(apu, x)
			else:
				parse_high_sound_cmd(apu, x)
		else:
			# Active command: advance volume decay / envelope
			if x == SOUND_SLOT_BGM_PULSE1 or x == SOUND_SLOT_BGM_PULSE2 or x == SOUND_SLOT_SFX_PULSE1:
				if (slot.flags & 0x04) != 0:
					# Automatic decrescendo
					if slot.cmd_length < slot.decrescendo_pause and slot.pulse_volume > 0:
						slot.pulse_volume -= 1
						write_channel_reg(apu, x, 0, slot.cfg_high | slot.pulse_volume)
				else:
					# Envelope from pulse_volume_ptr_tbl
					var env_ptr: int = ROM_PULSE_VOL_TABLE_OFFSET + slot.vol_env_index * 2
					var elo: int = read_prg_offset(env_ptr)
					var ehi: int = read_prg_offset(env_ptr + 1)
					var env_cpu: int = elo | (ehi << 8)
					var next_vol: int = read_prg_byte(env_cpu + slot.vol_step_index)

					if next_vol >= 0xFE:
						slot.flags |= 0x04
					else:
						slot.vol_step_index += 1
						slot.pulse_volume = next_vol & 0x1F
						write_channel_reg(apu, x, 0, slot.cfg_high | slot.pulse_volume)

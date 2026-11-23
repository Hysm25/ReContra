class_name ApuSynthesizer
extends RefCounted

## Generic Ricoh 2A03 APU Synthesizer
## Emulates Pulse 1, Pulse 2, Triangle, Noise, and 1-bit DMC/DPCM sound synthesis.
## Mixes output through the authentic NES non-linear curve and DC-blocking high-pass filter.
## Generates 48 kHz PackedVector2Array frames for AudioStreamGenerator and PackedFloat32Array for tests.

# --- Constants: Timing & Clocks ---
const APU_DEFAULT_SAMPLE_RATE: int = 48000
const APU_NTSC_CPU_CLOCK: int = 1789773
const APU_FRAME_QUARTER_CYCLES: int = 7457

# --- Constants: APU Register Memory Map ---
const APU_REG_PULSE1_CTRL: int = 0x4000
const APU_REG_PULSE1_SWEEP: int = 0x4001
const APU_REG_PULSE1_TIMER_LO: int = 0x4002
const APU_REG_PULSE1_TIMER_HI: int = 0x4003

const APU_REG_PULSE2_CTRL: int = 0x4004
const APU_REG_PULSE2_SWEEP: int = 0x4005
const APU_REG_PULSE2_TIMER_LO: int = 0x4006
const APU_REG_PULSE2_TIMER_HI: int = 0x4007

const APU_REG_TRI_CTRL: int = 0x4008
const APU_REG_TRI_TIMER_LO: int = 0x400A
const APU_REG_TRI_TIMER_HI: int = 0x400B

const APU_REG_NOISE_CTRL: int = 0x400C
const APU_REG_NOISE_PERIOD: int = 0x400E
const APU_REG_NOISE_LENGTH: int = 0x400F

const APU_REG_DMC_CTRL: int = 0x4010
const APU_REG_DMC_DIRECT: int = 0x4011
const APU_REG_DMC_ADDR: int = 0x4012
const APU_REG_DMC_LENGTH: int = 0x4013

const APU_REG_STATUS: int = 0x4015
const APU_REG_FRAME_COUNTER: int = 0x4017

# --- Constants: Synthesis Lookup Tables ---
const LENGTH_TABLE: PackedByteArray = [
	10, 254, 20, 2, 40, 4, 80, 6, 160, 8, 60, 10, 14, 12, 26, 14,
	12, 16, 24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30
]

const DUTY_TABLE: Array = [
	[0, 1, 0, 0, 0, 0, 0, 0], # 12.5%
	[0, 1, 1, 0, 0, 0, 0, 0], # 25.0%
	[0, 1, 1, 1, 1, 0, 0, 0], # 50.0%
	[1, 0, 0, 1, 1, 1, 1, 1]  # 75.0% / inverted 25%
]

const TRIANGLE_TABLE: PackedByteArray = [
	15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0,
	0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
]

const NOISE_PERIODS: PackedInt32Array = [
	4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068
]

const DMC_PERIODS: PackedInt32Array = [
	428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106, 84, 72, 54
]

# --- Nested Classes: Channel Definitions ---
class PulseChannel extends RefCounted:
	var enabled: bool = false
	var duty: int = 0
	var length_halt: bool = false
	var constant_vol: bool = false
	var volume: int = 0
	var envelope_divider: int = 0
	var envelope_counter: int = 0
	var envelope_start: bool = false

	var sweep_enabled: bool = false
	var sweep_period: int = 0
	var sweep_negate: bool = false
	var sweep_shift: int = 0
	var sweep_divider: int = 0
	var sweep_reload: bool = false

	var timer_period: int = 0
	var timer_counter: float = 0.0
	var sequence_step: int = 0
	var length_counter: int = 0
	var is_pulse2: bool = false

	func target_period() -> int:
		var delta: int = timer_period >> sweep_shift
		if sweep_negate:
			if is_pulse2:
				return (timer_period - delta) if timer_period >= delta else 0
			else:
				return (timer_period - delta - 1) if timer_period > delta else 0
		else:
			return timer_period + delta

	func is_muted() -> bool:
		if timer_period < 8:
			return true
		var target: int = target_period()
		if target > 0x07FF:
			return true
		return false

	func clock_envelope() -> void:
		if envelope_start:
			envelope_start = false
			envelope_counter = 15
			envelope_divider = volume
		else:
			if envelope_divider == 0:
				envelope_divider = volume
				if envelope_counter > 0:
					envelope_counter -= 1
				elif length_halt:
					envelope_counter = 15
			else:
				envelope_divider -= 1

	func clock_sweep() -> void:
		if sweep_reload:
			sweep_divider = sweep_period
			sweep_reload = false
		elif sweep_divider > 0:
			sweep_divider -= 1
		else:
			sweep_divider = sweep_period
			if sweep_enabled and sweep_shift > 0 and not is_muted():
				timer_period = target_period()


class TriangleChannel extends RefCounted:
	var enabled: bool = false
	var control_flag: bool = false
	var linear_reload_val: int = 0
	var linear_counter: int = 0
	var linear_reload_flag: bool = false

	var timer_period: int = 0
	var timer_counter: float = 0.0
	var sequence_step: int = 0
	var length_counter: int = 0

	func clock_linear() -> void:
		if linear_reload_flag:
			linear_counter = linear_reload_val
		elif linear_counter > 0:
			linear_counter -= 1
		if not control_flag:
			linear_reload_flag = false


class NoiseChannel extends RefCounted:
	var enabled: bool = false
	var length_halt: bool = false
	var constant_vol: bool = false
	var volume: int = 0
	var envelope_divider: int = 0
	var envelope_counter: int = 0
	var envelope_start: bool = false

	var mode: bool = false
	var period_idx: int = 0
	var timer_period: int = 4
	var timer_counter: float = 0.0
	var lfsr: int = 1
	var length_counter: int = 0

	func clock_envelope() -> void:
		if envelope_start:
			envelope_start = false
			envelope_counter = 15
			envelope_divider = volume
		else:
			if envelope_divider == 0:
				envelope_divider = volume
				if envelope_counter > 0:
					envelope_counter -= 1
				elif length_halt:
					envelope_counter = 15
			else:
				envelope_divider -= 1


class DmcChannel extends RefCounted:
	var enabled: bool = false
	var loop: bool = false
	var irq_enabled: bool = false
	var rate_idx: int = 0
	var rate_period: int = 428
	var timer_counter: float = 0.0
	var output_level: int = 0

	var sample_addr_cpu: int = 0xC000
	var sample_len_bytes: int = 1
	var current_addr: int = 0xC000
	var bytes_remaining: int = 0
	var shift_reg: int = 0
	var bits_remaining: int = 0
	var silence: bool = true

	var sample_memory: PackedByteArray = PackedByteArray()


# --- Synthesizer State ---
var pulse1: PulseChannel = PulseChannel.new()
var pulse2: PulseChannel = PulseChannel.new()
var triangle: TriangleChannel = TriangleChannel.new()
var noise: NoiseChannel = NoiseChannel.new()
var dmc: DmcChannel = DmcChannel.new()

var sample_rate: int = APU_DEFAULT_SAMPLE_RATE
var cycles_per_sample: float = float(APU_NTSC_CPU_CLOCK) / float(APU_DEFAULT_SAMPLE_RATE)
var dc_filter_in: float = 0.0
var dc_filter_out: float = 0.0

var frame_cycles: int = 0
var frame_step: int = 0
var frame_5step: bool = false


func _init(target_sample_rate: int = APU_DEFAULT_SAMPLE_RATE) -> void:
	pulse2.is_pulse2 = true
	sample_rate = target_sample_rate if target_sample_rate > 0 else APU_DEFAULT_SAMPLE_RATE
	cycles_per_sample = float(APU_NTSC_CPU_CLOCK) / float(sample_rate)
	reset()


## Resets APU synthesizer channels and state
func reset() -> void:
	var old_dmc_mem: PackedByteArray = dmc.sample_memory

	pulse1 = PulseChannel.new()
	pulse2 = PulseChannel.new()
	pulse2.is_pulse2 = true
	triangle = TriangleChannel.new()
	noise = NoiseChannel.new()
	noise.lfsr = 1
	noise.timer_period = NOISE_PERIODS[0]
	dmc = DmcChannel.new()
	dmc.rate_period = DMC_PERIODS[0]
	dmc.silence = true
	dmc.sample_memory = old_dmc_mem

	dc_filter_in = 0.0
	dc_filter_out = 0.0
	frame_cycles = 0
	frame_step = 0
	frame_5step = false


## Ingests sample memory buffer for DMC playback (Bank 7 16 KB or PRG ROM 128 KB)
func set_dmc_memory(mem: PackedByteArray) -> void:
	dmc.sample_memory = mem


## Writes to an APU register ($4000-$4017)
func write_register(reg: int, val: int) -> void:
	match reg:
		# Pulse 1
		APU_REG_PULSE1_CTRL:
			pulse1.duty = (val >> 6) & 0x03
			pulse1.length_halt = (val & 0x20) != 0
			pulse1.constant_vol = (val & 0x10) != 0
			pulse1.volume = val & 0x0F
		APU_REG_PULSE1_SWEEP:
			pulse1.sweep_enabled = (val & 0x80) != 0
			pulse1.sweep_period = (val >> 4) & 0x07
			pulse1.sweep_negate = (val & 0x08) != 0
			pulse1.sweep_shift = val & 0x07
			pulse1.sweep_reload = true
		APU_REG_PULSE1_TIMER_LO:
			pulse1.timer_period = (pulse1.timer_period & 0x0700) | (val & 0xFF)
		APU_REG_PULSE1_TIMER_HI:
			pulse1.timer_period = (pulse1.timer_period & 0x00FF) | ((val & 0x07) << 8)
			if pulse1.enabled:
				pulse1.length_counter = LENGTH_TABLE[(val >> 3) & 0x1F]
			pulse1.sequence_step = 0
			pulse1.envelope_start = true

		# Pulse 2
		APU_REG_PULSE2_CTRL:
			pulse2.duty = (val >> 6) & 0x03
			pulse2.length_halt = (val & 0x20) != 0
			pulse2.constant_vol = (val & 0x10) != 0
			pulse2.volume = val & 0x0F
		APU_REG_PULSE2_SWEEP:
			pulse2.sweep_enabled = (val & 0x80) != 0
			pulse2.sweep_period = (val >> 4) & 0x07
			pulse2.sweep_negate = (val & 0x08) != 0
			pulse2.sweep_shift = val & 0x07
			pulse2.sweep_reload = true
		APU_REG_PULSE2_TIMER_LO:
			pulse2.timer_period = (pulse2.timer_period & 0x0700) | (val & 0xFF)
		APU_REG_PULSE2_TIMER_HI:
			pulse2.timer_period = (pulse2.timer_period & 0x00FF) | ((val & 0x07) << 8)
			if pulse2.enabled:
				pulse2.length_counter = LENGTH_TABLE[(val >> 3) & 0x1F]
			pulse2.sequence_step = 0
			pulse2.envelope_start = true

		# Triangle
		APU_REG_TRI_CTRL:
			triangle.control_flag = (val & 0x80) != 0
			triangle.linear_reload_val = val & 0x7F
		APU_REG_TRI_TIMER_LO:
			triangle.timer_period = (triangle.timer_period & 0x0700) | (val & 0xFF)
		APU_REG_TRI_TIMER_HI:
			triangle.timer_period = (triangle.timer_period & 0x00FF) | ((val & 0x07) << 8)
			if triangle.enabled:
				triangle.length_counter = LENGTH_TABLE[(val >> 3) & 0x1F]
			triangle.linear_reload_flag = true

		# Noise
		APU_REG_NOISE_CTRL:
			noise.length_halt = (val & 0x20) != 0
			noise.constant_vol = (val & 0x10) != 0
			noise.volume = val & 0x0F
		APU_REG_NOISE_PERIOD:
			noise.mode = (val & 0x80) != 0
			noise.period_idx = val & 0x0F
			noise.timer_period = NOISE_PERIODS[noise.period_idx]
		APU_REG_NOISE_LENGTH:
			if noise.enabled:
				noise.length_counter = LENGTH_TABLE[(val >> 3) & 0x1F]
			noise.envelope_start = true

		# DMC
		APU_REG_DMC_CTRL:
			dmc.irq_enabled = (val & 0x80) != 0
			dmc.loop = (val & 0x40) != 0
			dmc.rate_idx = val & 0x0F
			dmc.rate_period = DMC_PERIODS[dmc.rate_idx]
		APU_REG_DMC_DIRECT:
			dmc.output_level = val & 0x7F
		APU_REG_DMC_ADDR:
			dmc.sample_addr_cpu = 0xC000 + ((val & 0xFF) << 6)
		APU_REG_DMC_LENGTH:
			dmc.sample_len_bytes = ((val & 0xFF) << 4) + 1

		# Status Control
		APU_REG_STATUS:
			pulse1.enabled = (val & 0x01) != 0
			if not pulse1.enabled:
				pulse1.length_counter = 0

			pulse2.enabled = (val & 0x02) != 0
			if not pulse2.enabled:
				pulse2.length_counter = 0

			triangle.enabled = (val & 0x04) != 0
			if not triangle.enabled:
				triangle.length_counter = 0

			noise.enabled = (val & 0x08) != 0
			if not noise.enabled:
				noise.length_counter = 0

			if (val & 0x10) != 0:
				dmc.enabled = true
				if dmc.bytes_remaining == 0:
					dmc.current_addr = dmc.sample_addr_cpu
					dmc.bytes_remaining = dmc.sample_len_bytes
					dmc.silence = false
			else:
				dmc.enabled = false
				dmc.bytes_remaining = 0
				dmc.silence = true

		# Frame Counter
		APU_REG_FRAME_COUNTER:
			frame_5step = (val & 0x80) != 0
			frame_step = 0
			frame_cycles = 0
			if frame_5step:
				clock_frame_quarter()
				clock_frame_half()


## Reads APU status register ($4015)
func read_status() -> int:
	var st: int = 0
	if pulse1.length_counter > 0:
		st |= 0x01
	if pulse2.length_counter > 0:
		st |= 0x02
	if triangle.length_counter > 0:
		st |= 0x04
	if noise.length_counter > 0:
		st |= 0x08
	if dmc.bytes_remaining > 0:
		st |= 0x10
	return st


## Advances quarter-frame units (envelopes and triangle linear counter)
func clock_frame_quarter() -> void:
	pulse1.clock_envelope()
	pulse2.clock_envelope()
	noise.clock_envelope()
	triangle.clock_linear()


## Advances half-frame units (length counters and pulse sweep units)
func clock_frame_half() -> void:
	if not pulse1.length_halt and pulse1.length_counter > 0:
		pulse1.length_counter -= 1
	if not pulse2.length_halt and pulse2.length_counter > 0:
		pulse2.length_counter -= 1
	if not triangle.control_flag and triangle.length_counter > 0:
		triangle.length_counter -= 1
	if not noise.length_halt and noise.length_counter > 0:
		noise.length_counter -= 1

	pulse1.clock_sweep()
	pulse2.clock_sweep()


## Generates audio samples as PackedVector2Array (for AudioStreamGenerator stereo output)
func generate_samples(count: int) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if count <= 0:
		return out
	out.resize(count)

	for s in range(count):
		var filtered: float = _synthesize_single_sample()
		out[s] = Vector2(filtered, filtered)

	return out


## Generates raw mono audio samples as PackedFloat32Array (for headless verification and CRC-32 testing)
func generate_samples_float(count: int) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	if count <= 0:
		return out
	out.resize(count)

	for s in range(count):
		out[s] = _synthesize_single_sample()

	return out


## Synthesizes a single 48 kHz audio sample through all channels and the non-linear mixer
func _synthesize_single_sample() -> float:
	# Advance frame sequencer
	frame_cycles += int(cycles_per_sample)
	while frame_cycles >= APU_FRAME_QUARTER_CYCLES:
		frame_cycles -= APU_FRAME_QUARTER_CYCLES
		frame_step += 1
		if not frame_5step:
			match frame_step & 0x03:
				1:
					clock_frame_quarter()
				2:
					clock_frame_quarter()
					clock_frame_half()
				3:
					clock_frame_quarter()
				0:
					clock_frame_quarter()
					clock_frame_half()
		else:
			match frame_step % 5:
				1:
					clock_frame_quarter()
				2:
					clock_frame_quarter()
					clock_frame_half()
				3:
					clock_frame_quarter()
				4:
					pass
				0:
					clock_frame_quarter()
					clock_frame_half()

	# 1. Pulse 1 Channel
	var pulse1_out: int = 0
	if pulse1.enabled and pulse1.length_counter > 0 and not pulse1.is_muted():
		pulse1.timer_counter -= cycles_per_sample * 0.5
		while pulse1.timer_counter <= 0.0:
			pulse1.timer_counter += float(pulse1.timer_period + 1)
			pulse1.sequence_step = (pulse1.sequence_step + 1) & 0x07
		if DUTY_TABLE[pulse1.duty][pulse1.sequence_step] != 0:
			pulse1_out = pulse1.volume if pulse1.constant_vol else pulse1.envelope_counter

	# 2. Pulse 2 Channel
	var pulse2_out: int = 0
	if pulse2.enabled and pulse2.length_counter > 0 and not pulse2.is_muted():
		pulse2.timer_counter -= cycles_per_sample * 0.5
		while pulse2.timer_counter <= 0.0:
			pulse2.timer_counter += float(pulse2.timer_period + 1)
			pulse2.sequence_step = (pulse2.sequence_step + 1) & 0x07
		if DUTY_TABLE[pulse2.duty][pulse2.sequence_step] != 0:
			pulse2_out = pulse2.volume if pulse2.constant_vol else pulse2.envelope_counter

	# 3. Triangle Channel
	var tri_out: int = 0
	if triangle.enabled and triangle.length_counter > 0 and triangle.linear_counter > 0:
		triangle.timer_counter -= cycles_per_sample
		while triangle.timer_counter <= 0.0:
			triangle.timer_counter += float(triangle.timer_period + 1)
			if triangle.timer_period > 2:
				triangle.sequence_step = (triangle.sequence_step + 1) & 0x1F
		tri_out = TRIANGLE_TABLE[triangle.sequence_step]

	# 4. Noise Channel
	var noise_out: int = 0
	if noise.enabled and noise.length_counter > 0:
		noise.timer_counter -= cycles_per_sample
		while noise.timer_counter <= 0.0:
			noise.timer_counter += float(noise.timer_period)
			var feedback: int = (noise.lfsr & 1) ^ (((noise.lfsr >> 6) & 1) if noise.mode else ((noise.lfsr >> 1) & 1))
			noise.lfsr = (noise.lfsr >> 1) | (feedback << 14)
		if (noise.lfsr & 1) == 0:
			noise_out = noise.volume if noise.constant_vol else noise.envelope_counter

	# 5. DMC / DPCM Channel
	if dmc.enabled and dmc.bytes_remaining > 0:
		dmc.timer_counter -= cycles_per_sample
		while dmc.timer_counter <= 0.0:
			dmc.timer_counter += float(dmc.rate_period)
			if dmc.bits_remaining == 0:
				if dmc.bytes_remaining > 0 and not dmc.sample_memory.is_empty():
					var prg_offset: int = 0
					if dmc.sample_memory.size() > 16384:
						prg_offset = 0x1C000 + (dmc.current_addr - 0xC000)
					else:
						prg_offset = dmc.current_addr - 0xC000

					if prg_offset >= 0 and prg_offset < dmc.sample_memory.size():
						dmc.shift_reg = dmc.sample_memory[prg_offset]
					else:
						dmc.shift_reg = 0

					dmc.current_addr += 1
					if dmc.current_addr > 0xFFFF:
						dmc.current_addr = 0x8000
					dmc.bytes_remaining -= 1
					dmc.bits_remaining = 8
					dmc.silence = false
				elif dmc.loop:
					dmc.current_addr = dmc.sample_addr_cpu
					dmc.bytes_remaining = dmc.sample_len_bytes
				else:
					dmc.silence = true

			if not dmc.silence and dmc.bits_remaining > 0:
				var bit: int = dmc.shift_reg & 0x01
				dmc.shift_reg >>= 1
				dmc.bits_remaining -= 1
				if bit != 0:
					if dmc.output_level <= 125:
						dmc.output_level += 2
				else:
					if dmc.output_level >= 2:
						dmc.output_level -= 2

	var dmc_out: int = dmc.output_level

	# Non-linear NES Mixer Curves
	var pulse_sum: float = float(pulse1_out + pulse2_out)
	var pulse_out: float = 0.0
	if pulse_sum > 0.0:
		pulse_out = 95.88 / ((8128.0 / pulse_sum) + 100.0)

	var tnd_sum: float = (float(tri_out) / 8227.0) + (float(noise_out) / 12241.0) + (float(dmc_out) / 22638.0)
	var tnd_out: float = 0.0
	if tnd_sum > 0.0:
		tnd_out = 159.79 / ((1.0 / tnd_sum) + 100.0)

	var mixed: float = (pulse_out + tnd_out) * 1.8 - 0.4

	# High-pass DC Blocking Filter
	var filtered: float = mixed - dc_filter_in + 0.995 * dc_filter_out
	dc_filter_in = mixed
	dc_filter_out = filtered

	# Clamped output
	return clampf(filtered, -1.0, 1.0)

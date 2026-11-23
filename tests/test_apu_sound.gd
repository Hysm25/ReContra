class_name TestApuSound
extends RefCounted

## Modular Test Suite: Ricoh 2A03 APU Synthesizer & 6-Slot Audio Engine (23 Tests)

const ApuSynthesizerScript = preload("res://src/audio/apu_synthesizer.gd")
const SoundEngineScript = preload("res://src/audio/sound_engine.gd")
const RomLoaderScript = preload("res://src/rom/rom_loader.gd")


static func run(runner: Object, loader: RefCounted) -> bool:
	print("\n--- 5. Ricoh 2A03 APU Synthesizer & 6-Slot Audio Engine ---")
	var apu = ApuSynthesizerScript.new()
	runner.assert_test("APU Initialized at 48000 Hz", apu.sample_rate == 48000)

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
	runner.assert_test("Pulse 1 Non-Silent Tone Generation", pulse_energy > 0.05, "Energy: %f" % pulse_energy)

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
	runner.assert_test("Triangle Non-Silent Tone Generation", tri_energy > 0.05, "Energy: %f" % tri_energy)

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
	runner.assert_test("Noise Non-Silent Waveform Generation", noise_energy > 0.05, "Energy: %f" % noise_energy)

	# 4. DPCM Sample Extraction & DMC Playback
	apu.reset()
	var bank7_prg: PackedByteArray = loader.get_bank(7)
	apu.set_dmc_memory(bank7_prg)

	var sound_engine = SoundEngineScript.new()
	var engine_ok: bool = sound_engine.init_engine(loader)
	runner.assert_test("Sound Engine Initialized with ROM", engine_ok)

	var play_dmc_ok: bool = sound_engine.play_sound(apu, 0x5B) # Snare drum sample
	runner.assert_test("Trigger DPCM Percussion 0x5B", play_dmc_ok)
	runner.assert_test("DMC Channel Enabled", apu.dmc.enabled)
	runner.assert_test("DPCM Sample 0x5B Byte Length == 593", apu.dmc.bytes_remaining == 593, "Got: %d" % apu.dmc.bytes_remaining)

	var dmc_samples: PackedFloat32Array = apu.generate_samples_float(800)
	var dmc_energy: float = 0.0
	for s in dmc_samples:
		dmc_energy += s * s
	print("  DMC Playback Energy: %f (remaining bytes: %d)" % [dmc_energy, apu.dmc.bytes_remaining])
	runner.assert_test("DMC Sample Playback Audio Energy", dmc_energy > 0.01, "Energy: %f" % dmc_energy)
	runner.assert_test("DMC Bytes Remaining Decreased", apu.dmc.bytes_remaining < 593, "Remaining: %d" % apu.dmc.bytes_remaining)

	# 5. Sound Engine Bytecode Execution: Stage 1 Jungle BGM (Sound 0x2A)
	apu.reset()
	apu.set_dmc_memory(bank7_prg)
	sound_engine.reset_engine()

	var bgm_ok: bool = sound_engine.play_sound(apu, 0x2A)
	runner.assert_test("Trigger Stage 1 BGM 0x2A", bgm_ok)
	runner.assert_test("Slot 0 BGM Pulse 1 Assigned", sound_engine.slots[SoundEngineScript.SOUND_SLOT_BGM_PULSE1].sound_code == 0x2A)
	runner.assert_test("Slot 1 BGM Pulse 2 Assigned", sound_engine.slots[SoundEngineScript.SOUND_SLOT_BGM_PULSE2].sound_code == 0x2A)
	runner.assert_test("Slot 2 BGM Triangle Assigned", sound_engine.slots[SoundEngineScript.SOUND_SLOT_BGM_TRI].sound_code == 0x2A)
	runner.assert_test("Slot 3 BGM Percussion Assigned", sound_engine.slots[SoundEngineScript.SOUND_SLOT_BGM_PERC].sound_code == 0x2A)

	# Simulate 120 frames (~2 seconds) of BGM playback
	var total_bgm_energy: float = 0.0
	for _f in range(120):
		sound_engine.update_frame(apu)
		var fbuf: PackedFloat32Array = apu.generate_samples_float(799)
		for s in fbuf:
			total_bgm_energy += s * s

	print("  Stage 1 BGM (120 frames) Total Synthesized Energy: %f" % total_bgm_energy)
	runner.assert_test("BGM Substantial Audio Energy Across 120 Frames", total_bgm_energy > 10.0, "Energy: %f" % total_bgm_energy)

	# 6. Slot Priority Arbitration: SFX Slot 4 over BGM Slot 0
	var sfx_ok: bool = sound_engine.play_sound(apu, 0x0A) # Weapon SFX
	runner.assert_test("Trigger SFX 0x0A on Slot 4", sfx_ok)
	runner.assert_test("Slot 4 Active with SFX 0x0A", sound_engine.slots[SoundEngineScript.SOUND_SLOT_SFX_PULSE1].sound_code == 0x0A)

	sound_engine.update_frame(apu)
	runner.assert_test("Slot 4 Remains Active During Execution", sound_engine.slots[SoundEngineScript.SOUND_SLOT_SFX_PULSE1].sound_code == 0x0A)

	# 7. AudioStreamGenerator Stereo Vector2 Format
	var stereo_frames: PackedVector2Array = apu.generate_samples(100)
	runner.assert_test("AudioStreamGenerator Frame Count == 100", stereo_frames.size() == 100)
	runner.assert_test("Stereo Balanced Channels (L == R)", stereo_frames[0].x == stereo_frames[0].y)

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
	runner.assert_test("Audio Simulation Deterministic Checksum Match", crc_run1 == crc_run2)
	runner.assert_test("Audio Simulation Checksum Non-Zero", crc_run1 != 0)

	return true

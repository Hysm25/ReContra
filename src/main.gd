class_name Main
extends Control

## Main Scene Controller & Interactive Game Runner
## Displays 256x240 software framebuffer on TextureRect, streams audio via
## AudioStreamGenerator, and arbitrates input across keyboard, gamepad, and touch controls.

const RomLoaderScript = preload("res://src/rom/rom_loader.gd")
const PpuRendererScript = preload("res://src/render/ppu_renderer.gd")
const ApuSynthesizerScript = preload("res://src/audio/apu_synthesizer.gd")
const SoundEngineScript = preload("res://src/audio/sound_engine.gd")
const GameLoopScript = preload("res://src/game/game_loop.gd")
const PlayerScript = preload("res://src/game/player.gd")

const NTSC_FRAME_DURATION: float = 1.0 / 60.0988
const MAX_DELTA_CLAMP: float = 2.0 / 60.0988
const REALTIME_AUDIO_SAMPLE_RATE: float = 24000.0
const MAX_AUDIO_CHUNK_FRAMES: int = 1024

@onready var texture_rect: TextureRect = $Screen
@onready var audio_player: AudioStreamPlayer = $AudioPlayer
@onready var touch_controls: Control = $TouchControls
@onready var file_dialog: FileDialog = $FileDialog

var rom_loader: RefCounted = null
var ppu: RefCounted = null
var apu: RefCounted = null
var sound_engine: RefCounted = null
var game_loop: RefCounted = null

var fb_texture: ImageTexture = null
var audio_generator: AudioStreamGenerator = null
var audio_playback: AudioStreamGeneratorPlayback = null

var touch_input_mask: int = 0
var is_game_running: bool = false
var sim_accumulator: float = 0.0


func _ready() -> void:
	_setup_audio()
	_setup_touch_controls()

	var rom_path: String = _discover_rom()
	if not rom_path.is_empty():
		_start_game(rom_path)
	else:
		_prompt_for_rom()


## Configures 24 kHz stereo AudioStreamGenerator playback
func _setup_audio() -> void:
	audio_generator = AudioStreamGenerator.new()
	audio_generator.mix_rate = REALTIME_AUDIO_SAMPLE_RATE
	audio_generator.buffer_length = 0.08
	audio_player.stream = audio_generator
	audio_player.play()
	audio_playback = audio_player.get_stream_playback()


## Detects touch screen availability and shows virtual controls if applicable
func _setup_touch_controls() -> void:
	if touch_controls == null:
		return
	var show_touch: bool = DisplayServer.is_touchscreen_available() \
		or OS.has_feature("mobile") \
		or OS.has_feature("web_android") \
		or OS.has_feature("web_ios")

	for arg in OS.get_cmdline_args():
		if arg == "--touch" or arg == "--show-touch":
			show_touch = true
			break
	for arg in OS.get_cmdline_user_args():
		if arg == "--touch" or arg == "--show-touch":
			show_touch = true
			break

	touch_controls.visible = show_touch


func _unhandled_input(event: InputEvent) -> void:
	# Toggle on-screen touch controls on desktop with T or F1 key
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T or event.keycode == KEY_F1:
			if touch_controls != null:
				touch_controls.visible = not touch_controls.visible


## Discovers ROM in standard local paths
func _discover_rom() -> String:
	var candidates: Array[String] = [
		"Contra.nes",
		"contra.nes",
		"res://Contra.nes",
		"res://contra.nes",
		"Contra (USA).nes",
		"/sdcard/Documents/Codes/ReContra/Contra.nes",
		"/sdcard/Documents/Codes/ReContra/contra.nes",
		"user://Contra.nes",
		"user://contra.nes"
	]
	for c in candidates:
		if FileAccess.file_exists(c):
			return c
	return ""


## Prompts user with FileDialog fallback
func _prompt_for_rom() -> void:
	if file_dialog != null:
		file_dialog.file_selected.connect(_start_game)
		file_dialog.popup_centered()


## Loads ROM and initializes 60 Hz GameLoop
func _start_game(path: String) -> void:
	rom_loader = RomLoaderScript.new()
	var err: Error = rom_loader.load_from_file(path)
	if err != OK:
		printerr("Failed to load ROM: %s (Error code: %d)" % [path, err])
		return

	ppu = PpuRendererScript.new()
	apu = ApuSynthesizerScript.new(int(REALTIME_AUDIO_SAMPLE_RATE))
	apu.set_dmc_memory(rom_loader.get_bank(7))

	sound_engine = SoundEngineScript.new()
	sound_engine.init_engine(rom_loader)

	game_loop = GameLoopScript.new(rom_loader, ppu, apu, sound_engine)
	game_loop.load_level(0) # Stage 1 Jungle

	var img: Image = ppu.get_framebuffer_image()
	fb_texture = ImageTexture.create_from_image(img)
	texture_rect.texture = fb_texture

	sim_accumulator = 0.0
	is_game_running = true


func _process(delta: float) -> void:
	if not is_game_running or game_loop == null:
		return

	# Clamp delta to prevent frame-accumulation spiral of death during lag spikes
	var clamped_delta: float = minf(delta, MAX_DELTA_CLAMP)
	sim_accumulator += clamped_delta

	var stepped: bool = false
	while sim_accumulator >= NTSC_FRAME_DURATION:
		sim_accumulator -= NTSC_FRAME_DURATION
		var input_mask: int = _gather_input()
		game_loop.tick(input_mask)
		stepped = true

	# Update screen texture in-place when simulation advanced
	if stepped and fb_texture != null and ppu != null:
		ppu.update_texture(fb_texture)

	# Stream audio frames up to available buffer space, capped per frame
	if apu != null and audio_playback != null:
		var frames_avail: int = audio_playback.get_frames_available()
		if frames_avail > 0:
			var frames_to_generate: int = mini(frames_avail, MAX_AUDIO_CHUNK_FRAMES)
			var frames: PackedVector2Array = apu.generate_stereo_frames(frames_to_generate)
			audio_playback.push_buffer(frames)


## Gathers composite bitmask from keyboard, gamepad, and touch input
func _gather_input() -> int:
	var mask: int = 0
	if touch_controls != null and touch_controls.visible:
		mask |= touch_controls.get_input_mask()

	# Directional buttons (Arrows / WASD / D-Pad)
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D) or Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_RIGHT):
		mask |= PlayerScript.INPUT_RIGHT
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A) or Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_LEFT):
		mask |= PlayerScript.INPUT_LEFT
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S) or Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_DOWN):
		mask |= PlayerScript.INPUT_DOWN
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W) or Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_UP):
		mask |= PlayerScript.INPUT_UP

	# Action buttons: Z/K = Jump (A), X/J = Fire (B)
	if Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_K) or Input.is_joy_button_pressed(0, JOY_BUTTON_A):
		mask |= PlayerScript.INPUT_A
	if Input.is_key_pressed(KEY_X) or Input.is_key_pressed(KEY_J) or Input.is_joy_button_pressed(0, JOY_BUTTON_X):
		mask |= PlayerScript.INPUT_B

	# Meta buttons: Enter = Start, Shift = Select
	if Input.is_key_pressed(KEY_ENTER) or Input.is_joy_button_pressed(0, JOY_BUTTON_START):
		mask |= PlayerScript.INPUT_START
	if Input.is_key_pressed(KEY_SHIFT) or Input.is_joy_button_pressed(0, JOY_BUTTON_BACK):
		mask |= PlayerScript.INPUT_SELECT

	return mask

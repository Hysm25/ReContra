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


func _ready() -> void:
	_setup_audio()
	_setup_touch_controls()

	var rom_path: String = _discover_rom()
	if not rom_path.is_empty():
		_start_game(rom_path)
	else:
		_prompt_for_rom()


## Configures 48 kHz stereo AudioStreamGenerator playback
func _setup_audio() -> void:
	audio_generator = AudioStreamGenerator.new()
	audio_generator.mix_rate = 48000.0
	audio_generator.buffer_length = 0.1
	audio_player.stream = audio_generator
	audio_player.play()
	audio_playback = audio_player.get_stream_playback()


## Detects touch screen availability and shows virtual controls if applicable
func _setup_touch_controls() -> void:
	if touch_controls == null:
		return
	var is_touch: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	touch_controls.visible = is_touch


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
	apu = ApuSynthesizerScript.new(48000)
	apu.set_dmc_memory(rom_loader.get_bank(7))

	sound_engine = SoundEngineScript.new()
	sound_engine.init_engine(rom_loader)

	game_loop = GameLoopScript.new(rom_loader, ppu, apu, sound_engine)
	game_loop.load_level(0) # Stage 1 Jungle

	var img: Image = ppu.get_framebuffer_image()
	fb_texture = ImageTexture.create_from_image(img)
	texture_rect.texture = fb_texture

	is_game_running = true


func _physics_process(_delta: float) -> void:
	if not is_game_running or game_loop == null:
		return

	var input_mask: int = _gather_input()
	game_loop.tick(input_mask)

	# Update screen texture
	var img: Image = ppu.get_framebuffer_image()
	if fb_texture != null:
		fb_texture.update(img)


func _process(_delta: float) -> void:
	if not is_game_running or apu == null or audio_playback == null:
		return

	# Fill audio playback buffer with synthesized samples
	var frames_avail: int = audio_playback.get_frames_available()
	if frames_avail > 0:
		var frames: PackedVector2Array = apu.generate_samples(frames_avail)
		audio_playback.push_buffer(frames)


## Gathers composite bitmask from keyboard, gamepad, and touch input
func _gather_input() -> int:
	var mask: int = touch_input_mask

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

class_name TouchControls
extends Control

## Generic Multi-Touch Virtual Controls Overlay
## Renders clean, semi-transparent vector controls for D-Pad, A, B, Select, and Start.
## Tracks simultaneous multi-touch pointers and mouse clicks, generating composite input masks.

const INPUT_RIGHT: int = 0x01
const INPUT_LEFT: int = 0x02
const INPUT_DOWN: int = 0x04
const INPUT_UP: int = 0x08
const INPUT_START: int = 0x10
const INPUT_SELECT: int = 0x20
const INPUT_B: int = 0x40
const INPUT_A: int = 0x80

# --- Geometry Layout (in 256x240 logical viewport coordinates) ---
const DPAD_CENTER: Vector2 = Vector2(44.0, 192.0)
const DPAD_RADIUS: float = 34.0
const DPAD_DEADZONE: float = 7.0

const B_CENTER: Vector2 = Vector2(192.0, 202.0)
const B_RADIUS: float = 14.0

const A_CENTER: Vector2 = Vector2(228.0, 180.0)
const A_RADIUS: float = 14.0

const SELECT_RECT: Rect2 = Rect2(80.0, 222.0, 40.0, 12.0)
const START_RECT: Rect2 = Rect2(136.0, 222.0, 40.0, 12.0)

# Expanded touch hitboxes
const SELECT_TOUCH_RECT: Rect2 = Rect2(74.0, 216.0, 52.0, 20.0)
const START_TOUCH_RECT: Rect2 = Rect2(130.0, 216.0, 52.0, 20.0)

var active_touches: Dictionary = {}  # pointer_id (int) -> Vector2
var input_mask: int = 0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_PASS


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			active_touches[event.index] = event.position
		else:
			active_touches.erase(event.index)
		_recalculate_mask()
		queue_redraw()
	elif event is InputEventScreenDrag:
		active_touches[event.index] = event.position
		_recalculate_mask()
		queue_redraw()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				active_touches[-1] = event.position
			else:
				active_touches.erase(-1)
			_recalculate_mask()
			queue_redraw()
	elif event is InputEventMouseMotion:
		if active_touches.has(-1):
			active_touches[-1] = event.position
			_recalculate_mask()
			queue_redraw()


## Recomputes composite input bitmask from all active touch positions
func _recalculate_mask() -> void:
	input_mask = 0

	for touch_pos in active_touches.values():
		var pos: Vector2 = touch_pos

		# 1. D-Pad Check
		if pos.distance_to(DPAD_CENTER) <= DPAD_RADIUS + 4.0:
			var delta: Vector2 = pos - DPAD_CENTER
			if delta.x > DPAD_DEADZONE:
				input_mask |= INPUT_RIGHT
			elif delta.x < -DPAD_DEADZONE:
				input_mask |= INPUT_LEFT

			if delta.y > DPAD_DEADZONE:
				input_mask |= INPUT_DOWN
			elif delta.y < -DPAD_DEADZONE:
				input_mask |= INPUT_UP

		# 2. B Button Check (Fire)
		if pos.distance_to(B_CENTER) <= B_RADIUS + 6.0:
			input_mask |= INPUT_B

		# 3. A Button Check (Jump)
		if pos.distance_to(A_CENTER) <= A_RADIUS + 6.0:
			input_mask |= INPUT_A

		# 4. Select Button Check
		if SELECT_TOUCH_RECT.has_point(pos):
			input_mask |= INPUT_SELECT

		# 5. Start Button Check
		if START_TOUCH_RECT.has_point(pos):
			input_mask |= INPUT_START


## Returns current composite touch input bitmask
func get_input_mask() -> int:
	return input_mask


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font

	# --- 1. D-Pad Background Circle ---
	draw_circle(DPAD_CENTER, DPAD_RADIUS, Color(0.1, 0.1, 0.1, 0.28))
	draw_arc(DPAD_CENTER, DPAD_RADIUS, 0, TAU, 32, Color(1.0, 1.0, 1.0, 0.25), 1.0)

	# D-Pad Cross Background
	draw_rect(Rect2(DPAD_CENTER.x - 30.0, DPAD_CENTER.y - 10.0, 60.0, 20.0), Color(0.15, 0.15, 0.15, 0.45))
	draw_rect(Rect2(DPAD_CENTER.x - 10.0, DPAD_CENTER.y - 30.0, 20.0, 60.0), Color(0.15, 0.15, 0.15, 0.45))

	# D-Pad Active Highlights
	if (input_mask & INPUT_UP) != 0:
		draw_rect(Rect2(DPAD_CENTER.x - 10.0, DPAD_CENTER.y - 30.0, 20.0, 20.0), Color(1.0, 1.0, 1.0, 0.45))
	if (input_mask & INPUT_DOWN) != 0:
		draw_rect(Rect2(DPAD_CENTER.x - 10.0, DPAD_CENTER.y + 10.0, 20.0, 20.0), Color(1.0, 1.0, 1.0, 0.45))
	if (input_mask & INPUT_LEFT) != 0:
		draw_rect(Rect2(DPAD_CENTER.x - 30.0, DPAD_CENTER.y - 10.0, 20.0, 20.0), Color(1.0, 1.0, 1.0, 0.45))
	if (input_mask & INPUT_RIGHT) != 0:
		draw_rect(Rect2(DPAD_CENTER.x + 10.0, DPAD_CENTER.y - 10.0, 20.0, 20.0), Color(1.0, 1.0, 1.0, 0.45))

	# D-Pad Center Cap
	draw_circle(DPAD_CENTER, 8.0, Color(0.25, 0.25, 0.25, 0.55))

	# D-Pad Arrows
	var up_arrow: PackedVector2Array = [
		Vector2(DPAD_CENTER.x, DPAD_CENTER.y - 24.0),
		Vector2(DPAD_CENTER.x - 5.0, DPAD_CENTER.y - 16.0),
		Vector2(DPAD_CENTER.x + 5.0, DPAD_CENTER.y - 16.0)
	]
	var down_arrow: PackedVector2Array = [
		Vector2(DPAD_CENTER.x, DPAD_CENTER.y + 24.0),
		Vector2(DPAD_CENTER.x - 5.0, DPAD_CENTER.y + 16.0),
		Vector2(DPAD_CENTER.x + 5.0, DPAD_CENTER.y + 16.0)
	]
	var left_arrow: PackedVector2Array = [
		Vector2(DPAD_CENTER.x - 24.0, DPAD_CENTER.y),
		Vector2(DPAD_CENTER.x - 16.0, DPAD_CENTER.y - 5.0),
		Vector2(DPAD_CENTER.x - 16.0, DPAD_CENTER.y + 5.0)
	]
	var right_arrow: PackedVector2Array = [
		Vector2(DPAD_CENTER.x + 24.0, DPAD_CENTER.y),
		Vector2(DPAD_CENTER.x + 16.0, DPAD_CENTER.y - 5.0),
		Vector2(DPAD_CENTER.x + 16.0, DPAD_CENTER.y + 5.0)
	]

	var arrow_color: Color = Color(1.0, 1.0, 1.0, 0.75)
	draw_colored_polygon(up_arrow, Color(1.0, 1.0, 0.5, 0.9) if (input_mask & INPUT_UP) != 0 else arrow_color)
	draw_colored_polygon(down_arrow, Color(1.0, 1.0, 0.5, 0.9) if (input_mask & INPUT_DOWN) != 0 else arrow_color)
	draw_colored_polygon(left_arrow, Color(1.0, 1.0, 0.5, 0.9) if (input_mask & INPUT_LEFT) != 0 else arrow_color)
	draw_colored_polygon(right_arrow, Color(1.0, 1.0, 0.5, 0.9) if (input_mask & INPUT_RIGHT) != 0 else arrow_color)

	# --- 2. Action Buttons (B & A) ---
	var b_active: bool = (input_mask & INPUT_B) != 0
	var b_fill: Color = Color(0.9, 0.25, 0.25, 0.75) if b_active else Color(0.85, 0.25, 0.25, 0.38)
	var b_border: Color = Color(1.0, 0.6, 0.6, 0.85) if b_active else Color(1.0, 0.6, 0.6, 0.45)
	draw_circle(B_CENTER, B_RADIUS, b_fill)
	draw_arc(B_CENTER, B_RADIUS, 0, TAU, 24, b_border, 1.5)
	draw_string(font, Vector2(B_CENTER.x - 4.0, B_CENTER.y + 4.0), "B", HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color.WHITE)

	var a_active: bool = (input_mask & INPUT_A) != 0
	var a_fill: Color = Color(0.25, 0.55, 0.95, 0.75) if a_active else Color(0.25, 0.55, 0.95, 0.38)
	var a_border: Color = Color(0.6, 0.8, 1.0, 0.85) if a_active else Color(0.6, 0.8, 1.0, 0.45)
	draw_circle(A_CENTER, A_RADIUS, a_fill)
	draw_arc(A_CENTER, A_RADIUS, 0, TAU, 24, a_border, 1.5)
	draw_string(font, Vector2(A_CENTER.x - 4.0, A_CENTER.y + 4.0), "A", HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color.WHITE)

	# --- 3. Meta Buttons (Select & Start) ---
	var select_active: bool = (input_mask & INPUT_SELECT) != 0
	var select_fill: Color = Color(1.0, 1.0, 1.0, 0.65) if select_active else Color(0.2, 0.2, 0.2, 0.4)
	draw_rect(SELECT_RECT, select_fill)
	draw_rect(SELECT_RECT, Color(1.0, 1.0, 1.0, 0.45), false, 1.0)
	draw_string(font, Vector2(SELECT_RECT.position.x + 6.0, SELECT_RECT.position.y + 9.0), "SELECT", HORIZONTAL_ALIGNMENT_CENTER, -1, 7, Color.WHITE)

	var start_active: bool = (input_mask & INPUT_START) != 0
	var start_fill: Color = Color(1.0, 1.0, 1.0, 0.65) if start_active else Color(0.2, 0.2, 0.2, 0.4)
	draw_rect(START_RECT, start_fill)
	draw_rect(START_RECT, Color(1.0, 1.0, 1.0, 0.45), false, 1.0)
	draw_string(font, Vector2(START_RECT.position.x + 8.0, START_RECT.position.y + 9.0), "START", HORIZONTAL_ALIGNMENT_CENTER, -1, 7, Color.WHITE)

class_name Toolbar
extends CanvasLayer

@export var build_system: Node

var _buttons: Dictionary = {}

const GROUPS: Array = [
	{ "label": "Hull",      "pieces": [&"skeleton", &"hull_panel", &"deck_panel"] },
	{ "label": "Structure", "pieces": [&"plank", &"iron_plank", &"beam", &"mast"] },
	{ "label": "Deck",      "pieces": [&"deck", &"floor_board", &"stair"] },
	{ "label": "Walls",     "pieces": [&"wall", &"half_wall", &"window_wall", &"door_frame", &"roof_panel"] },
	{ "label": "Other",     "pieces": [&"foundation", &"post", &"cannon"] },
]

const C_BG        := Color(0.07, 0.06, 0.05, 0.96)
const C_BORDER    := Color(0.55, 0.42, 0.18, 1.00)
const C_BTN       := Color(0.14, 0.12, 0.10, 1.00)
const C_BTN_HOVER := Color(0.25, 0.20, 0.14, 1.00)
const C_BTN_ON    := Color(0.50, 0.36, 0.10, 1.00)
const C_BTN_ON_BD := Color(0.85, 0.68, 0.25, 1.00)
const C_LABEL     := Color(0.65, 0.55, 0.35, 1.00)
const C_TEXT      := Color(0.90, 0.84, 0.70, 1.00)
const C_TEXT_ON   := Color(1.00, 0.92, 0.60, 1.00)
const C_DIVIDER   := Color(0.55, 0.42, 0.18, 0.40)


func _sb(bg: Color, r: int, bd_color: Color, bd: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(r)
	s.border_color = bd_color
	s.set_border_width_all(bd)
	s.set_content_margin_all(0)
	return s


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var panel := PanelContainer.new()
	panel.anchor_left   = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_top    = 1.0
	panel.anchor_bottom = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -12
	var ps := _sb(C_BG, 10, C_BORDER, 2)
	ps.content_margin_left   = 16
	ps.content_margin_right  = 16
	ps.content_margin_top    = 8
	ps.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", ps)
	root.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 0)
	panel.add_child(hbox)

	var btn_normal  := _sb(C_BTN,      5, Color(0.35, 0.28, 0.16, 0.8))
	var btn_hover   := _sb(C_BTN_HOVER, 5, C_BORDER)
	var btn_on      := _sb(C_BTN_ON,    5, C_BTN_ON_BD, 2)
	btn_normal.set_content_margin_all(0)
	btn_hover.set_content_margin_all(0)
	btn_on.set_content_margin_all(0)

	var first_group := true
	var shortcut_idx := 0
	for group: Dictionary in GROUPS:
		if not first_group:
			# Divider
			var div := ColorRect.new()
			div.color = C_DIVIDER
			div.custom_minimum_size = Vector2(1, 44)
			div.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hbox.add_child(div)
			var sp := Control.new()
			sp.custom_minimum_size = Vector2(10, 0)
			hbox.add_child(sp)
		first_group = false

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		hbox.add_child(vbox)

		var sp2 := Control.new()
		sp2.custom_minimum_size = Vector2(8, 0)
		hbox.add_child(sp2)

		var lbl := Label.new()
		lbl.text = group.label.to_upper()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color", C_LABEL)
		vbox.add_child(lbl)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		vbox.add_child(row)

		for key: StringName in group.pieces:
			if not PieceDefs.DEFS.has(key):
				continue
			var btn := Button.new()
			var sc := "%d·" % (shortcut_idx + 1) if shortcut_idx < 9 else ""
			btn.text = sc + PieceDefs.DEFS[key].label
			btn.toggle_mode = true
			btn.custom_minimum_size = Vector2(72, 32)
			btn.focus_mode = Control.FOCUS_NONE
			btn.add_theme_stylebox_override("normal",        btn_normal)
			btn.add_theme_stylebox_override("hover",         btn_hover)
			btn.add_theme_stylebox_override("pressed",       btn_on)
			btn.add_theme_stylebox_override("focus",         btn_normal)
			btn.add_theme_stylebox_override("hover_pressed", btn_on)
			btn.add_theme_font_size_override("font_size", 11)
			btn.add_theme_color_override("font_color",          C_TEXT)
			btn.add_theme_color_override("font_hover_color",    C_TEXT)
			btn.add_theme_color_override("font_pressed_color",  C_TEXT_ON)
			btn.pressed.connect(_on_piece_selected.bind(key))
			_buttons[key] = btn
			row.add_child(btn)
			shortcut_idx += 1


func _process(_delta: float) -> void:
	if not build_system:
		return
	var selected: StringName = build_system.selected_piece
	for key: StringName in _buttons:
		(_buttons[key] as Button).button_pressed = (key == selected)


func _on_piece_selected(type: StringName) -> void:
	if build_system:
		if build_system.selected_piece == type:
			build_system.select_piece(&"")
		else:
			build_system.select_piece(type)

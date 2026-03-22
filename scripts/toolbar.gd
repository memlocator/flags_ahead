class_name Toolbar
extends CanvasLayer

@export var build_system: Node

var _buttons: Dictionary = {}


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -52
	add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 6)
	panel.add_child(hbox)

	var idx := 0
	for key: StringName in PieceDefs.DEFS:
		var btn := Button.new()
		var shortcut := "[%d] " % (idx + 1) if idx < 9 else ""
		btn.text = shortcut + PieceDefs.DEFS[key].label
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(90, 38)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_piece_selected.bind(key))
		_buttons[key] = btn
		hbox.add_child(btn)
		idx += 1


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

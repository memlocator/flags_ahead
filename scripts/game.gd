extends Node3D

@onready var player              := $Player as CharacterBody3D
@onready var camera_pivot        := $CameraPivot
@onready var camera              := $CameraPivot/SpringArm3D/Camera3D as Camera3D
@onready var ship_root           := $ShipRoot as RigidBody3D
@onready var keel_group          := $ShipRoot/KeelGroup as Node3D
@onready var placed_pieces_node  := $ShipRoot/PlacedPieces as Node3D
@onready var build_system        := $BuildSystem
@onready var skeletons_root      := $SkeletonsRoot as Node3D
@onready var ghost_pivot         := $BuildSystem/BuildPreview/PivotNode as Node3D
@onready var ghost_mesh_node     := $BuildSystem/BuildPreview/PivotNode/GhostMesh as Node3D
@onready var toolbar             := $Toolbar
@onready var hud_label           := $HUD/Label as Label

var _ship_editor: ShipEditor


func _ready() -> void:
	camera_pivot.target       = player
	camera_pivot.build_system = build_system

	player.camera = camera

	# Set up the runtime hull editor
	_ship_editor = ShipEditor.new()
	_ship_editor.player       = player
	_ship_editor.camera       = camera
	_ship_editor.camera_pivot = camera_pivot
	add_child(_ship_editor)

	# Wire up any interactables already in the scene
	_connect_interactables()

	build_system.build_camera        = camera
	build_system.ship_root           = ship_root
	build_system.placed_pieces_node  = placed_pieces_node
	build_system.ghost_pivot         = ghost_pivot
	build_system.ghost_mesh_node     = ghost_mesh_node
	build_system.skeletons_root      = skeletons_root

	toolbar.build_system = build_system

	build_system.piece_added.connect(_on_piece_added)
	build_system.piece_destroyed.connect(_on_piece_destroyed)

	_add_crosshair()
	_update_hud()


func _add_crosshair() -> void:
	var dot := Label.new()
	dot.text = "·"
	dot.add_theme_font_size_override("font_size", 28)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dot.offset_left = -10
	dot.offset_right = 10
	dot.offset_top = -14
	dot.offset_bottom = 14
	$HUD.add_child(dot)


func _process(_delta: float) -> void:
	_update_hud()


func _update_hud() -> void:
	var piece_label : String = PieceDefs.DEFS[build_system.selected_piece].label \
		if build_system.selected_piece != &"" else "—"
	var count: int  = build_system.placed_pieces.size()
	var sym         := "ON" if build_system.symmetry_enabled else "OFF"
	var snap        := "ON" if build_system.snapping_enabled else "OFF"
	const AXIS_NAMES := ["X (red)", "Y (green)", "Z (blue)"]
	var axis_label: String = AXIS_NAMES[build_system.rot_axis_index] if build_system.selected_piece != &"" else "—"
	hud_label.text  = "Piece: %s  |  [R] Axis: %s  |  [T] Reset rot  |  [G] Snap: %s  |  [M] Sym: %s  |  Placed: %d\nWASD=move  LMB=place  RMB=remove  Scroll=spin  Shift=fine  TAB/1-9=select  Esc=cursor" \
		% [piece_label, axis_label, snap, sym, count]


func _on_piece_added(_piece: ShipPiece, _reason: BuildSystem.PlaceReason, _source: Node) -> void:
	pass


func _on_piece_destroyed(_piece: ShipPiece, _reason: BuildSystem.RemoveReason, _source: Node) -> void:
	pass


# ── Ship editor wiring ────────────────────────────────────────────────────────

func _connect_interactables() -> void:
	# Walk the tree and connect any ShipSkeletonInteractable nodes
	for node in get_tree().get_nodes_in_group("ship_skeleton_interactable"):
		_connect_interactable(node)
	# Also scan skeletons_root for interactable children
	if skeletons_root:
		for child in skeletons_root.get_children():
			for sub in child.get_children():
				if sub is ShipSkeletonInteractable:
					_connect_interactable(sub)


func _connect_interactable(interactable: ShipSkeletonInteractable) -> void:
	if not interactable.interact_requested.is_connected(_on_interact_requested):
		interactable.interact_requested.connect(_on_interact_requested.bind(interactable))
		print("ShipEditor: connected interactable ", interactable.get_path())


func _on_interact_requested(skeleton: ShipSkeleton, interactable: ShipSkeletonInteractable) -> void:
	interactable.set_editing(true)
	_ship_editor.editing_finished.connect(
		func(_confirmed: bool) -> void: interactable.set_editing(false),
		CONNECT_ONE_SHOT)
	_ship_editor.start_editing(skeleton)

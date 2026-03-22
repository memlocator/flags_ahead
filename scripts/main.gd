extends Node3D

@onready var ship_root        = $ShipRoot
@onready var keel_group       = $ShipRoot/KeelGroup
@onready var placed_pieces_node = $ShipRoot/PlacedPieces
@onready var build_system     = $BuildSystem
@onready var ghost_pivot      = $BuildSystem/BuildPreview/PivotNode
@onready var ghost_mesh_node  = $BuildSystem/BuildPreview/PivotNode/GhostMesh
@onready var camera           = $Camera3D
@onready var hud_label        = $HUD/Label


func _ready() -> void:
	keel_group.build()

	camera.build_system = build_system

	build_system.build_camera     = camera
	build_system.ship_root        = ship_root
	build_system.placed_pieces_node = placed_pieces_node
	build_system.ghost_pivot      = ghost_pivot
	build_system.ghost_mesh_node  = ghost_mesh_node

	build_system.piece_placed.connect(_on_piece_placed)
	build_system.piece_removed.connect(_on_piece_removed)

	_update_hud()


func _process(_delta: float) -> void:
	_update_hud()


func _update_hud() -> void:
	var mode        := "BUILD" if build_system.build_mode_active else "VIEW"
	var piece_label : String = PieceDefs.DEFS[build_system.selected_piece].label
	var count: int  = build_system.placed_pieces.size()
	var sym         := "ON" if build_system.symmetry_enabled else "OFF"
	hud_label.text  = "[B] Mode: %s  |  [TAB] Piece: %s  |  [M] Sym: %s  |  Placed: %d\nRMB=orbit  Scroll=zoom  |  [BUILD] LMB=place  RMB=remove  Scroll=rotate" \
		% [mode, piece_label, sym, count]


func _on_piece_placed(_piece) -> void:
	pass


func _on_piece_removed(_piece) -> void:
	pass

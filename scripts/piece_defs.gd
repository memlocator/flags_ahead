class_name PieceDefs

const DEFS: Dictionary = {
	&"plank": {
		"label": "Wood Plank",
		"size": Vector3(2.0, 0.5, 0.12),
		"face_axis": 0,  # X (2.0) long axis along normal — stands out from surface
		"weight": 1.0,
		"max_support": 6,
		"resets_stability": false,
		"material_tier": 0,
		"hp": 100,
	},
	&"iron_plank": {
		"label": "Iron Plank",
		"size": Vector3(2.0, 0.5, 0.12),
		"face_axis": 0,
		"weight": 2.5,
		"max_support": 12,
		"resets_stability": true,
		"material_tier": 2,
		"hp": 200,
	},
	&"deck": {
		"label": "Deck",
		"size": Vector3(2.0, 0.12, 2.0),
		"face_axis": 1,  # Y is the thin face — lies flat on floor
		"weight": 1.2,
		"max_support": 6,
		"resets_stability": false,
		"material_tier": 0,
		"hp": 120,
	},
	&"wall": {
		"label": "Wall",
		"size": Vector3(2.0, 1.5, 0.12),
		"face_axis": 2,
		"weight": 0.8,
		"max_support": 6,
		"resets_stability": false,
		"material_tier": 0,
		"hp": 80,
	},
	&"half_wall": {
		"label": "Half Wall",
		"size": Vector3(2.0, 0.75, 0.12),
		"face_axis": 2,
		"weight": 0.5,
		"max_support": 6,
		"resets_stability": false,
		"material_tier": 0,
		"hp": 50,
	},
	&"window_wall": {
		"label": "Window Wall",
		"size": Vector3(1.0, 1.0, 0.12),
		"face_axis": 2,
		"weight": 0.7,
		"max_support": 6,
		"resets_stability": false,
		"material_tier": 0,
		"hp": 70,
	},
	&"beam": {
		"label": "Beam",
		"size": Vector3(0.12, 0.12, 1.0),
		"face_axis": 0,  # X (0.12) face contacts surface — lies along surface, spin orients long Z axis
		"weight": 0.6,
		"max_support": 6,
		"resets_stability": false,
		"material_tier": 0,
		"hp": 60,
	},
	&"mast": {
		"label": "Mast",
		"size": Vector3(0.3, 4.0, 0.3),
		"face_axis": 1,  # Y is the long axis — stands upright from floor
		"weight": 1.5,
		"max_support": 8,
		"resets_stability": false,
		"material_tier": 1,
		"hp": 150,
	},
	&"cannon": {
		"label": "Cannon",
		"size": Vector3(0.6, 0.6, 1.5),
		"face_axis": 1,  # Y up — sits on deck
		"weight": 3.0,
		"max_support": 8,
		"resets_stability": false,
		"material_tier": 2,
		"hp": 300,
	},
}

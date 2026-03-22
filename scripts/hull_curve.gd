class_name HullCurve
extends Node

## Defines how hull planks curve as they extend outward from the rib surface.
##
## The profile Curve maps t (0 = keel, 1 = gunwale) to Z_norm (0 = centreline,
## 1 = outer edge) — matching the HULL_PROFILE shape in ShipSkeleton.
##
## get_bend_offsets(hit_y, plank_length) returns Y-rise values for each
## segment boundary along the plank, from the inner end (at the rib) to the
## outer end.  Bending peaks at the bilge and tapers to zero at keel/gunwale.

@export var profile: Curve
@export var segments: int = 8
@export var rib_height: float = 2.5  # world height of the midship rib
@export var bend_scale: float = 0.15  # max rise ratio; tune in-editor


func _ready() -> void:
	if profile == null:
		_build_default_profile()


## Returns (segments + 1) Y-offset values.
## offset[0] = 0 (inner end flush with rib).
## offset[segments] = rise at the outer end.
func get_bend_offsets(hit_y: float, plank_length: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(segments + 1)
	var t: float = clamp(hit_y / rib_height, 0.0, 1.0)
	# Curvature factor peaks at the bilge (~t=0.5), zero at keel and gunwale
	var curvature: float = sin(t * PI) * bend_scale
	# Monotonic rise from inner (s=0, offset=0) to outer (s=1, offset=curvature*length)
	for i in range(segments + 1):
		var s := float(i) / float(segments)
		out[i] = curvature * s * plank_length
	return out


func _build_default_profile() -> void:
	profile = Curve.new()
	# V-hull cross-section: matches HULL_PROFILE in ShipSkeleton
	profile.add_point(Vector2(0.00, 0.00), 0.0, 3.0)
	profile.add_point(Vector2(0.12, 0.52), 2.0, 1.2)
	profile.add_point(Vector2(0.42, 0.88), 0.6, 0.3)
	profile.add_point(Vector2(0.78, 0.97), 0.1, 0.05)
	profile.add_point(Vector2(1.00, 1.00), 0.05, 0.0)
	profile.bake()

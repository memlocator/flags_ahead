@tool
class_name ShipConfig
extends Resource

## Defines the structural parameters of a ship frame.
## Create different ship types as .tres files and assign to a ShipSkeleton.

# Number of ribs — changing this evenly respaces them between stern and bow.
@export_range(2, 50) var rib_count: int = 5:
	set(v):
		rib_count = v
		if rib_x_positions.size() != v:
			_respace_ribs()
			emit_changed()

# Number of decks — changing this evenly respaces them between keel and gunwale.
@export_range(0, 10) var deck_count: int = 2:
	set(v):
		deck_count = v
		if deck_heights.size() != v:
			_respace_decks()
			emit_changed()

# Rib X positions along the ship's long axis (bow is positive X)
@export var rib_x_positions: PackedFloat32Array = PackedFloat32Array([-4.0, -2.0, 0.0, 2.0, 4.0])

# Where the bow stem sits (should be beyond the last positive rib)
@export var bow_x: float = 5.1

# How far the bow stem rakes forward from keel to gunwale (0 = vertical stem)
@export var bow_rake: float = 0.0

# How far the sternpost rakes aft from keel to gunwale (negative = rakes aft)
@export var stern_rake: float = 0.0

# Where the transom stern sits (should be beyond the last negative rib)
@export var stern_x: float = -5.0

# Midship rib height (keel to gunwale)
@export var rib_height_base: float = 4.5

# How much height tapers per unit of distance from midship
@export var rib_height_taper: float = 0.18

# Midship half-beam (centre to outer edge at max width)
@export var rib_width_base: float = 2.4

# How much beam tapers per unit of distance from midship
@export var rib_width_taper: float = 0.10

# Hull cross-section profile (right/starboard side; mirrored for port).
# Each Vector2: (y_fraction, z_fraction)
#   y_fraction: 0 = keel, 1 = gunwale
#   z_fraction: 0 = centreline, 1 = outer edge at that height
@export var hull_profile: Array[Vector2] = [
	Vector2(0.00, 0.00),  # keel
	Vector2(0.08, 0.38),  # lower bilge
	Vector2(0.25, 0.78),  # bilge knuckle
	Vector2(0.45, 0.98),  # max beam (waterline)
	Vector2(0.62, 0.96),  # tumblehome begins
	Vector2(0.80, 0.91),  # tumblehome mid
	Vector2(1.00, 0.88),  # gunwale
]

# Heights at which horizontal deck girder beams are generated (snap targets for floors)
@export var deck_heights: Array[float] = [2.0, 3.5]

# Uniform scale applied to all output geometry (design values stay as-is)
@export var scale_factor: float = 1.0


# Derived helpers ─────────────────────────────────────────────────────────────

## Raw (unscaled) rib height — used internally for dimensionless ratios.
func rib_height(rib_x: float) -> float:
	return rib_height_base - absf(rib_x) * rib_height_taper


## Raw (unscaled) half-beam — used internally for dimensionless ratios.
func rib_half_width(rib_x: float) -> float:
	return (rib_width_base - absf(rib_x) * rib_width_taper) * 0.5


## All bay station X values in ascending order, including bow and stern endpoints.
## Returns raw (design-space) values — callers that work in world space must apply scale_factor.
func bay_stations() -> Array[float]:
	var stations: Array[float] = []
	stations.append(stern_x)
	for x: float in rib_x_positions:
		stations.append(x)
	stations.append(bow_x)
	stations.sort()
	return stations


## Hull profile sampled at rib_x, in skeleton local space (scaled by scale_factor).
## side: +1.0 = starboard, -1.0 = port
func rib_profile_points(rib_x: float, side: float) -> PackedVector3Array:
	var sf := scale_factor
	var h  := rib_height(rib_x)
	var hw := rib_half_width(rib_x)
	var pts := PackedVector3Array()
	for p: Vector2 in hull_profile:
		pts.append(Vector3(rib_x * sf, p.x * h * sf, side * p.y * hw * sf))
	return pts


## Bow stem profile — points converge to the centreline at bow_x (scaled).
func bow_stem_points(_side: float = 1.0) -> PackedVector3Array:
	var sf  := scale_factor
	var h   := rib_height(rib_x_positions[rib_x_positions.size() - 1])
	var pts := PackedVector3Array()
	for p: Vector2 in hull_profile:
		pts.append(Vector3((bow_x + bow_rake * p.x) * sf, p.x * h * sf, 0.0))
	return pts


## Stern post profile — points converge to the centreline at stern_x (scaled).
func stern_profile_points(_side: float = 1.0) -> PackedVector3Array:
	var sf  := scale_factor
	var h   := rib_height(rib_x_positions[0])
	var pts := PackedVector3Array()
	for p: Vector2 in hull_profile:
		pts.append(Vector3((stern_x + stern_rake * p.x) * sf, p.x * h * sf, 0.0))
	return pts


## Deck profile at a given station X and deck height Y (both raw/design values).
## Returns two scaled points spanning port to starboard.
func deck_profile_points(station_x: float, deck_y: float) -> PackedVector3Array:
	var sf := scale_factor
	var t  := deck_y / maxf(rib_height(station_x), 0.001)
	var hw := rib_half_width(station_x) * hull_z_at(t) * sf
	var pts := PackedVector3Array()
	pts.append(Vector3(station_x * sf, deck_y * sf, -hw))
	pts.append(Vector3(station_x * sf, deck_y * sf,  hw))
	return pts


@export_tool_button("↺ Redistribute Ribs") var _btn_ribs: Callable = redistribute_ribs

func redistribute_ribs() -> void:
	_respace_ribs()
	emit_changed()


func _respace_ribs() -> void:
	if stern_x >= bow_x or rib_count < 2:
		return
	var step := (bow_x - stern_x) / float(rib_count + 1)
	rib_x_positions.resize(rib_count)
	for i in rib_count:
		rib_x_positions[i] = stern_x + step * float(i + 1)


func _respace_decks() -> void:
	deck_heights.resize(deck_count)
	for i in deck_count:
		deck_heights[i] = rib_height_base * float(i + 1) / float(deck_count + 1)


## Z fraction of the hull profile at a given normalised height t (0=keel, 1=gunwale).
func hull_z_at(t: float) -> float:
	for i in range(hull_profile.size() - 1):
		var p1: Vector2 = hull_profile[i]
		var p2: Vector2 = hull_profile[i + 1]
		if t >= p1.x and t <= p2.x:
			var f := (t - p1.x) / (p2.x - p1.x)
			return lerpf(p1.y, p2.y, f)
	return 1.0

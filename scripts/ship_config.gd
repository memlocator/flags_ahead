@tool
class_name ShipConfig
extends Resource

## Defines the structural parameters of a ship frame.
## Create different ship types as .tres files and assign to a ShipSkeleton.

# Rib X positions along the ship's long axis (bow is positive X)
@export var rib_x_positions: PackedFloat32Array = PackedFloat32Array([-4.0, -2.0, 0.0, 2.0, 4.0])

# Where the bow stem sits (should be beyond the last positive rib)
@export var bow_x: float = 5.1

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


# Derived helpers ─────────────────────────────────────────────────────────────

func rib_height(rib_x: float) -> float:
	return rib_height_base - absf(rib_x) * rib_height_taper


func rib_half_width(rib_x: float) -> float:
	return (rib_width_base - absf(rib_x) * rib_width_taper) * 0.5


## All bay station X values in ascending order, including bow and stern endpoints.
func bay_stations() -> Array[float]:
	var stations: Array[float] = []
	stations.append(stern_x)
	for x: float in rib_x_positions:
		stations.append(x)
	stations.append(bow_x)
	stations.sort()
	return stations


## Hull profile sampled at rib_x, in skeleton local space.
## side: +1.0 = starboard, -1.0 = port
func rib_profile_points(rib_x: float, side: float) -> PackedVector3Array:
	var h  := rib_height(rib_x)
	var hw := rib_half_width(rib_x)
	var pts := PackedVector3Array()
	for p: Vector2 in hull_profile:
		pts.append(Vector3(rib_x, p.x * h, side * p.y * hw))
	return pts


## Bow cap: all profile points converge toward the centreline at bow_x.
func bow_stem_points() -> PackedVector3Array:
	var h   := rib_height(rib_x_positions[rib_x_positions.size() - 1])
	var pts := PackedVector3Array()
	for p: Vector2 in hull_profile:
		pts.append(Vector3(bow_x, p.x * h, 0.0))
	return pts


## Stern profile: matches the last negative rib width but placed at stern_x.
func stern_profile_points(side: float) -> PackedVector3Array:
	# Find the rib closest to the stern (smallest X in rib_x_positions)
	var inner_x := rib_x_positions[0]
	for x: float in rib_x_positions:
		if x < inner_x: inner_x = x
	var h  := rib_height(inner_x)
	var hw := rib_half_width(inner_x) * 0.88  # transom slightly narrower than hull
	var pts := PackedVector3Array()
	for p: Vector2 in hull_profile:
		pts.append(Vector3(stern_x, p.x * h, side * p.y * hw))
	return pts


## Z fraction of the hull profile at a given normalised height t (0=keel, 1=gunwale).
func hull_z_at(t: float) -> float:
	for i in range(hull_profile.size() - 1):
		var p1: Vector2 = hull_profile[i]
		var p2: Vector2 = hull_profile[i + 1]
		if t >= p1.x and t <= p2.x:
			var f := (t - p1.x) / (p2.x - p1.x)
			return lerpf(p1.y, p2.y, f)
	return 1.0

# Hull Editor

Draggable handles in the Godot 3D viewport gizmo, built on `EditorNode3DGizmoPlugin`.

## Handle types

| Handle | Color | Controls | Drag axis |
|--------|-------|----------|-----------|
| Profile points | Yellow circles | `hull_profile[i]` (y_frac, z_frac) | Y-Z plane at X=0 |
| Rib positions | Blue diamonds | `rib_x_positions[i]` | X axis |
| Bow / stern | Red circles | `bow_x`, `stern_x` | X axis |
| Deck levels | Green circles | `deck_heights[i]` | Y axis |

Profile handles live on the starboard side of the midship rib. Port mirrors automatically. All ribs share one profile shape — editing the handles reshapes all ribs proportionally.

Deck handles sit slightly outside the hull edge so they're easy to click without overlapping the rib geometry.

## Handle ID scheme

```
0 .. profile_n-1              hull_profile points
profile_n .. +rib_n-1         rib_x_positions
profile_n + rib_n             bow_x
profile_n + rib_n + 1         stern_x
profile_n + rib_n + 2 .. +D   deck_heights
```

## Drag behaviour

- Profile: ray intersects local X=0 plane (skeleton's X axis as normal), Y/Z normalised by rib height/half-width.
- Rib/bow/stern: camera-facing plane through handle world pos, take X component only. Ribs clamped 0.3 m away from neighbours and endpoints.
- Deck: same camera-facing plane, take Y component. Clamped 0.1 m above keel and 0.95 × rib_height_base.
- During drag: update cfg values + `skel.update_gizmos()` only (no physics rebuild).
- On commit: `skel._rebuild()` to sync StaticBody3D geometry.
- On cancel: restore original value from `_get_handle_value`, then rebuild.

## ShipConfig additions

```gdscript
@export var rib_count: int = 5
@export var deck_count: int = 2

@export_tool_button("↺ Redistribute Ribs")
var _btn_ribs: Callable = redistribute_ribs

@export_tool_button("↺ Redistribute Decks")
var _btn_decks: Callable = redistribute_decks
```

`redistribute_ribs()` — spaces `rib_count` ribs evenly between `stern_x` and `bow_x` (equal margin at each end).

`redistribute_decks()` — spaces `deck_count` decks evenly from keel to 90% of `rib_height_base`.

Changing `rib_count` or `deck_count` in the Inspector does NOT auto-redistribute — press the button after setting the count. This preserves manual positions from handle drags.

## Stair holes

Not part of hull config. Place `door_frame` or stair pieces on deck girders via the normal build system. The deck girders are snap targets; openings are just a gap in the floor planks.

## Files to change

- `scripts/ship_config.gd` — add `rib_count`, `deck_count`, two tool buttons, two redistribute helpers
- `addons/ship_builder/ship_skeleton_gizmo.gd` — add handle materials, full `_redraw` handle calls, `_get_handle_name`, `_get_handle_value`, `_set_handle`, `_commit_handle`, `_handle_local_pos` helper

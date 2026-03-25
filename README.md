# Flag Ahead

A ship-building sandbox in Godot 4. Place structural frames, hull planks, deck panels, cannons, and more to construct a ship piece by piece.

## Gameplay

Walk around the build site and use the toolbar to select a piece type, then click to place it against the skeleton. Pieces snap to each other. Unsupported structures gradually collapse.

**Controls**

| Key | Action |
|-----|--------|
| WASD | Move |
| Mouse | Look |
| Left click | Place piece |
| Right click | Remove piece |
| Tab / 1–9 | Cycle / select piece type |
| R | Change rotation axis |
| Scroll wheel | Rotate piece |
| T | Reset rotation |
| M | Toggle mirror symmetry |
| G | Toggle snapping |

## Building

- **Hull panels** — skin the sides of the frame bay by bay; taper automatically at the bow and stern
- **Deck panels** — cover the deck girders section by section; taper to match the hull at the ends
- **Planks / iron planks** — bend to conform to the hull curve
- **Skeleton** — place additional ship frames anywhere on the ground

## Hull Editor (Godot editor)

Select a `ShipSkeleton` node in the editor to get draggable handles:

- **Yellow** — hull profile cross-section points
- **Blue** — rib X positions
- **Red** — bow and stern endpoints
- **Green** — deck heights

Hull shapes are saved as `.tres` resource files and assigned to skeleton nodes.

## Requirements

- Godot 4.6+

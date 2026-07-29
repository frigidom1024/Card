# Random Board Event Placement Design

**Date:** 2026-07-29

## Goal

Generate the initial event instances from `EventLib`, place them randomly on the board without overlapping or leaving board bounds, and render each placed event through its configured `BoardEvent` scene.

## Scope

- Use `EventLib.generate_event_datas()` as the source of runtime event instances.
- Run initial event placement once from `GameManager._ready()`.
- Keep random placement policy outside `Board`.
- Let `Board` own grid validation, event occupancy, event-node attachment, and event-node removal support.
- Block cards from being placed on cells currently occupied by events.
- Skip an event with a warning if no valid location remains; do not abort game startup.

## Responsibilities

| Component | Responsibility |
| --- | --- |
| `EventLib` | Holds event-entry data and creates a configured `BoardEvent` node for a supplied runtime instance. |
| `EventPlacementService` | Generates instances from `EventLib`, finds a random valid origin for each instance, and asks the board to attach the rendered node. |
| `Board` | Knows board bounds and occupied cells; validates event placement; tracks attached event nodes; prevents card/event overlap; attaches and later removes event nodes. |
| `GameManager` | Owns the exported `EventLib` reference and triggers the one-time initial placement call. |

## Placement Flow

```text
GameManager._ready()
  -> init_events()
  -> EventPlacementService.place_initial_events(event_lib, board)
  -> EventLib.generate_event_datas()
  -> for each EventInstance:
       build all valid board origins for EventData.size
       choose one randomly from the valid origins
       set EventInstance.origin
       EventLib.create_event_scene(instance, board.cell_size)
       Board.attach_event(node)
```

`EventPlacementService` will use an injectable `RandomNumberGenerator`. Runtime calls randomize its generator; tests pass a seeded generator so their placement checks are repeatable.

## Board APIs

The board will expose focused event APIs instead of choosing randomness itself:

- `get_event_cells(origin, event_size)` returns all cells occupied by an event rectangle.
- `can_attach_event(instance)` checks bounds plus card/event occupancy.
- `attach_event(event_node)` reserves cells, adds the node as a board child, and records it in `events`.
- `remove_event(event_node)` releases occupied cells and removes the event node from `events`.

The existing card-conflict check will also regard event-occupied cells as unavailable.

## Data and Rendering

- `EventInstance.origin` starts unassigned and is set only after the placement service chooses a valid origin.
- `EventData.size` remains the only source of an event's board footprint; no duplicate size setting is introduced.
- `EventLib.create_event_scene()` configures the `BoardEvent` before it enters the board tree, so it renders from the assigned instance and does not fall back to the scene-preview instance.
- The board keeps rendered `BoardEvent` nodes in `events`; their normal event-selection and completion logic remains unchanged.

## Capacity Behavior

If no valid position exists for an event, the service reports a warning and continues with the next generated event. The return value contains only the events successfully attached to the board.

## Verification

Automated tests will cover:

1. A generated event receives an in-bounds origin and a `BoardEvent` child attached to the board.
2. Multiple events occupy no shared cells, including multi-cell event sizes.
3. Event cells prevent card-placement conflict checks from approving an overlap.
4. A board with insufficient space skips unplaceable events without corrupting existing event occupancy.
5. The game-manager scene supplies the initial `EventLib` reference and triggers initial placement through `init_events()`.

## Non-goals

- Weighted event selection beyond the current `EventEntry` count ranges.
- Procedural room generation, path connectivity, or encounter progression rules.
- Event completion rewards and removal behavior beyond the board API needed to support future removal.

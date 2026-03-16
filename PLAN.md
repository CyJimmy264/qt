# Qt Ruby Bridge Plan

## Goal

Move the bridge toward maximal Qt-derived generation with minimal policy surface, so Qt 6.x updates are pulled in automatically instead of requiring manual generator maintenance.

## Event Payload Roadmap

### Current Direction

- Keep expanding AST/header-derived event support.
- Reduce handwritten generator policy where Qt provides enough structure to derive behavior automatically.
- Prefer explicit warnings over silent fallback when event-class resolution is ambiguous.

### Near-Term Follow-Ups

1. Remove duplicate warnings during event payload generation.
2. Continue pushing remaining policy out of `scripts/generate_bridge/event_payloads.rb`:
   - `EVENT_PAYLOAD_EXCLUDED_METHODS`
   - `EVENT_PAYLOAD_COMPATIBILITY_ALIASES`
   - flattening heuristics for `QPoint` / `QSize` / similar Qt value types
3. Build a more direct `QEvent::Type -> event class` extractor from AST/header patterns to reduce family heuristics further.
4. Continue extending typed support across the bridge using the same approach, not only for events.

## Phase 2

- Expand auto-derived payload coverage to more event classes.
- Resolve complex Qt types and duplicated/deprecated getters more cleanly.
- Refine field-selection policy so payloads do not grow noisy or redundant.
- Add end-to-end payload assertions for newer event families.
- Finish end-to-end payload assertions for newly added event classes if still incomplete.

## Phase 3

- Start removing legacy compatibility payload fields `:a/:b/:c/:d`, or make them optional.
- Stabilize the public payload contract around named fields only.
- Generate richer Ruby event objects instead of plain `Hash` payloads if that becomes worthwhile.

## Broader Generator Direction

- Keep source-of-truth in stable Ruby/C++ files plus AST/header-derived generator logic.
- Avoid reintroducing large manual lists when the same data can be inferred from Qt headers.
- Use warnings to surface ambiguity/conflicts during generation rather than hiding them behind fallback behavior.

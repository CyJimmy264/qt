# Qt Ruby Project Notes

## Core Policy
- Do not hand-write new C/C++ bridge functions for app-level behavior.
- Bridge/native layer should be generated from Qt headers/API only.
- Application logic belongs in Ruby app code (examples or user apps), not in bridge.
- Do not reimplement Qt behavior inside core bridge/native (no custom click systems, no synthetic event dispatch in `lib/qt/native.rb`).
- No framework-level polling/hit-test event emulation in core. If polling is needed, it is app/example-level temporary logic only.
- Do not pseudo-generate non-Qt-derived runtime logic (e.g., large handcrafted Ruby modules emitted as string templates).
- If logic cannot be directly generated from Qt headers/metaobject data, keep it as regular Ruby source files in the repository (source-of-truth), not in generated artifacts.
- Apply the same rule to C++: non-Qt-derived runtime logic must live in regular `*.cpp/*.h` source files in the repository, not as large `lines <<` string blocks in the generator.
- Generator responsibility is wiring/composition of generated API plus stable source files, not embedding substantial handcrafted C++ runtime implementations inline.

## Architecture
- Project is a Ruby-to-Qt bridge (`qt` gem name).
- Generated artifacts live under `build/` and are not source-of-truth.
- Source-of-truth:
  - `scripts/generate_bridge.rb` (AST-driven generator + universal policy)
- `lib/qt/native.rb` must remain a thin FFI wrapper over generated bridge API.
- Build flow:
  - `ruby scripts/generate_bridge.rb`
  - `bundle exec rake compile`
  - Verification flow is strictly sequential: never run `compile` and `test` in parallel.
  - Always run `bundle exec rake compile` first, then `bundle exec rake test`.

## Universal Generation Contract
- Target direction: universal AST-driven policy, not per-class manual method curation.
- Keep per-class exceptions minimal and temporary (only unavoidable bootstrap/special-cases).
- Candidate methods: public only, non-deprecated, non-operator, non-internal/event/metaobject hooks.
- Candidate signatures: FFI-safe types only (int/bool/QString/pointer + explicitly supported enum casts).
- Default arguments must be respected in generated Ruby method signatures.
- Ruby API must be Ruby-safe by construction (keyword-safe method/argument names).
- Overload resolution must be deterministic and policy-driven, not class-by-class hand tuning.

## Inheritance Model
- Ruby classes are generated with Qt-based inheritance derived from AST.
- Intermediate Qt classes may be generated as thin Ruby wrappers (no native methods), e.g.:
  - `QLabel < QFrame < QWidget`
  - `QPushButton < QAbstractButton < QWidget`
  - `QTableWidget < QTableView < QAbstractItemView ...`
- Duplicated QWidget methods should not be repeated in child specs.

## Events / Signals / Slots Policy
- Current target is Qt-native event architecture, not custom bridge callbacks.
- Do not add hand-written bridge callbacks like `set_click_callback/watch_widget_click`.
- Do not generate helper methods like `on_click` unless backed by Qt-native event/metaobject model.
- Preferred roadmap:
  - Generate QObject event primitives from Qt API/types.
  - Add signals/slots support based on Qt metaobject system.
  - Rewrite examples to use that model.

## Example App Guidance
- `examples/development_ordered_demos/06_timetrap_clockify.rb` should keep scroll/state behavior in Ruby.
- Avoid recreating `QScrollArea` content widget on each render when preserving scroll UX.
- Prefer updating/reusing existing container and child widgets.

## Current UX Expectations (timetrap_clockify)
- Sidebar project filter.
- Week/day grouped blocks.
- Expand/collapse project rows.
- Stable scrolling (no jump to top on row click).
- Styled modern scrollbar via QSS.

## Debugging
- Use `TIMETRAP_UI_DEBUG=1` for verbose Ruby-side logs.
- Keep logs useful but avoid adding permanent bridge APIs only for debugging.

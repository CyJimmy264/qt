# qt

![Ruby](https://img.shields.io/badge/Ruby-3.1%2B-CC342D)
![Qt](https://img.shields.io/badge/Qt-6.10%2B-41CD52)
![Status](https://img.shields.io/badge/Status-Experimental-orange)
![Bridge](https://img.shields.io/badge/Architecture-Ruby%20%E2%86%94%20Qt%20Bridge-blue)

Ruby-first Qt 6.10+ bridge.

Build real Qt Widgets apps in pure Ruby, mutate them live from IRB, and keep C/C++ surface minimal via generated bridge code from system Qt headers.

## Why It Hits Different

- Pure Ruby usage: no QML, no extra UI language.
- Real Qt power: `QApplication`, `QWidget`, `QLabel`, `QPushButton`, `QVBoxLayout`.
- Ruby ergonomics: Qt-style and snake_case/property style in parallel.
- Live GUI hacking: update widgets while the window is open.
- Generated bridge: API is derived from system Qt headers.

## 30-Second Wow

```bash
ruby examples/development_ordered_demos/02_live_layout_console.rb
```

Then in IRB:

```ruby
add_label("Release pipeline")
add_button("Run")
remove_last

gui { window.resize(1100, 700) }
items.last&.q_inspect
```

## Before -> After

Before (typical static run):

```ruby
app = QApplication.new(0, [])
window = QWidget.new
window.show
app.exec
```

After (live dev loop):

```ruby
# app already running
add_label("Dynamic block")
add_button("Ship")
gui { window.set_window_title("Changed live") }
```

## Install

### Requirements

- Ruby 3.1+
- Qt 6.10+ dev packages (`Qt6Core`, `Qt6Gui`, `Qt6Widgets` via `pkg-config`)
- C++17 compiler

Check Qt:

```bash
pkg-config --modversion Qt6Widgets
```

### Build from repo

```bash
bundle install
bundle exec rake compile
bundle exec rake install
```

`rake install` installs into your current Ruby environment (including active `rbenv` version).
`rake compile` builds the full bridge with `QT_RUBY_SCOPE=all` by default.

### Gem usage

```bash
gem install qt
```

## Hello Qt in Ruby

```ruby
require 'qt'

app = QApplication.new(0, [])

window = QWidget.new do |w|
  w.set_window_title('Qt Ruby App')
  w.resize(800, 600)
end

label = QLabel.new(window)
label.text = 'Hello from Ruby + Qt'
label.set_alignment(Qt::AlignCenter)
label.set_geometry(0, 0, 800, 600)

app.exec
```

## API Style: Qt + Ruby

```ruby
# Qt style
label.setText('A')
window.setWindowTitle('Main')

# Ruby style
label.text = 'B'
window.window_title = 'Main 2'
puts label.text
```

## API Compatibility Notes

Generated Ruby API is intentionally close to Qt API, but follows universal bridge policies.

- `snake_case` aliases are generated for Qt camelCase methods.
- Ruby keyword-safe renaming is applied when needed: `next` -> `next_`.
- Default C++ arguments are surfaced as optional Ruby arguments.
- Internal runtime name collisions are renamed consistently:
  - Qt `handle(int)` is exposed as `handle_at(int)` because `handle` is used for native object pointer access.
- Property convenience API is generated from Qt setters/getters when available:
  - `setText(...)` -> `text=(...)`, `text`.
- Runtime event/signal convenience methods are Ruby-layer helpers (not raw Qt method names):
  - `on(event, &block)` / alias `on_event`
  - `off(event = nil)` / alias `off_event`
  - `connect(signal, &block)` / aliases `on_signal`, `slot`
  - `disconnect(signal = nil)` / alias `off_signal`
  - these helpers are mixed into generated `QObject` descendants (for example `QWidget`, `QPushButton`, `QTimer`)
  - non-`QObject` value classes (`QIcon`, `QPixmap`, `QImage`) intentionally do not expose `connect`/`on`
- Introspection helpers are Ruby-layer helpers:
  - `q_inspect`, aliases `qt_inspect`, `to_h`
- Top-level constant aliases are provided for convenience:
  - `QApplication`, `QWidget`, `QLabel`, `QPushButton`, `QLineEdit`, `QVBoxLayout`, `QTableWidget`, `QTableWidgetItem`, `QScrollArea`
- Methods with unsupported signatures are skipped by policy:
  - non-public, deprecated, operator/internal event hooks,
  - non-FFI-safe argument/return types.

## Introspection

Every generated object exposes API snapshot helpers:

```ruby
label.q_inspect
label.qt_inspect
label.to_h
```

Shape:

```ruby
{
  qt_class: "QLabel",
  ruby_class: "Qt::QLabel",
  qt_methods: ["setText", "setAlignment", "text", ...],
  ruby_methods: [:setText, :set_text, :text, ...],
  properties: { text: "A", alignment: 129 }
}
```

## Examples

```bash
ruby examples/development_ordered_demos/01_dsl_hello.rb
ruby examples/development_ordered_demos/02_live_layout_console.rb
```

QObject signal example:

```ruby
timer = QTimer.new
timer.set_interval(1000)
timer.connect('timeout') { puts 'tick' }
timer.start
```

## Architecture

1. `scripts/generate_bridge.rb` reads Qt API from system headers.
2. Generates:
- `build/generated/qt_ruby_bridge.cpp`
- `build/generated/bridge_api.rb`
- `build/generated/widgets.rb`
3. Compiles native extension into `build/qt/qt_ruby_bridge.so`.
4. Ruby layer calls bridge functions via `ffi`.

Everything generated/build-related is under `build/` and should stay out of git.

## Layout

- `lib/qt` public Ruby API
- `scripts/generate_bridge.rb` AST-driven bridge generator
- `ext/qt_ruby_bridge` native extension entrypoint
- `build/generated` generated sources
- `build/qt` compiled bridge `.so`
- `examples` demos
- `test` tests

## Roadmap

### Done

- AST-driven generation with scope support: `QT_RUBY_SCOPE=widgets|qobject|all`
- default compile path switched to `all` (`widgets + qobject`)
- generated Qt inheritance in Ruby classes (including intermediate Qt wrappers)
- Qt-native event/signal runtime wired to Ruby at QObject level (`on`, `connect`, `disconnect`)
- `QTimer` available in generated API with `connect('timeout')` support

### Next

- typed signal payloads (not only raw/placeholder payload)
- richer QObject metaobject Ruby API (`meta_object`, methods/signatures/properties introspection)
- normalize signal naming rules for overloads and deterministic connect behavior
- finish rewriting complex demos to pure event/signal model (`app.exec`, timer-driven updates, no manual polling loops)

### Later

- expand generated surface for additional Qt modules (network, sql, xml, etc.) using the same generator policy
- packaging hardening for Linux/macOS (install/build paths, gem install reliability)
- CI matrix for Ruby/Qt combinations and scope modes (`widgets`, `qobject`, `all`)
- add performance checks for generator traversal and compile size/time regression tracking

## Development

```bash
bundle exec rake test
bundle exec rake compile
bundle exec rake rubocop
```

### Generation Scope

Default build scope is `all`. You can still override scope manually with `QT_RUBY_SCOPE`:

- `widgets` (default): QWidget/QLayout-oriented classes.
- `qobject`: QObject descendants excluding QWidget/QLayout branch.
- `all`: combined public surface from `widgets` + `qobject` scopes (default build mode).

Examples:

```bash
QT_RUBY_SCOPE=widgets bundle exec rake compile
QT_RUBY_SCOPE=qobject bundle exec rake compile
QT_RUBY_SCOPE=all bundle exec rake compile
```

If Qt is in a custom prefix:

```bash
export PKG_CONFIG_PATH="/path/to/qt/lib/pkgconfig:$PKG_CONFIG_PATH"
```

# qt

`qt` is an early-stage Ruby GUI bindings library built on top of Qt 6.10+.

## Status

This repository currently provides:

- gem/project skeleton;
- native C ABI bridge to Qt (called from Ruby via `ffi`);
- Ruby wrappers for `QApplication`, `QWidget`, `QLabel`.

## Requirements

- Ruby 3.1+
- Qt 6.10+ (`Qt6Core`, `Qt6Gui`, `Qt6Widgets` visible via `pkg-config`)
- C++17 compiler

## Build

```bash
bundle install
bundle exec rake compile
bundle exec rake install
```

For installed gem usage:

```bash
gem install qt
```

`rake compile` first generates the bridge from system Qt headers, then compiles it.
All generated artifacts are written under `build/`.

If Qt is installed in a custom location, expose it to `pkg-config`:

```bash
export PKG_CONFIG_PATH="/path/to/qt/lib/pkgconfig:$PKG_CONFIG_PATH"
```

## Usage

```ruby
require 'qt'

app = QApplication.new(0, [])

window = QWidget.new do |w|
  w.setWindowTitle('Qt Ruby App')
  w.resize(800, 600)
end

QLabel.new(window) do |l|
  l.setText('Hello from Ruby')
  l.setAlignment(Qt::AlignCenter)
  l.setGeometry(0, 0, 800, 600)
end

app.exec
```

Or run the example:

```bash
ruby examples/dsl_hello.rb
ruby examples/live_console.rb
ruby examples/live_layout_console.rb
```

Inside `live_layout_console.rb` IRB:

```ruby
add_label("Dynamic label")
add_button("Dynamic button")
remove_last
gui { window.resize(900, 600) }
```

## Project layout

- `lib/qt`: public Ruby API
- `scripts/generate_bridge.rb`: bridge generator (reads system Qt headers)
- `scripts/specs/qt_widgets.rb`: declarative widget/API spec for generation
- `ext/qt_ruby_bridge`: native extension build scripts
- `build/generated`: generated C++ and Ruby bindings
- `build/qt`: compiled native bridge (`qt_ruby_bridge.so`)
- `examples`: runnable demos
- `test`: Ruby-layer tests

## Next steps

- event/callback bridge from Qt signals to Ruby blocks;
- richer widgets API;
- packaging and CI matrix for Linux/macOS.

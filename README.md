# qt-ruby

`qt-ruby` is an early-stage Ruby GUI library built on top of Qt 6.10+.

## Status

This repository currently provides:

- gem/project skeleton;
- native C++ extension bridge to Qt;
- minimal API to read Qt version and open a window.

## Requirements

- Ruby 3.1+
- Qt 6.10+ (`Qt6Core`, `Qt6Gui`, `Qt6Widgets` visible via `pkg-config`)
- C++17 compiler

## Build

```bash
bundle install
bundle exec rake compile
```

If Qt is installed in a custom location, expose it to `pkg-config`:

```bash
export PKG_CONFIG_PATH="/path/to/qt/lib/pkgconfig:$PKG_CONFIG_PATH"
```

## Usage

```ruby
require 'qt'

app = Qt::Application.new(title: 'My App', width: 800, height: 600)
puts Qt::Application.qt_version
app.run
```

Or run the example:

```bash
ruby examples/hello_window.rb
```

## Project layout

- `lib/qt`: public Ruby API
- `ext/qt_ruby_ext`: native Qt bridge
- `examples`: runnable demos
- `test`: Ruby-layer tests

## Next steps

- event/callback bridge from Qt signals to Ruby blocks;
- richer widgets API;
- packaging and CI matrix for Linux/macOS.

# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog.

## [0.1.5] - 2026-03-16

### Added

- Add `:wheel` support to the event runtime.
- Add minimal wheel payload fields: `pixel_delta_y` and `angle_delta_y`.

### Changed

- Allow Ruby event handlers to return `false` or `:ignore` to mark native Qt events as ignored.
- Generate `EventRuntime` event name mappings from Qt `QEvent::Type` enums instead of maintaining a hand-written Ruby-side list.

## [0.1.4] - 2026-03-14

### Changed

- Wrap `QObject`-derived pointer returns into generated Ruby wrapper objects instead of exposing raw `FFI::Pointer` values for APIs such as `focus_widget` and `child_at`.

### Fixed

- Add bridge coverage for wrapped widget/object returns in `QWidget` and `QApplication`.

## [0.1.3] - 2026-03-05

### Added

- Add Fedora/COPR RPM packaging for `ruby-qt`.
- Document quick install paths for RubyGems and Fedora COPR.

### Changed

- Lower minimum supported Ruby version to `3.2+`.
- Lower minimum supported Qt version to `6.4.2+`.
- Ship the native bridge in the RPM package so target machines do not need to build it locally.

## [0.1.1] - 2026-03-05

### Added

- Publish initial RubyGems release metadata.
- Add maintainer metadata and BSD-2-Clause licensing metadata.
- Add `QShortcut` / `QKeySequence` typed bridge support.
- Add generated scoped Qt enum constants.
- Generate runtime free functions from Qt AST and runtime headers.
- Normalize bridge string encoding to UTF-8 by default.
- Add `QApplication` identity APIs for desktop integration.
- Harden `QApplication` shutdown order and GUI-thread lifecycle checks.

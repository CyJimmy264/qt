# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog.

## [Unreleased]

### Changed

- Keep canonical Ruby wrapper identity for `QObject`-derived native handles by caching wrappers per native object, reusing them across wrapping paths such as `parent`, `child_at`, and `focus_widget`, and invalidating the cache on `QObject::destroyed`.
- Share native signal registrations between internal bridge hooks and user callbacks so internal lifecycle hooks do not duplicate user signal delivery.
- Return `QObject::children()` from Qt-derived bridge data instead of maintaining a separate Ruby-side `children` mirror, and decode `QObjectList` results into canonical wrapped Ruby objects.

## [0.1.6] - 2026-03-16

### Added

- Generate event payload schemas from Qt-derived event classes and switch the native event callback ABI to JSON payload delivery.
- Expand generated event payload coverage for additional event families, including enter, context menu, hover, drag-and-drop related events.
- Add end-to-end event runtime delivery coverage for reproducible lifecycle events including move, show, hide, and close.

### Changed

- Derive event payload classes without hand-written regex rules and use deterministic, more specific family matching when resolving Qt event subclasses.
- Distinguish ignored versus consumed event runtime callbacks: `false` / `:ignore` now keep pass-through semantics, while `true` / `:consume` consume the Qt event and make the native event filter return `true`.

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

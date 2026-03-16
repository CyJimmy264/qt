# frozen_string_literal: true

require_relative 'test_helper'
require 'open3'
require 'rbconfig'
require 'date'

class QtBindingsTest < Minitest::Test
  def setup
    Qt::ObjectWrapper.reset_cache!
    Qt::EventRuntime.instance_variable_set(:@internal_signal_handlers, nil)
    Qt::EventRuntime.instance_variable_set(:@signal_registrations, nil)
  end

  def teardown
    Qt::ObjectWrapper.reset_cache!
    Qt::EventRuntime.instance_variable_set(:@internal_signal_handlers, nil)
    Qt::EventRuntime.instance_variable_set(:@signal_registrations, nil)
  end

  def test_version_present
    refute_nil Qt::VERSION
  end

  def test_native_loadability_boolean
    assert_includes [true, false], Qt::Native.available?
  end

  def test_qapplication_tracks_current_instance
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do |app|
      assert_equal app, Qt::QApplication.current

      assert_equal QApplication.qtVersion, QApplication.qt_version
    end
  end

  def test_qapplication_keyboard_modifiers_api_smoke
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      mods = QApplication.keyboard_modifiers
      query_mods = QApplication.query_keyboard_modifiers

      assert_kind_of Integer, mods
      assert_kind_of Integer, query_mods

      assert_equal mods, QApplication.keyboardModifiers
      assert_equal query_mods, QApplication.queryKeyboardModifiers

      assert_kind_of Integer, (mods & Qt::ControlModifier)
      assert_kind_of Integer, (mods & Qt::ShiftModifier)
    end
  end

  def test_qapplication_identity_setters_roundtrip
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      QApplication.set_application_name('QTimetrap')
      QApplication.set_application_display_name('QTimetrap UI')
      QApplication.set_organization_name('mveynberg')
      QApplication.set_desktop_file_name('qtimetrap')

      assert_equal 'QTimetrap', QApplication.application_name
      assert_equal 'QTimetrap UI', QApplication.application_display_name
      assert_equal 'mveynberg', QApplication.organization_name
      assert_equal 'qtimetrap', QApplication.desktop_file_name
    end
  end

  def test_qapplication_dispose_is_idempotent
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do |app|
      assert_equal true, app.dispose
      assert_nil app.handle
      assert_nil QApplication.current
      assert_nil app.dispose
    end
  end

  def test_qapplication_repeated_create_dispose_cycle
    skip 'native bridge is not available' unless Qt::Native.available?

    4.times do
      app = QApplication.new(0, ['bridge-cycle'])
      window = QWidget.new
      window.show
      QApplication.process_events
      assert_equal true, app.dispose
    end
  end

  def test_qapplication_dispose_from_non_gui_thread_is_rejected
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do |app|
      dispose_result = nil
      silence_native_stderr do
        Thread.new { dispose_result = app.dispose }.join
      end

      assert_equal false, dispose_result
      refute_nil app.handle
      assert_equal true, app.dispose
    end
  end

  def test_qapplication_subprocess_shutdown_has_no_qthreadstorage_warning
    skip 'native bridge is not available' unless Qt::Native.available?

    lib_dir = File.expand_path('../lib', __dir__)
    script = <<~'RUBY'
      require 'qt'
      app = Qt::QApplication.new(0, ['bridge-shutdown-smoke'])
      window = Qt::QWidget.new
      window.show
      Qt::QApplication.process_events
      window.close
      Qt::QApplication.process_events
      app.dispose
    RUBY
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_dir, '-e', script)
    assert status.success?, "subprocess failed\nstdout:\n#{stdout}\nstderr:\n#{stderr}"
    refute_match(/QThreadStorage:\s*entry\s+\d+\s+destroyed before end of thread/i, stderr)
  end

  def test_qapplication_keyboard_modifiers_manual_ctrl_shift_smoke
    skip 'native bridge is not available' unless Qt::Native.available?
    skip 'manual smoke; set QT_RUBY_MANUAL_MODIFIERS=1 to enable' unless ENV['QT_RUBY_MANUAL_MODIFIERS'] == '1'

    with_qapplication do
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3.0
      seen = false

      while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        QApplication.process_events
        mods = QApplication.keyboard_modifiers
        if (mods & Qt::ControlModifier) != 0 || (mods & Qt::ShiftModifier) != 0
          seen = true
          break
        end
        sleep(0.01)
      end

      assert seen, 'expected ControlModifier or ShiftModifier while key is held'
    end
  end

  def test_qwidget_and_qlabel_register_children
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window = QWidget.new
      label = QLabel.new(window)
      label.text = 'A'

      assert_equal 1, window.children.size
      assert_equal label, window.children.first
      assert_equal 'A', label.text
    end
  end

  def test_qobject_children_returns_canonical_wrappers_from_qt
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window = QWidget.new
      label = QLabel.new(window)
      label.set_text('A')

      a = window.children.first
      a.instance_variable_set(:@foo, 123)
      b = window.children.first

      assert a.equal?(label)
      assert a.equal?(b)
      assert_equal 123, b.instance_variable_get(:@foo)
    end
  end

  def test_qwidget_focus_widget_returns_wrapped_widget
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window = QWidget.new
      input = QLineEdit.new(window)
      input.set_object_name('task_input')
      input.set_geometry(10, 10, 120, 30)
      window.set_geometry(0, 0, 240, 120)
      window.show
      input.set_focus
      QApplication.process_events

      focused = window.focus_widget

      assert_kind_of QLineEdit, focused
      assert_equal 'task_input', focused.object_name
    end
  end

  def test_qwidget_child_at_returns_wrapped_widget_or_nil
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window = QWidget.new
      input = QLineEdit.new(window)
      input.set_object_name('child_input')
      input.set_geometry(20, 20, 100, 24)
      window.set_geometry(0, 0, 240, 120)
      window.show
      QApplication.process_events

      child = window.child_at(25, 25)

      assert_kind_of QLineEdit, child
      assert_equal 'child_input', child.object_name
      assert_nil window.child_at(200, 100)
    end
  end

  def test_qobject_parent_wrapper_has_stable_identity
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      parent = QWidget.new
      child = QLineEdit.new(parent)

      a = child.parent
      b = child.parent

      assert a.equal?(b)
      assert a.equal?(parent)
    end
  end

  def test_qwidget_child_at_wrapper_preserves_ruby_ivars_across_rewrapping
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window = QWidget.new
      child = QLineEdit.new(window)
      child.set_geometry(20, 20, 100, 24)
      window.set_geometry(0, 0, 240, 120)
      window.show
      QApplication.process_events

      a = window.child_at(25, 25)
      a.instance_variable_set(:@foo, 123)
      b = window.child_at(25, 25)

      assert a.equal?(child)
      assert a.equal?(b)
      assert_equal 123, b.instance_variable_get(:@foo)
    end
  end

  def test_focus_widget_wrappers_share_canonical_identity
    skip 'native bridge is not available' unless Qt::Native.available?
    skip 'QApplication.focus_widget is not available in this generated scope' unless QApplication.respond_to?(:focus_widget)

    with_qapplication do
      window = QWidget.new
      input = QLineEdit.new(window)
      input.set_geometry(10, 10, 120, 30)
      window.set_geometry(0, 0, 240, 120)
      window.show
      input.set_focus
      QApplication.process_events

      from_window = window.focus_widget
      from_app = QApplication.focus_widget
      from_window.instance_variable_set(:@focus_marker, 'ok')

      assert from_window.equal?(input)
      assert from_window.equal?(from_app)
      assert_equal 'ok', from_app.instance_variable_get(:@focus_marker)
    end
  end

  def test_object_wrapper_cache_is_cleared_after_destroyed
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window = QWidget.new
      window.set_attribute(Qt::WA_DeleteOnClose, 1)
      window.set_geometry(0, 0, 240, 120)
      window.show
      QApplication.process_events

      wrapped = Qt::ObjectWrapper.wrap(window.handle, 'QWidget')
      address = wrapped.handle.address
      wrapped.instance_variable_set(:@foo, 123)

      window.close
      20.times do
        QApplication.process_events
        QApplication.send_posted_events if QApplication.respond_to?(:send_posted_events)
        break unless Qt::ObjectWrapper.instance_variable_get(:@wrapper_cache)&.key?(address)

        sleep(0.005)
      end

      refute Qt::ObjectWrapper.instance_variable_get(:@wrapper_cache)&.key?(address)
    end
  end

  def test_qapplication_focus_widget_returns_wrapped_widget
    skip 'native bridge is not available' unless Qt::Native.available?
    skip 'QApplication.focus_widget is not available in this generated scope' unless QApplication.respond_to?(:focus_widget)

    with_qapplication do
      window = QWidget.new
      input = QLineEdit.new(window)
      input.set_object_name('global_focus_input')
      input.set_geometry(10, 10, 120, 30)
      window.set_geometry(0, 0, 240, 120)
      window.show
      input.set_focus
      QApplication.process_events

      focused = QApplication.focus_widget

      assert_kind_of QLineEdit, focused
      assert_equal 'global_focus_input', focused.object_name
    end
  end

  def test_qlineedit_text_roundtrip_utf8_cyrillic
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      input = QLineEdit.new
      input.set_text('Привет, мир')

      value = input.text
      assert_equal Encoding::UTF_8, value.encoding
      assert_equal 'Привет, мир', value
    end
  end

  def test_qlineedit_accepts_ascii_8bit_with_valid_utf8_bytes
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      source = 'Привет'.dup.encode(Encoding::UTF_8).b
      assert_equal Encoding::ASCII_8BIT, source.encoding

      input = QLineEdit.new
      input.set_text(source)

      value = input.text
      assert_equal Encoding::UTF_8, value.encoding
      assert_equal 'Привет', value
    end
  end

  def test_qlineedit_invalid_bytes_do_not_crash_and_are_replaced
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      input = QLineEdit.new
      input.set_text("\xFF\xFEtask".b)

      value = input.text
      assert_equal Encoding::UTF_8, value.encoding
      assert value.valid_encoding?
      assert_includes value, 'task'
      assert_includes value, "\uFFFD"
    end
  end

  def test_qwidget_and_qlabel_inspection_aliases
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window = QWidget.new
      label = QLabel.new(window)
      label.text = 'A'

      inspected = label.q_inspect
      qt_inspected = label.qt_inspect
      hash_inspected = label.to_h

      assert_equal 'QLabel', inspected[:qt_class]
      assert_equal inspected[:qt_class], qt_inspected[:qt_class]
      assert_equal inspected[:qt_class], hash_inspected[:qt_class]
      assert_equal inspected.dig(:properties, :text), qt_inspected.dig(:properties, :text)
      assert_equal inspected.dig(:properties, :text), hash_inspected.dig(:properties, :text)
    end
  end

  def test_qwidget_and_qlabel_inspection_properties
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window = QWidget.new
      label = QLabel.new(window)
      label.text = 'A'

      assert_equal 'A', label.q_inspect.dig(:properties, :text)
    end
  end

  def test_widget_layout_smoke
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window, label, layout, button = build_widget_layout_fixture
      exercise_widget_layout_fixture(window, label, layout, button)
    end
  end

  def test_widget_visibility_uses_boolean_api
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window = QWidget.new

      window.set_visible(true)

      assert window.is_visible

      window.set_visible(false)

      refute window.is_visible
    end
  end

  def test_qdatetimeedit_roundtrip_time_with_timezone_and_seconds
    skip 'native bridge is not available' unless Qt::Native.available?
    skip 'QDateTimeEdit is not available in this generated scope' unless Qt.const_defined?(:QDateTimeEdit)

    with_qapplication do
      editor = QDateTimeEdit.new
      editor.set_time_spec(Qt::UTC) if editor.respond_to?(:set_time_spec)
      source = Time.new(2026, 3, 2, 17, 45, 12, '+00:00')
      editor.set_date_time(source)
      roundtrip = editor.date_time

      assert_kind_of Time, roundtrip
      assert_equal source.to_i, roundtrip.to_i
      assert_equal source.sec, roundtrip.sec
      assert_kind_of Integer, roundtrip.utc_offset
    end
  end

  def test_qdatetimeedit_min_max_limits
    skip 'native bridge is not available' unless Qt::Native.available?
    skip 'QDateTimeEdit is not available in this generated scope' unless Qt.const_defined?(:QDateTimeEdit)

    with_qapplication do
      editor = QDateTimeEdit.new
      min = Time.new(2026, 3, 1, 10, 0, 0, '+00:00')
      max = Time.new(2026, 3, 1, 11, 0, 0, '+00:00')
      editor.set_minimum_date_time(min)
      editor.set_maximum_date_time(max)

      editor.set_date_time(Time.new(2026, 3, 1, 12, 30, 0, '+00:00'))
      value = editor.date_time

      assert_operator value.to_i, :<=, max.to_i
      assert_operator value.to_i, :>=, min.to_i
    end
  end

  def test_qdatetimeedit_calendar_popup_smoke
    skip 'native bridge is not available' unless Qt::Native.available?
    skip 'QDateTimeEdit is not available in this generated scope' unless Qt.const_defined?(:QDateTimeEdit)

    with_qapplication do
      editor = QDateTimeEdit.new
      editor.set_calendar_popup(true)
      calendar = editor.calendar_widget

      refute_nil calendar
      assert(!calendar.respond_to?(:null?) || !calendar.null?)
    end
  end

  def test_qcalendarwidget_selected_date_roundtrip
    skip 'native bridge is not available' unless Qt::Native.available?
    skip 'QCalendarWidget is not available in this generated scope' unless Qt.const_defined?(:QCalendarWidget)

    with_qapplication do
      calendar = QCalendarWidget.new
      source = Date.new(2026, 3, 2)
      calendar.set_selected_date(source)
      assert_equal source, calendar.selected_date
    end
  end

  def test_qshortcut_constructor_accepts_qkeysequence_and_parent
    skip 'native bridge is not available' unless Qt::Native.available?
    skip 'QShortcut is not available in this generated scope' unless Qt.const_defined?(:QShortcut)
    skip 'QKeySequence is not available in this generated scope' unless Qt.const_defined?(:QKeySequence)

    with_qapplication do
      parent = QWidget.new
      seq = QKeySequence.new('Space')
      shortcut = QShortcut.new(seq, parent)

      refute_nil shortcut.handle
    end
  end

  def test_qshortcut_set_keys_accepts_qkeysequence_via_compat_path
    skip 'native bridge is not available' unless Qt::Native.available?
    skip 'QShortcut is not available in this generated scope' unless Qt.const_defined?(:QShortcut)
    skip 'QKeySequence is not available in this generated scope' unless Qt.const_defined?(:QKeySequence)

    with_qapplication do
      parent = QWidget.new
      shortcut = QShortcut.new(parent)
      seq = QKeySequence.new('Space')

      shortcut.set_key(seq) if shortcut.respond_to?(:set_key)
      shortcut.set_keys(seq)
      shortcut.set_keys(0)
    end
  end

  private

  def silence_native_stderr
    original_stderr = STDERR.dup
    File.open(File::NULL, 'w') do |null|
      STDERR.reopen(null)
      yield
    end
  ensure
    STDERR.reopen(original_stderr)
    original_stderr.close
  end

  def build_widget_layout_fixture
    window = QWidget.new
    label = QLabel.new(window)
    layout = QVBoxLayout.new(window)
    button = QPushButton.new(window)
    button.set_text('Click')
    [window, label, layout, button]
  end

  def exercise_widget_layout_fixture(window, label, layout, button)
    window.set_layout(layout)
    window.set_geometry(50, 60, 320, 240)
    window.x
    window.y
    layout.add_widget(button)
    layout.remove_widget(button)
    button.hide
    label.set_style_sheet('background-color: #fafafa;')
  end

  def with_qapplication
    app = QApplication.new(0, [])
    yield(app)
  ensure
    app&.dispose
  end
end

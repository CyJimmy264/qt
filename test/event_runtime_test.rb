# frozen_string_literal: true

require_relative 'test_helper'

module QtEventRuntimeTestHelpers
  def setup
    reset_event_runtime_state
  end

  def teardown
    reset_event_runtime_state
  end

  private

  def reset_event_runtime_state
    Qt::EventRuntime.instance_variable_set(:@event_handlers, nil)
    Qt::EventRuntime.instance_variable_set(:@signal_handlers, nil)
    Qt::EventRuntime.instance_variable_set(:@internal_signal_handlers, nil)
    Qt::EventRuntime.instance_variable_set(:@signal_registrations, nil)
    Qt::EventRuntime.instance_variable_set(:@event_callback, nil)
    Qt::EventRuntime.instance_variable_set(:@signal_callback, nil)
  end

  def with_qapplication
    app = QApplication.new(0, [])
    yield
  ensure
    app&.dispose
  end
end

class QtEventRuntimeApiTest < Minitest::Test
  include QtEventRuntimeTestHelpers

  def test_native_does_not_expose_runtime_helpers
    refute_respond_to Qt::Native, :on_event
    refute_respond_to Qt::Native, :on_signal
  end

  def test_native_does_not_expose_runtime_detach_helpers
    refute_respond_to Qt::Native, :off_event
    refute_respond_to Qt::Native, :off_signal
  end

  def test_widget_methods_validate_blocks
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window = QWidget.new

      assert_raises(ArgumentError) { window.on(:resize) }
      assert_raises(ArgumentError) { window.connect('clicked') }
    end
  end

  def test_widget_event_subscription_smoke
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window = QWidget.new

      assert_equal window, window.on(:resize) { |_ev| nil }
      assert_equal window, window.off_event(:resize)
    end
  end

  def test_widget_event_subscription_without_explicit_name
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window = QWidget.new

      assert_equal window, window.on(:key_press) { |_ev| nil }
      assert_equal window, window.off_event
    end
  end

  def test_widget_signal_subscription_named_disconnect
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window = QWidget.new
      button = QPushButton.new(window)
      button.set_text('Click')

      assert_equal button, button.connect('clicked') { |_payload| nil }
      assert_equal button, button.disconnect('clicked')
    end
  end

  def test_widget_signal_subscription_default_disconnect
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      button = QPushButton.new

      assert_equal button, button.connect('clicked') { |_payload| nil }
      assert_equal button, button.disconnect
    end
  end

  def test_qtimer_supports_qobject_signal_subscription
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      timer = QTimer.new

      assert_equal timer, timer.connect('timeout') { |_payload| nil }
      assert_equal timer, timer.disconnect('timeout')
    end
  end

  def test_qicon_does_not_expose_qobject_signal_helpers
    skip 'QIcon is not available in this generated scope' unless Qt.const_defined?(:QIcon)

    icon = QIcon.new('')

    refute_respond_to icon, :connect
    refute_respond_to icon, :on
  end

  def test_widget_subscription_validation
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window = QWidget.new
      button = QPushButton.new(window)

      assert_raises(ArgumentError) { window.on(:not_a_real_event) { |_ev| nil } }
      assert_equal window, window.on(:wheel) { |_ev| nil }
      assert_equal window, window.off_event(:wheel)
      assert_raises(ArgumentError) { button.connect('') { |_payload| nil } }
    end
  end

  def test_event_type_lookup_uses_generated_qevent_map
    assert_equal Qt::EventWheel, Qt::EventRuntime.event_type_for(:wheel)
    assert_equal Qt::EventMouseButtonDblClick, Qt::EventRuntime.event_type_for(:mouse_button_dbl_click)
  end

  def test_generated_event_payload_schema_is_available
    schema = Qt::GENERATED_EVENT_PAYLOAD_SCHEMAS[:wheel]

    refute_nil schema
    assert_equal Qt::EventWheel, schema[:event_type]
    assert_equal 'QWheelEvent', schema[:event_class]
  end

  def test_generated_event_payload_schema_covers_phase_two_event_families
    assert_equal 'QMouseEvent', Qt::GENERATED_EVENT_PAYLOAD_SCHEMAS[:mouse_button_press][:event_class]
    assert_equal 'QMouseEvent', Qt::GENERATED_EVENT_PAYLOAD_SCHEMAS[:non_client_area_mouse_move][:event_class]
    assert_equal 'QKeyEvent', Qt::GENERATED_EVENT_PAYLOAD_SCHEMAS[:key_press][:event_class]
    assert_equal 'QFocusEvent', Qt::GENERATED_EVENT_PAYLOAD_SCHEMAS[:focus_out][:event_class]
    assert_equal 'QFocusEvent', Qt::GENERATED_EVENT_PAYLOAD_SCHEMAS[:focus_about_to_change][:event_class]
    assert_equal 'QEnterEvent', Qt::GENERATED_EVENT_PAYLOAD_SCHEMAS[:enter][:event_class]
    assert_equal 'QContextMenuEvent', Qt::GENERATED_EVENT_PAYLOAD_SCHEMAS[:context_menu][:event_class]
    assert_equal 'QHoverEvent', Qt::GENERATED_EVENT_PAYLOAD_SCHEMAS[:hover_move][:event_class]
    assert_equal 'QDragEnterEvent', Qt::GENERATED_EVENT_PAYLOAD_SCHEMAS[:drag_enter][:event_class]
    assert_equal 'QDragMoveEvent', Qt::GENERATED_EVENT_PAYLOAD_SCHEMAS[:drag_move][:event_class]
    assert_equal 'QDragLeaveEvent', Qt::GENERATED_EVENT_PAYLOAD_SCHEMAS[:drag_leave][:event_class]
    assert_equal 'QDropEvent', Qt::GENERATED_EVENT_PAYLOAD_SCHEMAS[:drop][:event_class]
  end

  def test_signal_resolution_requires_valid_signature
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      button = QPushButton.new

      assert_equal button, button.connect('clicked(bool)') { |_payload| nil }
      assert_equal button, button.disconnect('clicked(bool)')
      assert_raises(ArgumentError) { button.connect('clicked(QString)') { |_payload| nil } }
    end
  end
end

class QtEventRuntimeDeliveryTest < Minitest::Test
  include QtEventRuntimeTestHelpers

  def test_event_payload_contract_for_mouse_events
    assert_payload_forwarding(Qt::EventMouseButtonPress, { x: 12.0, y: 34.0, button: 1, buttons: 3, a: 12.0, b: 34.0, c: 1, d: 3 })
    assert_payload_forwarding(Qt::EventMouseButtonRelease, { x: 8.0, y: 9.0, button: 1, buttons: 0, a: 8.0, b: 9.0, c: 1, d: 0 })
    assert_payload_forwarding(Qt::EventMouseMove, { x: 101.0, y: 202.0, button: 0, buttons: 1, a: 101.0, b: 202.0, c: 0, d: 1 })
  end

  def test_event_payload_contract_for_key_events
    assert_payload_forwarding(Qt::EventKeyPress, { key: 65, modifiers: 0, is_auto_repeat: false, count: 1, a: 65, b: 0, c: false, d: 1 })
    assert_payload_forwarding(Qt::EventKeyRelease, { key: 13, modifiers: 0, is_auto_repeat: true, count: 2, a: 13, b: 0, c: true, d: 2 })
  end

  def test_event_payload_contract_for_resize_event
    assert_payload_forwarding(Qt::EventResize, { width: 640, height: 360, old_width: 320, old_height: 180, a: 640, b: 360, c: 320, d: 180 })
  end

  def test_event_payload_contract_for_wheel_event
    captured = assert_payload_forwarding(Qt::EventWheel, { angle_delta_x: 0, angle_delta_y: 120, pixel_delta_x: 0, pixel_delta_y: 4, buttons: 0, a: 4, b: 120, c: 0, d: 0 })
    assert_equal 4, captured[:pixel_delta_y]
    assert_equal 120, captured[:angle_delta_y]
  end

  def test_event_dispatch_return_value_false_marks_event_ignored
    ptr = FFI::Pointer.new(0x1234)
    handlers = { ptr.address => { Qt::EventWheel => [->(_payload) { false }] } }

    result = Qt::EventRuntimeDispatch.dispatch_event(handlers, ptr, Qt::EventWheel, { type: Qt::EventWheel })

    assert_equal Qt::EventRuntimeDispatch::EVENT_RESULT_IGNORE, result
  end

  def test_event_dispatch_return_value_symbol_ignore_marks_event_ignored
    ptr = FFI::Pointer.new(0x1234)
    handlers = { ptr.address => { Qt::EventWheel => [->(_payload) { :ignore }] } }

    result = Qt::EventRuntimeDispatch.dispatch_event(handlers, ptr, Qt::EventWheel, { type: Qt::EventWheel })

    assert_equal Qt::EventRuntimeDispatch::EVENT_RESULT_IGNORE, result
  end

  def test_event_dispatch_return_value_true_marks_event_consumed
    ptr = FFI::Pointer.new(0x1234)
    handlers = { ptr.address => { Qt::EventWheel => [->(_payload) { true }] } }

    result = Qt::EventRuntimeDispatch.dispatch_event(handlers, ptr, Qt::EventWheel, { type: Qt::EventWheel })

    assert_equal Qt::EventRuntimeDispatch::EVENT_RESULT_CONSUME, result
  end

  def test_event_dispatch_return_value_symbol_consume_marks_event_consumed
    ptr = FFI::Pointer.new(0x1234)
    handlers = { ptr.address => { Qt::EventWheel => [->(_payload) { :consume }] } }

    result = Qt::EventRuntimeDispatch.dispatch_event(handlers, ptr, Qt::EventWheel, { type: Qt::EventWheel })

    assert_equal Qt::EventRuntimeDispatch::EVENT_RESULT_CONSUME, result
  end

  def test_resize_event_end_to_end
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      payloads = capture_resize_payloads
      ev = find_resize_payload(payloads, 400, 260)
      skip 'resize to target geometry was not observed in this Qt platform environment' unless ev
    end
  end

  def test_move_event_end_to_end
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      payloads = capture_move_payloads
      ev = find_move_payload(payloads, 45, 55)
      skip 'move to target position was not observed in this Qt platform environment' unless ev

      assert_equal Qt::EventMove, ev[:type]
      assert_equal 45, ev[:x]
      assert_equal 55, ev[:y]
    end
  end

  def test_show_event_end_to_end
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      payloads = capture_show_payloads
      skip 'show event was not delivered in this Qt platform environment' if payloads.empty?

      assert_operator payloads.length, :>=, 1
      assert_equal Qt::EventShow, payloads.last[:type]
    end
  end

  def test_hide_event_end_to_end
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      payloads = capture_hide_payloads
      skip 'hide event was not delivered in this Qt platform environment' if payloads.empty?

      assert_operator payloads.length, :>=, 1
      assert_equal Qt::EventHide, payloads.last[:type]
    end
  end

  def test_close_event_end_to_end
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      payloads = capture_close_payloads
      skip 'close event was not delivered in this Qt platform environment' if payloads.empty?

      assert_operator payloads.length, :>=, 1
      assert_equal Qt::EventClose, payloads.last[:type]
    end
  end

  def test_clicked_bool_signal_end_to_end_via_button_click
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      calls = capture_clicked_bool_calls
      verify_clicked_signal_delivered(calls)
    end
  end

  def test_focus_event_delivered_for_watched_ancestor
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window = QWidget.new
      parent = QWidget.new(window)
      child = QPushButton.new(parent)
      parent.set_geometry(20, 20, 200, 120)
      child.set_geometry(10, 10, 120, 30)
      parent.show
      child.show
      window.show
      QApplication.process_events

      parent_events = []
      parent.on(:focus_in) { |ev| parent_events << ev }
      child.set_focus
      wait_for_non_empty_payloads(parent_events)

      skip 'focus event was not delivered in this Qt platform environment' if parent_events.empty?

      assert_operator parent_events.length, :>=, 1
    end
  end

  def test_focus_event_is_not_double_dispatched_when_child_watched
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window = QWidget.new
      parent = QWidget.new(window)
      child = QPushButton.new(parent)
      parent.set_geometry(20, 20, 200, 120)
      child.set_geometry(10, 10, 120, 30)
      parent.show
      child.show
      window.show
      QApplication.process_events

      parent_events = []
      child_events = []
      parent.on(:focus_in) { |ev| parent_events << ev }
      child.on(:focus_in) { |ev| child_events << ev }

      # Drop startup focus noise and check one explicit focus transition.
      parent_events.clear
      child_events.clear
      child.set_focus
      wait_for_non_empty_payloads(child_events)

      skip 'focus event was not delivered in this Qt platform environment' if child_events.empty?

      assert_operator child_events.length, :>=, 1
      assert_equal 0, parent_events.length
    end
  end

  def test_scroll_hierarchy_focus_events_survive_repeated_show_hide_cycles
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window = QWidget.new
      scroll = QScrollArea.new(window)
      host = QWidget.new
      button = QPushButton.new(host)
      scroll.set_geometry(0, 0, 320, 240)
      host.set_geometry(0, 0, 300, 600)
      button.set_geometry(20, 20, 140, 30)
      scroll.set_widget(host)
      scroll.show
      window.show
      QApplication.process_events

      events = []
      scroll.on(:focus_in) { |ev| events << ev }

      6.times do
        host.hide
        QApplication.process_events
        host.show
        QApplication.process_events
        button.set_focus
        QApplication.process_events
      end

      skip 'focus event was not delivered in this Qt platform environment' if events.empty?

      assert_operator events.length, :>=, 3
    end
  end

  def test_signal_payload_is_normalized_to_utf8
    ptr = FFI::Pointer.new(0x2222)
    captured = []

    handlers = {
      ptr.address => {
        'textChanged(QString)' => { index: 7, blocks: [->(payload) { captured << payload }] }
      }
    }
    Qt::EventRuntime.instance_variable_set(:@signal_handlers, handlers)
    Qt::EventRuntime.ensure_signal_callback!
    callback = Qt::EventRuntime.instance_variable_get(:@signal_callback)

    callback.call(ptr, 7, "Привет".b)

    assert_equal 1, captured.length
    assert_equal Encoding::UTF_8, captured.first.encoding
    assert_equal 'Привет', captured.first
  end

  def test_signal_payload_invalid_bytes_are_replaced
    ptr = FFI::Pointer.new(0x3333)
    captured = []

    handlers = {
      ptr.address => {
        'textChanged(QString)' => { index: 8, blocks: [->(payload) { captured << payload }] }
      }
    }
    Qt::EventRuntime.instance_variable_set(:@signal_handlers, handlers)
    Qt::EventRuntime.ensure_signal_callback!
    callback = Qt::EventRuntime.instance_variable_get(:@signal_callback)

    callback.call(ptr, 8, "\xFF\xFEok".b)

    assert_equal 1, captured.length
    assert_equal Encoding::UTF_8, captured.first.encoding
    assert captured.first.valid_encoding?
    assert_includes captured.first, 'ok'
    assert_includes captured.first, "\uFFFD"
  end

  def test_qdatetimeedit_datetime_changed_signal_payload_is_time
    skip 'native bridge is not available' unless Qt::Native.available?
    skip 'QDateTimeEdit is not available in this generated scope' unless Qt.const_defined?(:QDateTimeEdit)

    with_qapplication do
      editor = QDateTimeEdit.new
      editor.set_time_spec(Qt::UTC) if editor.respond_to?(:set_time_spec)
      payloads = []
      editor.connect('dateTimeChanged(QDateTime)') { |payload| payloads << payload }
      source = Time.new(2026, 3, 2, 19, 33, 44, '+00:00')
      editor.set_date_time(source)

      wait_for_non_empty_payloads(payloads)
      skip 'dateTimeChanged was not delivered in this Qt platform environment' if payloads.empty?

      assert_kind_of Time, payloads.last
      assert_equal source.to_i, payloads.last.to_i
      assert_equal source.sec, payloads.last.sec
      assert_kind_of Integer, payloads.last.utc_offset
    end
  end

  def test_qdatetimeedit_subscriptions_survive_repeated_show_hide_and_destroy
    skip 'native bridge is not available' unless Qt::Native.available?
    skip 'QDateTimeEdit is not available in this generated scope' unless Qt.const_defined?(:QDateTimeEdit)

    with_qapplication do
      4.times do
        window = QWidget.new
        editor = QDateTimeEdit.new(window)
        payloads = []
        editor.connect('timeChanged(QTime)') { |payload| payloads << payload }
        window.show
        QApplication.process_events
        editor.set_date_time(Time.new(2026, 3, 2, 9, 10, 11, '+00:00'))
        QApplication.process_events
        window.hide
        QApplication.process_events
        window.close
        QApplication.process_events
      end
    end
  end

  private

  def wait_for_non_empty_payloads(payloads)
    20.times do
      QApplication.process_events
      break unless payloads.empty?

      sleep(0.005)
    end
  end

  def find_resize_payload(payloads, width, height)
    payloads.find { |payload| payload[:type] == Qt::EventResize && payload[:width] == width && payload[:height] == height }
  end

  def find_move_payload(payloads, x, y)
    payloads.find { |payload| payload[:type] == Qt::EventMove && payload[:x] == x && payload[:y] == y }
  end

  def verify_clicked_signal_delivered(calls)
    skip 'clicked(bool) signal was not delivered in this Qt platform environment' if calls.empty?

    assert_operator calls.length, :>=, 1
  end

  def capture_resize_payloads
    window = QWidget.new
    payloads = []
    window.on(:resize) { |ev| payloads << ev }
    show_and_process_events(window)
    window.set_geometry(20, 30, 400, 260)
    wait_for_non_empty_payloads(payloads)
    skip 'resize event was not delivered in this Qt platform environment' if payloads.empty?
    payloads
  end

  def capture_move_payloads
    window = QWidget.new
    payloads = []
    window.on(:move) { |ev| payloads << ev }
    show_and_process_events(window)
    window.move(45, 55)
    wait_for_non_empty_payloads(payloads)
    skip 'move event was not delivered in this Qt platform environment' if payloads.empty?
    payloads
  end

  def capture_show_payloads
    window = QWidget.new
    payloads = []
    window.on(:show) { |ev| payloads << ev }
    show_and_process_events(window)
    payloads
  end

  def capture_hide_payloads
    window = QWidget.new
    payloads = []
    window.on(:hide) { |ev| payloads << ev }
    show_and_process_events(window)
    window.hide
    wait_for_non_empty_payloads(payloads)
    payloads
  end

  def capture_close_payloads
    window = QWidget.new
    payloads = []
    window.on(:close) { |ev| payloads << ev }
    show_and_process_events(window)
    window.close
    wait_for_non_empty_payloads(payloads)
    payloads
  end

  def capture_clicked_bool_calls
    window = QWidget.new
    button = QPushButton.new(window)
    calls = []
    button.connect('clicked(bool)') { |payload| calls << payload }
    button.show
    show_and_process_events(window)
    button.click
    wait_for_non_empty_payloads(calls)
    calls
  end

  def show_and_process_events(widget)
    widget.show
    QApplication.process_events
  end

  def assert_payload_forwarding(event_type, payload)
    ptr = FFI::Pointer.new(0x1234)
    captured = []

    handlers = { ptr.address => { event_type => [->(payload) { captured << payload }] } }
    Qt::EventRuntime.instance_variable_set(:@event_handlers, handlers)
    Qt::EventRuntime.ensure_event_callback!
    callback = Qt::EventRuntime.instance_variable_get(:@event_callback)

    callback.call(ptr, event_type, JSON.generate(payload.merge(type: event_type)))

    assert_equal 1, captured.length
    assert_equal event_type, captured.first[:type]
    payload.each do |key, value|
      assert_equal value, captured.first[key]
    end
    captured.first
  end
end

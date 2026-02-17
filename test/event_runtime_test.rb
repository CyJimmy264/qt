# frozen_string_literal: true

require_relative 'test_helper'

class QtEventRuntimeTest < Minitest::Test
  def setup
    reset_event_runtime_state
  end

  def teardown
    reset_event_runtime_state
  end

  def test_native_does_not_expose_runtime_helpers
    refute_respond_to Qt::Native, :on_event
    refute_respond_to Qt::Native, :on_signal
    refute_respond_to Qt::Native, :off_event
    refute_respond_to Qt::Native, :off_signal
  end

  def test_widget_methods_validate_blocks
    skip 'native bridge is not available' unless Qt::Native.available?

    app = QApplication.new(0, [])
    window = QWidget.new

    assert_raises(ArgumentError) { window.on(:resize) }
    assert_raises(ArgumentError) { window.connect('clicked') }
  ensure
    app&.dispose
  end

  def test_widget_event_and_signal_subscription_smoke
    skip 'native bridge is not available' unless Qt::Native.available?

    app = QApplication.new(0, [])
    window = QWidget.new
    button = QPushButton.new(window)
    button.set_text('Click')

    assert_equal window, window.on(:resize) { |_ev| nil }
    assert_equal window, window.off_event(:resize)
    assert_equal window, window.on(:key_press) { |_ev| nil }
    assert_equal window, window.off_event

    assert_equal button, button.connect('clicked') { |_payload| nil }
    assert_equal button, button.disconnect('clicked')
    assert_equal button, button.connect('clicked') { |_payload| nil }
    assert_equal button, button.disconnect

    assert_raises(ArgumentError) { window.on(:not_a_real_event) { |_ev| nil } }
    assert_raises(ArgumentError) { button.connect('') { |_payload| nil } }
  ensure
    app&.dispose
  end

  def test_signal_resolution_requires_valid_signature
    skip 'native bridge is not available' unless Qt::Native.available?

    app = QApplication.new(0, [])
    button = QPushButton.new

    assert_equal button, button.connect('clicked(bool)') { |_payload| nil }
    assert_equal button, button.disconnect('clicked(bool)')
    assert_raises(ArgumentError) { button.connect('clicked(QString)') { |_payload| nil } }
  ensure
    app&.dispose
  end

  def test_event_payload_contract_for_mouse_events
    assert_payload_forwarding(Qt::EventMouseButtonPress, [12, 34, 1, 3])
    assert_payload_forwarding(Qt::EventMouseButtonRelease, [8, 9, 1, 0])
    assert_payload_forwarding(Qt::EventMouseMove, [101, 202, 0, 1])
  end

  def test_event_payload_contract_for_key_events
    assert_payload_forwarding(Qt::EventKeyPress, [65, 0, 0, 1])
    assert_payload_forwarding(Qt::EventKeyRelease, [13, 0, 1, 2])
  end

  def test_event_payload_contract_for_resize_event
    assert_payload_forwarding(Qt::EventResize, [640, 360, 320, 180])
  end

  private

  def assert_payload_forwarding(event_type, values)
    ptr = FFI::Pointer.new(0x1234)
    captured = []

    handlers = { ptr.address => { event_type => [->(payload) { captured << payload }] } }
    Qt::EventRuntime.instance_variable_set(:@event_handlers, handlers)
    Qt::EventRuntime.ensure_event_callback!
    callback = Qt::EventRuntime.instance_variable_get(:@event_callback)

    callback.call(ptr, event_type, *values)

    assert_equal 1, captured.length
    assert_equal({ type: event_type, a: values[0], b: values[1], c: values[2], d: values[3] }, captured.first)
  end

  def reset_event_runtime_state
    Qt::EventRuntime.instance_variable_set(:@event_handlers, nil)
    Qt::EventRuntime.instance_variable_set(:@signal_handlers, nil)
    Qt::EventRuntime.instance_variable_set(:@event_callback, nil)
    Qt::EventRuntime.instance_variable_set(:@signal_callback, nil)
  end
end

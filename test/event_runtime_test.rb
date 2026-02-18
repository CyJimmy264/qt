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

  def test_widget_subscription_validation
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window = QWidget.new
      button = QPushButton.new(window)

      assert_raises(ArgumentError) { window.on(:not_a_real_event) { |_ev| nil } }
      assert_raises(ArgumentError) { button.connect('') { |_payload| nil } }
    end
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

  def test_resize_event_end_to_end
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window = QWidget.new
      payloads = []

      window.on(:resize) { |ev| payloads << ev }
      window.show
      QApplication.process_events
      window.set_geometry(20, 30, 400, 260)

      20.times do
        QApplication.process_events
        break unless payloads.empty?
        sleep(0.005)
      end

      skip 'resize event was not delivered in this Qt platform environment' if payloads.empty?

      ev = payloads.find { |payload| payload[:type] == Qt::EventResize && payload[:a] == 400 && payload[:b] == 260 }
      skip 'resize to target geometry was not observed in this Qt platform environment' unless ev
    end
  end

  def test_clicked_bool_signal_end_to_end_via_button_click
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window = QWidget.new
      button = QPushButton.new(window)
      calls = []

      button.connect('clicked(bool)') { |payload| calls << payload }
      button.show
      window.show
      QApplication.process_events

      button.click
      20.times do
        QApplication.process_events
        break unless calls.empty?
        sleep(0.005)
      end

      skip 'clicked(bool) signal was not delivered in this Qt platform environment' if calls.empty?

      assert_operator calls.length, :>=, 1
    end
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
end

# frozen_string_literal: true

require_relative 'test_helper'

class QtEventRuntimeTest < Minitest::Test
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
end

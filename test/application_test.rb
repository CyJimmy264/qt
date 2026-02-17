# frozen_string_literal: true

require_relative 'test_helper'

class QtBindingsTest < Minitest::Test
  def test_version_present
    refute_nil Qt::VERSION
  end

  def test_native_loadability_boolean
    assert_includes [true, false], Qt::Native.available?
  end

  def test_qapplication_tracks_current_instance
    skip 'native bridge is not available' unless Qt::Native.available?

    app = QApplication.new(0, [])
    assert_equal app, Qt::QApplication.current
    assert_equal QApplication.qtVersion, QApplication.qt_version
  ensure
    app&.dispose
  end

  def test_qwidget_and_qlabel_register_children
    skip 'native bridge is not available' unless Qt::Native.available?

    app = QApplication.new(0, [])
    window = QWidget.new
    label = QLabel.new(window)
    label.text = 'A'

    assert_equal 1, window.children.size
    assert_equal label, window.children.first
    assert_equal 'A', label.text
    assert_equal label.q_inspect, label.qt_inspect
    assert_equal label.q_inspect, label.to_h
    assert_equal 'QLabel', label.q_inspect[:qt_class]
    assert_equal 'A', label.q_inspect.dig(:properties, :text)

    layout = QVBoxLayout.new(window)
    window.set_layout(layout)
    window.set_geometry(50, 60, 320, 240)
    window.x
    window.y

    button = QPushButton.new(window)
    button.set_text('Click')
    layout.add_widget(button)
    layout.remove_widget(button)
    button.hide
    label.set_style_sheet('background-color: #fafafa;')
  ensure
    app&.dispose
  end
end

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

    with_qapplication do |app|
      assert_equal app, Qt::QApplication.current

      assert_equal QApplication.qtVersion, QApplication.qt_version
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

  def test_qwidget_and_qlabel_inspection_aliases
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window = QWidget.new
      label = QLabel.new(window)
      label.text = 'A'

      assert_equal label.q_inspect, label.qt_inspect
      assert_equal label.q_inspect, label.to_h
      assert_equal 'QLabel', label.q_inspect[:qt_class]
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

  private

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

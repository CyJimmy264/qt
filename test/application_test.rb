# frozen_string_literal: true

require_relative 'test_helper'

# rubocop:disable Metrics/ClassLength
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

  # rubocop:disable Metrics/MethodLength
  def test_qss_selector_matches_after_object_name_change
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window = QWidget.new
      button = QPushButton.new(window)
      button.set_text('Base')

      window.set_style_sheet('QPushButton#start_button { qproperty-text: "ID matched"; }')
      show_and_process_events(window)

      refute_equal 'ID matched', button.text

      button.object_name = 'start_button'
      window.set_style_sheet(window.style_sheet)
      show_and_process_events(window)

      assert_equal 'ID matched', button.text
    end
  end
  # rubocop:enable Metrics/MethodLength

  # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
  def test_qss_selector_matches_dynamic_property
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window = QWidget.new
      button = QPushButton.new(window)
      button.set_text('Base2')
      window.set_style_sheet('QPushButton[role="primary"] { qproperty-text: "Role matched"; }')
      show_and_process_events(window)

      refute_equal 'Role matched', button.text

      button.set_property('role', 'primary')

      assert_equal 'primary', button.property('role')

      window.set_style_sheet(window.style_sheet)
      show_and_process_events(window)

      assert_equal 'Role matched', button.text
    end
  end
  # rubocop:enable Metrics/AbcSize,Metrics/MethodLength

  # rubocop:disable Metrics/AbcSize,Metrics/MethodLength,Minitest/MultipleAssertions
  def test_dynamic_property_roundtrip_typed_values
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window = QWidget.new
      button = QPushButton.new(window)
      button.show
      window.show
      QApplication.process_events

      button.set_property('flag', true)
      button.set_property('count', 42)
      button.set_property('ratio', 1.5)
      button.set_property('list_payload', [1, 'x'])
      button.set_property('map_payload', { 'k' => 1, 's' => 'v' })

      assert button.property('flag')
      assert_equal 42, button.property('count')
      assert_in_delta 1.5, button.property('ratio'), 0.0001
      assert_equal [1, 'x'], button.property('list_payload')
      assert_equal({ 'k' => 1, 's' => 'v' }, button.property('map_payload'))
    end
  end
  # rubocop:enable Metrics/AbcSize,Metrics/MethodLength,Minitest/MultipleAssertions

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

  def show_and_process_events(widget)
    widget.show
    QApplication.process_events
  end
end
# rubocop:enable Metrics/ClassLength

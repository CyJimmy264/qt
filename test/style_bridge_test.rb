# frozen_string_literal: true

require_relative 'test_helper'

class QtStyleBridgeTest < Minitest::Test
  def test_qt_top_level_aliases_for_value_classes
    assert Object.const_defined?(:QIcon, false)
    assert Object.const_defined?(:QPixmap, false)
    assert Object.const_defined?(:QImage, false)
  end

  def test_qss_selector_matches_after_object_name_change
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window, button = build_button_fixture(text: 'Base')

      assert_id_style_applies_after_object_name(window, button)
    end
  end

  def test_qicon_and_window_icon_smoke
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do |app|
      window = QWidget.new
      icon = QIcon.new('/tmp/qt-ruby-missing-icon.png')

      assert_respond_to window, :set_window_icon
      window.set_window_icon(icon)

      refute_respond_to app, :set_window_icon
    end
  end

  def test_qss_selector_matches_dynamic_property
    skip 'native bridge is not available' unless Qt::Native.available?

    with_qapplication do
      window, button = build_button_fixture(text: 'Base2')

      assert_role_style_applies_after_property(window, button)
    end
  end

  def test_dynamic_property_roundtrip_boolean
    skip 'native bridge is not available' unless Qt::Native.available?

    assert_property_roundtrip('flag', true)
  end

  def test_dynamic_property_roundtrip_integer
    skip 'native bridge is not available' unless Qt::Native.available?

    assert_property_roundtrip('count', 42)
  end

  def test_dynamic_property_roundtrip_float
    skip 'native bridge is not available' unless Qt::Native.available?

    with_visible_button do |button|
      button.set_property('ratio', 1.5)

      assert_in_delta 1.5, button.property('ratio'), 0.0001
    end
  end

  def test_dynamic_property_roundtrip_array
    skip 'native bridge is not available' unless Qt::Native.available?

    assert_property_roundtrip('list_payload', [1, 'x'])
  end

  def test_dynamic_property_roundtrip_hash
    skip 'native bridge is not available' unless Qt::Native.available?

    assert_property_roundtrip('map_payload', { 'k' => 1, 's' => 'v' })
  end

  private

  def assert_property_roundtrip(key, value)
    with_visible_button do |button|
      button.set_property(key, value)

      assert_equal value, button.property(key)
    end
  end

  def assert_id_style_applies_after_object_name(window, button)
    window.set_style_sheet(id_match_qss)
    show_and_process_events(window)

    refute_equal 'ID matched', button.text

    button.object_name = 'start_button'
    window.set_style_sheet(window.style_sheet)
    show_and_process_events(window)

    assert_equal 'ID matched', button.text
  end

  def assert_role_style_applies_after_property(window, button)
    window.set_style_sheet(role_match_qss)
    show_and_process_events(window)

    refute_equal 'Role matched', button.text

    button.set_property('role', 'primary')

    assert_equal 'primary', button.property('role')

    window.set_style_sheet(window.style_sheet)
    show_and_process_events(window)

    assert_equal 'Role matched', button.text
  end

  def build_button_fixture(text:)
    window = QWidget.new
    button = QPushButton.new(window)
    button.set_text(text)
    [window, button]
  end

  def id_match_qss
    'QPushButton#start_button { qproperty-text: "ID matched"; }'
  end

  def role_match_qss
    'QPushButton[role="primary"] { qproperty-text: "Role matched"; }'
  end

  def with_visible_button
    with_qapplication do
      window = QWidget.new
      button = QPushButton.new(window)
      show_and_process_events(window)

      yield(button)
    end
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

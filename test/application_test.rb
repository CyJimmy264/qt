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
  ensure
    app&.dispose
  end

  def test_qwidget_and_qlabel_register_children
    skip 'native bridge is not available' unless Qt::Native.available?

    app = QApplication.new(0, [])
    window = QWidget.new
    label = QLabel.new(window)

    assert_equal 1, window.children.size
    assert_equal label, window.children.first
  ensure
    app&.dispose
  end
end

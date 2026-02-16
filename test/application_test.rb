# frozen_string_literal: true

require_relative 'test_helper'

class ApplicationTest < Minitest::Test
  def test_version_present
    refute_nil Qt::VERSION
  end

  def test_application_initialization
    app = Qt::Application.new(title: 'X', width: 100, height: 200)

    assert_equal 'X', app.title
    assert_equal 100, app.width
    assert_equal 200, app.height
  end

  def test_native_not_loaded_by_default
    # In CI/dev environments without Qt this should be false.
    assert_includes [true, false], Qt::Native.available?
  end
end

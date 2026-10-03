# frozen_string_literal: true

require_relative 'test_helper'

class QtGeneratorOutputTest < Minitest::Test
  GENERATED_CPP = File.expand_path('../build/generated/qt_ruby_bridge.cpp', __dir__)

  def test_generated_native_symbols_are_unique
    skip 'generated C++ bridge is not available' unless File.exist?(GENERATED_CPP)

    duplicates = generated_native_symbols.tally.select { |_name, count| count > 1 }.keys

    assert_empty duplicates.sort
  end

  def test_qapplication_related_clipboard_api_is_generated
    clipboard_methods = Qt::QClipboard.instance_methods

    assert_includes clipboard_methods, :text
    assert_includes clipboard_methods, :setText
    assert_includes clipboard_methods, :set_text
  end

  def test_qtextedit_cursor_value_api_is_generated
    assert_includes Qt::QTextEdit.instance_methods, :text_cursor
    assert_includes Qt::QTextEdit.instance_methods, :set_text_cursor
  end

  def test_qtextedit_cursor_value_can_be_read_changed_and_applied
    app = QApplication.new(0, [])
    editor = QTextEdit.new
    editor.set_plain_text("abc")
    cursor = editor.text_cursor
    cursor.set_position(2)
    editor.set_text_cursor(cursor)

    assert_equal 2, editor.text_cursor.position
  ensure
    app&.dispose
  end

  private

  def generated_native_symbols
    File.read(GENERATED_CPP).scan(/extern "C" [^{;\n]+?\b(qt_ruby_\w+)\s*\(/).flatten
  end
end

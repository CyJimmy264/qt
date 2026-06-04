# frozen_string_literal: true

require_relative 'test_helper'

class QtGeneratorOutputTest < Minitest::Test
  GENERATED_CPP = File.expand_path('../build/generated/qt_ruby_bridge.cpp', __dir__)

  def test_generated_native_symbols_are_unique
    skip 'generated C++ bridge is not available' unless File.exist?(GENERATED_CPP)

    duplicates = generated_native_symbols.tally.select { |_name, count| count > 1 }.keys

    assert_empty duplicates.sort
  end

  private

  def generated_native_symbols
    File.read(GENERATED_CPP).scan(/extern "C" [^{;\n]+?\b(qt_ruby_\w+)\s*\(/).flatten
  end
end

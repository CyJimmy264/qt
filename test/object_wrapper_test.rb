# frozen_string_literal: true

require_relative 'test_helper'

class QtObjectWrapperTest < Minitest::Test
  FakePointer = Struct.new(:address)

  def setup
    Qt::ObjectWrapper.reset_cache!
  end

  def teardown
    Qt::ObjectWrapper.reset_cache!
  end

  def test_missing_wrapper_warning_is_debug_gated
    pointer = FakePointer.new(0x1234)
    result = nil

    with_object_wrapper_resolver(nil) do
      with_env('QT_RUBY_OBJECT_WRAPPER_DEBUG', nil) do
        _stdout, stderr = capture_io do
          result = Qt::ObjectWrapper.wrap(pointer, 'QMissingWrapper')
        end

        assert_same pointer, result
        assert_empty stderr
      end
    end
  end

  def test_missing_wrapper_warning_identifies_expected_qt_class
    pointer = FakePointer.new(0x1234)
    result = nil

    with_object_wrapper_resolver(nil) do
      with_env('QT_RUBY_OBJECT_WRAPPER_DEBUG', '1') do
        _stdout, stderr = capture_io do
          result = Qt::ObjectWrapper.wrap(pointer, 'QMissingWrapper')
        end

        assert_same pointer, result
        assert_match(/\[qt-ruby-wrapper\]/, stderr)
        assert_match(/QMissingWrapper/, stderr)
        assert_match(/address=0x1234/, stderr)
      end
    end
  end

  private

  def with_object_wrapper_resolver(value)
    singleton = Qt::ObjectWrapper.singleton_class
    singleton.alias_method(:__orig_resolve_wrapper_class_for_test, :resolve_wrapper_class)
    singleton.remove_method(:resolve_wrapper_class)
    singleton.define_method(:resolve_wrapper_class) { |_pointer, _expected_qt_class| value }
    yield
  ensure
    singleton&.remove_method(:resolve_wrapper_class) if singleton&.method_defined?(:resolve_wrapper_class)
    if singleton&.method_defined?(:__orig_resolve_wrapper_class_for_test)
      singleton.alias_method(:resolve_wrapper_class, :__orig_resolve_wrapper_class_for_test)
      singleton.remove_method(:__orig_resolve_wrapper_class_for_test)
    end
  end

  def with_env(name, value)
    original = ENV.fetch(name, nil)
    value.nil? ? ENV.delete(name) : ENV[name] = value
    yield
  ensure
    original.nil? ? ENV.delete(name) : ENV[name] = original
  end
end

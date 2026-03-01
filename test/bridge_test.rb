# frozen_string_literal: true

require_relative 'test_helper'

class QtBridgeTest < Minitest::Test
  DummySpec = Struct.new(:extension_dir)

  def setup
    Qt::Bridge.instance_variable_set(:@library_candidates, nil)
  end

  def teardown
    Qt::Bridge.instance_variable_set(:@library_candidates, nil)
  end

  def test_library_candidates_include_gem_extension_dir
    ext = RbConfig::CONFIG['DLEXT']
    dummy_ext_dir = '/tmp/qt-ext-dir'
    expected = File.join(dummy_ext_dir, 'qt', "qt_ruby_bridge.#{ext}")
    klass = Gem::Specification.singleton_class
    old_verbose = $VERBOSE
    $VERBOSE = nil
    klass.send(:alias_method, :__orig_find_by_name_for_qt_bridge_test, :find_by_name)
    klass.send(:define_method, :find_by_name) { |_name| DummySpec.new(dummy_ext_dir) }

    candidates = Qt::Bridge.library_candidates
    assert_includes candidates, expected
  ensure
    $VERBOSE = old_verbose
    if klass.method_defined?(:__orig_find_by_name_for_qt_bridge_test)
      old_verbose = $VERBOSE
      $VERBOSE = nil
      klass.send(:alias_method, :find_by_name, :__orig_find_by_name_for_qt_bridge_test)
      klass.send(:remove_method, :__orig_find_by_name_for_qt_bridge_test)
      $VERBOSE = old_verbose
    end
  end
end

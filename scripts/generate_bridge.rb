#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tempfile'

ROOT = File.expand_path('..', __dir__)
BUILD_DIR = File.join(ROOT, 'build')
GENERATED_DIR = File.join(BUILD_DIR, 'generated')
CPP_PATH = File.join(GENERATED_DIR, 'qt_ruby_bridge.cpp')
API_PATH = File.join(GENERATED_DIR, 'bridge_api.rb')
RUBY_WIDGETS_PATH = File.join(GENERATED_DIR, 'widgets.rb')

# Universal generation policy: class set is discovered from AST per scope.
GENERATOR_SCOPE = (ENV['QT_RUBY_SCOPE'] || 'widgets').freeze
SUPPORTED_SCOPES = %w[widgets].freeze

QAPPLICATION_SPEC = {
  qt_class: 'QApplication',
  ruby_class: 'QApplication',
  include: 'QApplication',
  prefix: 'qapplication',
  constructor: { parent: false, mode: :qapplication },
  class_methods: [
    { ruby_name: 'qtVersion', native: 'qt_version', args: [] },
    { ruby_name: 'processEvents', native: 'qapplication_process_events', args: [] },
    { ruby_name: 'topLevelWidgetsCount', native: 'qapplication_top_level_widgets_count', args: [] }
  ],
  methods: [
    { qt_name: 'exec', ruby_name: 'exec', ffi_return: :int, args: [] }
  ],
  validate: { constructors: ['QApplication'], methods: ['exec'] }
}.freeze
RUBY_RESERVED_WORDS = %w[
  BEGIN END alias and begin break case class def defined? do else elsif end ensure false
  for if in module next nil not or redo rescue retry return self super then true undef unless
  until when while yield __ENCODING__ __FILE__ __LINE__
].to_set.freeze
RUNTIME_METHOD_RENAMES = { 'handle' => 'handle_at' }.freeze
RUNTIME_RESERVED_RUBY_METHODS = Set['handle'].freeze

require_relative 'generate_bridge/core_utils'
require_relative 'generate_bridge/ffi_api'
require_relative 'generate_bridge/auto_method_spec_resolver'
require_relative 'generate_bridge/cpp_method_return_emitter'
require_relative 'generate_bridge/ast_introspection'
require_relative 'generate_bridge/auto_methods'
require_relative 'generate_bridge/spec_discovery'

def next_trace_base(fetch_bases, cur, visited)
  bases = Array(fetch_bases.call(cur))
  return nil if bases.empty?

  base = bases.first
  return nil if base.nil? || base.empty? || visited[base]

  base
end

def trace_generated_super_chain(fetch_bases, known_qt, qt_class, super_qt_by_qt)
  return if qt_class == 'QApplication'

  visited = {}
  prev = cur = qt_class
  loop do
    break unless (base = next_trace_base(fetch_bases, cur, visited))

    visited[base] = true
    super_qt_by_qt[prev] ||= base
    break if known_qt.include?(base)

    prev = cur = base
  end
end

def build_generated_inheritance(ast, specs)
  known_qt = specs.map { |s| s[:qt_class] }
  base_cache = {}
  fetch_bases = lambda do |qt_class|
    base_cache[qt_class] ||= collect_class_bases(ast, qt_class)
  end

  super_qt_by_qt = {}
  known_qt.each { |qt_class| trace_generated_super_chain(fetch_bases, known_qt, qt_class, super_qt_by_qt) }

  wrapper_qt_classes = (super_qt_by_qt.keys + super_qt_by_qt.values - known_qt).uniq
  [super_qt_by_qt, wrapper_qt_classes]
end

def widget_based_qt_class?(qt_class, super_qt_by_qt)
  cur = qt_class
  while (sup = super_qt_by_qt[cur])
    return true if sup == 'QWidget'

    cur = sup
  end
  false
end

def inherited_methods_for_spec(spec, specs_by_qt, super_qt_by_qt)
  inherited = []
  cur = spec[:qt_class]

  while (sup = super_qt_by_qt[cur])
    parent_spec = specs_by_qt[sup]
    inherited.concat(parent_spec[:methods]) if parent_spec
    cur = sup
  end

  inherited
end

def generate_ruby_wrapper_class(lines, qt_class, super_ruby)
  class_decl = ruby_wrapper_class_decl(qt_class, super_ruby)
  lines << class_decl
  lines << "    QT_CLASS = '#{qt_class}'.freeze"
  lines << '    QT_API_QT_METHODS = [].freeze'
  lines << '    QT_API_RUBY_METHODS = [].freeze'
  lines << '    QT_API_PROPERTIES = [].freeze'
  lines << '  end'
  lines << ''
end

def ruby_wrapper_class_decl(qt_class, super_ruby)
  return "  class #{qt_class}" unless super_ruby

  "  class #{qt_class} < #{super_ruby}"
end

def find_getter_decl(ast, qt_class, property)
  collect_method_decls_with_bases(ast, qt_class, property).find do |decl|
    next false unless decl['__effective_access'] == 'public'

    parsed = parse_method_signature(decl)
    next false unless parsed && parsed[:params].empty?

    map_cpp_return_type(parsed[:return_type])
  end
end

def build_property_getter_method(getter_decl, property)
  parsed_getter = parse_method_signature(getter_decl)
  ret_info = map_cpp_return_type(parsed_getter[:return_type])
  return nil unless ret_info

  getter = {
    qt_name: property,
    ruby_name: property,
    ffi_return: ret_info[:ffi_return],
    args: [],
    property: property
  }
  getter[:return_cast] = ret_info[:return_cast] if ret_info[:return_cast]
  getter
end

def enrich_spec_with_property_getter!(methods, ast, spec, method)
  property = property_name_from_setter(method[:qt_name])
  return unless property_candidate?(method, ast, spec, property)

  return if attach_existing_property_getter?(methods, property)

  getter_decl = find_getter_decl(ast, spec[:qt_class], property)
  return unless getter_decl

  getter = build_property_getter_method(getter_decl, property)
  methods << getter if getter
end

def attach_existing_property_getter?(methods, property)
  existing_getter = methods.find { |method| method[:qt_name] == property && method[:args].empty? }
  return false unless existing_getter

  existing_getter[:property] ||= property
  true
end

def property_candidate?(method, ast, spec, property)
  return false unless method[:args].length == 1
  return false unless property
  return false unless class_has_method?(ast, spec[:qt_class], property)

  true
end

def enrich_specs_with_properties(specs, ast)
  specs.map do |spec|
    methods = spec[:methods].dup

    spec[:methods].each do |method|
      enrich_spec_with_property_getter!(methods, ast, spec, method)
    end

    spec.merge(methods: methods)
  end
end

def validate_spec_api(errors, spec, api)
  req = spec[:validate]
  req[:constructors].each do |ctor|
    errors << "#{spec[:qt_class]}: constructor #{ctor} not found" unless api[:constructors].include?(ctor)
  end
  req[:methods].each do |method|
    errors << "#{spec[:qt_class]}: method #{method} not found" unless api[:methods].include?(method)
  end
end

def validate_qt_api!(ast, specs)
  errors = []

  specs.each do |spec|
    api = collect_class_api(ast, spec[:qt_class])
    validate_spec_api(errors, spec, api)
  end

  return if errors.empty?

  raise "Qt AST validation failed:\n- #{errors.join("\n- ")}"
end

def arg_expr(arg)
  case arg[:cast]
  when :qstring then "as_qstring(#{arg[:name]})"
  when :alignment then "static_cast<Qt::Alignment>(#{arg[:name]})"
  when String then "static_cast<#{arg[:cast]}>(#{arg[:name]})"
  else
    arg[:name]
  end
end

def emit_cpp_qapplication_constructor(lines, name)
  lines << "extern \"C\" void* #{name}() {"
  lines << '  static int argc = 1;'
  lines << '  static char arg0[] = "qt-ruby";'
  lines << '  static char* argv[] = {arg0, nullptr};'
  lines << '  return new QApplication(argc, argv);'
  lines << '}'
end

def emit_cpp_default_constructor(lines, name, qt_class)
  lines << "extern \"C\" void* #{name}() {"
  lines << "  return new #{qt_class}();"
  lines << '}'
end

def emit_cpp_parent_constructor(lines, name, spec)
  parent_type = spec[:constructor][:parent_type]
  parent_class = parent_type.delete('*')
  lines << "extern \"C\" void* #{name}(void* parent_handle) {"
  lines << "  #{parent_class}* parent = static_cast<#{parent_type}>(parent_handle);"
  lines << "  return new #{spec[:qt_class]}(parent);"
  lines << '}'
end

def generate_cpp_constructor(lines, spec)
  name = ctor_function_name(spec)

  if spec[:constructor][:mode] == :qapplication
    emit_cpp_qapplication_constructor(lines, name)
    return
  end

  unless spec[:constructor][:parent]
    emit_cpp_default_constructor(lines, name, spec[:qt_class])
    return
  end

  emit_cpp_parent_constructor(lines, name, spec)
end

def generate_cpp_delete(lines)
  lines << 'extern "C" void qt_ruby_qapplication_delete(void* app_handle) {'
  lines << '  if (!app_handle) {'
  lines << '    return;'
  lines << '  }'
  lines << ''
  lines << '  auto* app = static_cast<QApplication*>(app_handle);'
  lines << '  delete app;'
  lines << '}'
end

def cpp_method_signature(method)
  ['void* handle'] + method[:args].map { |arg| "#{ffi_to_cpp_type(arg[:ffi])} #{arg[:name]}" }
end

def cpp_null_handle_return(method)
  case method[:ffi_return]
  when :int
    '    return -1;'
  when :pointer, :string
    '    return nullptr;'
  else
    '    return;'
  end
end

def emit_cpp_method_return(lines, method, invocation)
  CppMethodReturnEmitter.new(lines: lines, method: method, invocation: invocation).emit
end

def cpp_method_invocation(method)
  call_args = method[:args].map { |arg| arg_expr(arg) }.join(', ')
  "self_obj->#{method[:qt_name]}(#{call_args})"
end

def generate_cpp_method(lines, spec, method)
  fn = method_function_name(spec, method)
  ret = ffi_return_to_cpp(method[:ffi_return])
  lines << "extern \"C\" #{ret} #{fn}(#{cpp_method_signature(method).join(', ')}) {"
  lines << '  if (!handle) {'
  lines << cpp_null_handle_return(method)
  lines << '  }'
  lines << ''
  lines << "  auto* self_obj = static_cast<#{spec[:qt_class]}*>(handle);"
  emit_cpp_method_return(lines, method, cpp_method_invocation(method))
  lines << '}'
end

def generate_cpp_bridge(specs)
  lines = required_includes(GENERATOR_SCOPE).map { |inc| "#include <#{inc}>" }
  append_block(lines, cpp_bridge_prelude)

  specs.each { |spec| append_cpp_spec_methods(lines, spec) }

  generate_cpp_delete(lines)
  "#{lines.join("\n")}\n"
end

def append_cpp_spec_methods(lines, spec)
  generate_cpp_constructor(lines, spec)
  lines << ''
  spec[:methods].each do |method|
    generate_cpp_method(lines, spec, method)
    lines << ''
  end
end

def append_block(lines, block)
  lines.concat(block.strip.split("\n"))
  lines << ''
end

def cpp_bridge_prelude
  <<~CPP
    #include <QByteArray>
    #include <QString>
    #include "qt_ruby_runtime.hpp"

    namespace {

    QString as_qstring(const char* value, const char* fallback = "") {
      if (!value) {
        return QString::fromUtf8(fallback);
      }

      return QString::fromUtf8(value);
    }
    }  // namespace

    extern "C" const char* qt_ruby_qt_version() {
      return qVersion();
    }

    extern "C" void qt_ruby_qapplication_process_events() {
      QtRubyRuntime::qapplication_process_events();
    }

    extern "C" int qt_ruby_qapplication_top_level_widgets_count() {
      return QtRubyRuntime::qapplication_top_level_widgets_count();
    }

    extern "C" void qt_ruby_set_event_callback(void* callback_ptr) {
      QtRubyRuntime::set_event_callback(callback_ptr);
    }

    extern "C" void qt_ruby_watch_qobject_event(void* object_handle, int event_type) {
      QtRubyRuntime::watch_qobject_event(object_handle, event_type);
    }

    extern "C" void qt_ruby_unwatch_qobject_event(void* object_handle, int event_type) {
      QtRubyRuntime::unwatch_qobject_event(object_handle, event_type);
    }

    extern "C" void qt_ruby_set_signal_callback(void* callback_ptr) {
      QtRubyRuntime::set_signal_callback(callback_ptr);
    }

    extern "C" int qt_ruby_qobject_connect_signal(void* object_handle, const char* signal_name) {
      return QtRubyRuntime::qobject_connect_signal(object_handle, signal_name);
    }

    extern "C" int qt_ruby_qobject_disconnect_signal(void* object_handle, const char* signal_name) {
      return QtRubyRuntime::qobject_disconnect_signal(object_handle, signal_name);
    }
  CPP
end

def generate_bridge_api(specs)
  lines = bridge_api_prelude_lines
  append_bridge_api_function_lines(lines, specs)
  lines.concat(bridge_api_closure_lines)
  "#{lines.join("\n")}\n"
end

def bridge_api_prelude_lines
  [
    '# frozen_string_literal: true',
    '',
    'module Qt',
    '  module BridgeAPI',
    '    FUNCTIONS = ['
  ]
end

def append_bridge_api_function_lines(lines, specs)
  all_ffi_functions(specs).each do |fn|
    args = fn[:args].map { |arg| ":#{arg}" }.join(', ')
    lines << "      { name: :#{fn[:name]}, args: [#{args}], return: :#{fn[:ffi_return]} },"
  end
end

def bridge_api_closure_lines
  [
    '    ].freeze',
    '  end',
    'end'
  ]
end

def ruby_api_metadata(methods)
  qt_method_names = methods.map { |method| method[:qt_name] }.uniq
  ruby_method_names = methods.flat_map do |method|
    ruby_name = ruby_safe_method_name(method[:ruby_name])
    snake = to_snake(ruby_name)
    snake == ruby_name ? [ruby_name] : [ruby_name, snake]
  end.uniq
  properties = methods.filter_map { |method| method[:property] }.uniq

  {
    qt_method_names: qt_method_names,
    ruby_method_names: ruby_method_names,
    properties: properties
  }
end

def append_ruby_class_api_constants(lines, qt_class:, metadata:, indent:)
  lines << "#{indent}QT_CLASS = '#{qt_class}'.freeze"
  lines << "#{indent}QT_API_QT_METHODS = #{metadata[:qt_method_names].inspect}.freeze"
  lines << "#{indent}QT_API_RUBY_METHODS = #{metadata[:ruby_method_names].map(&:to_sym).inspect}.freeze"
  lines << "#{indent}QT_API_PROPERTIES = #{metadata[:properties].map(&:to_sym).inspect}.freeze"
end

def ruby_method_arguments(method, arg_map, required_arg_count)
  method[:args].each_with_index.map do |arg, idx|
    safe = arg_map[arg[:name]]
    idx < required_arg_count ? safe : "#{safe} = nil"
  end.join(', ')
end

def optional_arg_replacement(arg, safe)
  case arg[:ffi]
  when :int then "(#{safe}.nil? ? 0 : #{safe})"
  when :pointer then safe
  else "(#{safe}.nil? ? '' : #{safe})"
  end
end

def rewrite_native_call_args(native_call, method, arg_map, required_arg_count)
  rewritten_native_call = native_call
  method[:args].each_with_index do |arg, idx|
    safe = arg_map[arg[:name]]
    replacement = idx >= required_arg_count ? optional_arg_replacement(arg, safe) : safe
    rewritten_native_call = rewritten_native_call.gsub(/\b#{Regexp.escape(arg[:name])}\b/, replacement)
  end
  rewritten_native_call
end

def append_ruby_native_call_method(lines, method:, native_call:, indent:)
  ruby_name = ruby_safe_method_name(method[:ruby_name])
  snake_alias = to_snake(ruby_name)
  arg_map = ruby_arg_name_map(method[:args])
  required_arg_count = method.fetch(:required_arg_count, method[:args].length)
  ruby_args = ruby_method_arguments(method, arg_map, required_arg_count)
  rewritten_native_call = rewrite_native_call_args(native_call, method, arg_map, required_arg_count)

  lines << "#{indent}def #{ruby_name}(#{ruby_args})"
  lines << "#{indent}  #{rewritten_native_call}"
  lines << "#{indent}end"
  lines << "#{indent}alias_method :#{snake_alias}, :#{ruby_name}" if snake_alias != ruby_name
end

def append_ruby_property_writer(lines, method:, indent:)
  return unless method[:property]

  snake_property = to_snake(method[:property])
  lines << "#{indent}def #{method[:property]}=(value)"
  lines << "#{indent}  set#{method[:property][0].upcase}#{method[:property][1..]}(value)"
  lines << "#{indent}end"
  lines << "#{indent}alias_method :#{snake_property}=, :#{method[:property]}=" if snake_property != method[:property]
end

def append_widget_initializer(lines, spec:, widget_root:, indent:)
  if spec[:constructor][:parent]
    append_parent_widget_initializer(lines, spec, widget_root, indent)
  else
    append_default_widget_initializer(lines, spec, indent)
  end

  lines << "#{indent}  yield self if block_given?"
  lines << "#{indent}end"
end

def append_parent_widget_initializer(lines, spec, widget_root, indent)
  lines << "#{indent}def initialize(parent = nil)"
  lines << "#{indent}  @handle = Native.#{spec[:prefix]}_new(parent&.handle)"
  lines << "#{indent}  init_children_tracking!" if widget_root
  append_parent_registration_logic(lines, spec, indent)
end

def append_default_widget_initializer(lines, spec, indent)
  lines << "#{indent}def initialize(_argc = 0, _argv = [])"
  lines << "#{indent}  @handle = Native.#{spec[:prefix]}_new"
end

def append_parent_registration_logic(lines, spec, indent)
  if spec[:ruby_class] == 'QWidget'
    lines << "#{indent}  if parent"
    lines << "#{indent}    parent.add_child(self)"
    lines << "#{indent}  else"
    lines << "#{indent}    app = QApplication.current"
    lines << "#{indent}    app&.register_window(self)"
    lines << "#{indent}  end"
  elsif spec[:constructor][:register_in_parent]
    lines << "#{indent}  parent.add_child(self) if parent&.respond_to?(:add_child)"
  end
end

def append_ruby_qapplication_prelude(lines, spec, metadata)
  lines << '  class QApplication'
  append_ruby_class_api_constants(lines, qt_class: spec[:qt_class], metadata: metadata, indent: '    ')
  lines << ''
  lines << '    attr_reader :handle'
  lines << '    include Inspectable'
  lines << '    include ApplicationLifecycle'
  lines << ''
end

def append_ruby_qapplication_singleton_accessors(lines)
  lines << '    class << self'
  lines << '      def current'
  lines << '        Thread.current[:qt_ruby_current_app]'
  lines << '      end'
  lines << ''
  lines << '      def current=(app)'
  lines << '        Thread.current[:qt_ruby_current_app] = app'
  lines << '      end'
end

def generate_ruby_qapplication(lines, spec)
  metadata = ruby_api_metadata(spec[:methods])

  append_ruby_qapplication_prelude(lines, spec, metadata)
  append_ruby_qapplication_singleton_accessors(lines)

  Array(spec[:class_methods]).each { |method| append_ruby_qapplication_class_method(lines, method) }

  lines << '    end'
  lines << ''
  lines << '  end'
  lines << ''
end

def qapplication_method_arguments(method)
  arg_hashes = Array(method[:args]).map { |name| { name: name } }
  arg_map = ruby_arg_name_map(arg_hashes)
  rendered_args = arg_hashes.map { |arg| arg_map[arg[:name]] }.join(', ')
  [arg_hashes, arg_map, rendered_args]
end

def qapplication_method_call_suffix(arg_hashes, arg_map)
  native_args = arg_hashes.map { |arg| arg_map[arg[:name]] }.join(', ')
  native_args.empty? ? '' : "(#{native_args})"
end

def append_ruby_qapplication_class_method(lines, method)
  ruby_name = ruby_safe_method_name(method[:ruby_name])
  snake_alias = to_snake(ruby_name)
  method_arg_hashes, arg_map, args = qapplication_method_arguments(method)
  call_suffix = qapplication_method_call_suffix(method_arg_hashes, arg_map)

  lines << ''
  lines << "      def #{ruby_name}(#{args})"
  lines << (method[:native] ? "        Native.#{method[:native]}#{call_suffix}" : '        nil')
  lines << '      end'
  lines << "      alias_method :#{snake_alias}, :#{ruby_name}" if snake_alias != ruby_name
end

def generate_ruby_widget_class_header(lines, spec, metadata:, super_ruby:, widget_root:)
  class_decl = super_ruby ? "  class #{spec[:ruby_class]} < #{super_ruby}" : "  class #{spec[:ruby_class]}"
  lines << class_decl
  append_ruby_class_api_constants(lines, qt_class: spec[:qt_class], metadata: metadata, indent: '    ')
  lines << ''
  lines << '    attr_reader :handle'
  lines << '    attr_reader :children' if widget_root
  lines << '    include Inspectable'
  lines << '    include ChildrenTracking' if widget_root
  lines << '    include EventRuntime::WidgetMethods' if widget_root
  lines << ''
end

def append_ruby_widget_methods(lines, spec)
  spec[:methods].each do |method|
    call_args = ['@handle'] + method[:args].map { |arg| arg[:name] }
    native_call = "Native.#{spec[:prefix]}_#{to_snake(method[:qt_name])}(#{call_args.join(', ')})"
    append_ruby_native_call_method(lines, method: method, native_call: native_call, indent: '    ')
    append_ruby_property_writer(lines, method: method, indent: '    ')
    lines << ''
  end
end

def generate_ruby_widget_class(lines, spec, specs_by_qt, super_qt_by_qt, qt_to_ruby)
  metadata = ruby_api_metadata_for_spec(spec, specs_by_qt, super_qt_by_qt)
  super_ruby = ruby_super_class_for_spec(spec, super_qt_by_qt, qt_to_ruby)
  widget_root = spec[:ruby_class] == 'QWidget'

  generate_ruby_widget_class_header(lines, spec, metadata: metadata, super_ruby: super_ruby, widget_root: widget_root)
  append_widget_initializer(lines, spec: spec, widget_root: widget_root, indent: '    ')
  lines << ''
  append_ruby_widget_methods(lines, spec)

  lines << '  end'
  lines << ''
end

def ruby_api_metadata_for_spec(spec, specs_by_qt, super_qt_by_qt)
  inherited_methods = inherited_methods_for_spec(spec, specs_by_qt, super_qt_by_qt)
  all_methods = (inherited_methods + spec[:methods]).uniq { |method| method[:qt_name] }
  ruby_api_metadata(all_methods)
end

def ruby_super_class_for_spec(spec, super_qt_by_qt, qt_to_ruby)
  super_qt = super_qt_by_qt[spec[:qt_class]]
  super_qt ? qt_to_ruby[super_qt] : nil
end

def build_qt_to_ruby_map(specs, wrapper_qt_classes)
  qt_to_ruby = specs.each_with_object({}) { |s, map| map[s[:qt_class]] = s[:ruby_class] }
  wrapper_qt_classes.each { |qt_class| qt_to_ruby[qt_class] = qt_class }
  qt_to_ruby
end

def qts_to_emit(specs, wrapper_qt_classes)
  (wrapper_qt_classes + specs.map { |s| s[:qt_class] }.reject { |q| q == 'QApplication' }).uniq
end

def emit_qt_classes(lines, qts_to_emit, specs_by_qt, super_qt_by_qt, qt_to_ruby)
  emitted = {}
  emit_qt = lambda do |qt_class|
    return if emitted[qt_class]

    super_qt = super_qt_by_qt[qt_class]
    emit_qt.call(super_qt) if super_qt && qts_to_emit.include?(super_qt)
    emit_qt_class_definition(lines, qt_class, specs_by_qt, super_qt_by_qt, qt_to_ruby)
    emitted[qt_class] = true
  end
  qts_to_emit.sort.each { |qt_class| emit_qt.call(qt_class) }
end

def emit_qt_class_definition(lines, qt_class, specs_by_qt, super_qt_by_qt, qt_to_ruby)
  spec = specs_by_qt[qt_class]
  if spec
    generate_ruby_widget_class(lines, spec, specs_by_qt, super_qt_by_qt, qt_to_ruby)
  else
    super_qt = super_qt_by_qt[qt_class]
    generate_ruby_wrapper_class(lines, qt_class, super_qt ? qt_to_ruby[super_qt] : nil)
  end
end

def ruby_widgets_prelude_lines
  ['# frozen_string_literal: true', '', 'module Qt']
end

def append_ruby_widgets_classes(lines, specs, super_qt_by_qt, wrapper_qt_classes)
  qapplication_spec = specs.find { |spec| spec[:ruby_class] == 'QApplication' }
  generate_ruby_qapplication(lines, qapplication_spec)

  specs_by_qt = specs.each_with_object({}) { |spec, map| map[spec[:qt_class]] = spec }
  qt_to_ruby = build_qt_to_ruby_map(specs, wrapper_qt_classes)
  emitted_qts = qts_to_emit(specs, wrapper_qt_classes)
  emit_qt_classes(lines, emitted_qts, specs_by_qt, super_qt_by_qt, qt_to_ruby)
end

def generate_ruby_widgets(specs, super_qt_by_qt, wrapper_qt_classes)
  lines = ruby_widgets_prelude_lines
  append_ruby_widgets_classes(lines, specs, super_qt_by_qt, wrapper_qt_classes)

  lines << 'end'
  "#{lines.join("\n")}\n"
end

total_start = monotonic_now
ast = timed('ast_dump_total') { ast_dump }
base_specs = timed('build_base_specs') { build_base_specs(ast) }
timed('validate_qt_api') { validate_qt_api!(ast, base_specs) }
expanded_specs = timed('expand_auto_methods') { expand_auto_methods(base_specs, ast) }
effective_specs = timed('enrich_specs_with_properties') { enrich_specs_with_properties(expanded_specs, ast) }
super_qt_by_qt, wrapper_qt_classes = timed('build_generated_inheritance') do
  build_generated_inheritance(ast, effective_specs)
end

timed('write_cpp_bridge') do
  FileUtils.mkdir_p(File.dirname(CPP_PATH))
  File.write(CPP_PATH, generate_cpp_bridge(effective_specs))
end
timed('write_bridge_api') do
  FileUtils.mkdir_p(File.dirname(API_PATH))
  File.write(API_PATH, generate_bridge_api(effective_specs))
end
timed('write_ruby_widgets') do
  FileUtils.mkdir_p(File.dirname(RUBY_WIDGETS_PATH))
  File.write(RUBY_WIDGETS_PATH, generate_ruby_widgets(effective_specs, super_qt_by_qt, wrapper_qt_classes))
end
debug_log("total=#{format('%.3fs', monotonic_now - total_start)}")

puts "Generated #{CPP_PATH}"
puts "Generated #{API_PATH}"
puts "Generated #{RUBY_WIDGETS_PATH}"

#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'set'
require 'tempfile'
require_relative 'specs/qt_widgets'

ROOT = File.expand_path('..', __dir__)
BUILD_DIR = File.join(ROOT, 'build')
GENERATED_DIR = File.join(BUILD_DIR, 'generated')
CPP_PATH = File.join(GENERATED_DIR, 'qt_ruby_bridge.cpp')
API_PATH = File.join(GENERATED_DIR, 'bridge_api.rb')
RUBY_WIDGETS_PATH = File.join(GENERATED_DIR, 'widgets.rb')

CLASS_SPECS = QtRubyGenerator::Specs::CLASS_SPECS

def required_includes
  CLASS_SPECS.map { |spec| spec.fetch(:include) }.uniq
end

def ffi_to_cpp_type(ffi)
  case ffi
  when :pointer then 'void*'
  when :string then 'const char*'
  when :int then 'int'
  else
    raise "Unsupported ffi type: #{ffi.inspect}"
  end
end

def ffi_return_to_cpp(ffi)
  case ffi
  when :void then 'void'
  when :pointer then 'void*'
  when :int then 'int'
  when :string then 'const char*'
  else
    raise "Unsupported ffi return: #{ffi.inspect}"
  end
end

def to_snake(name)
  name.gsub(/([a-z\d])([A-Z])/, '\\1_\\2').downcase
end

def lower_camel(name)
  return name if name.empty?

  name[0].downcase + name[1..]
end

def property_name_from_setter(qt_name)
  return nil unless qt_name.start_with?('set')
  return nil if qt_name.length <= 3

  lower_camel(qt_name.delete_prefix('set'))
end

def ctor_function_name(spec)
  "qt_ruby_#{spec[:prefix]}_new"
end

def method_function_name(spec, method)
  "qt_ruby_#{spec[:prefix]}_#{to_snake(method[:qt_name])}"
end

def free_functions
  [
    { name: 'qt_ruby_qt_version', ffi_return: :string, args: [] },
    { name: 'qt_ruby_qapplication_process_events', ffi_return: :void, args: [] },
    { name: 'qt_ruby_qapplication_top_level_widgets_count', ffi_return: :int, args: [] },
    { name: 'qt_ruby_set_event_callback', ffi_return: :void, args: [:pointer] },
    { name: 'qt_ruby_watch_qobject_event', ffi_return: :void, args: [:pointer, :int] },
    { name: 'qt_ruby_unwatch_qobject_event', ffi_return: :void, args: [:pointer, :int] },
    { name: 'qt_ruby_set_signal_callback', ffi_return: :void, args: [:pointer] },
    { name: 'qt_ruby_qobject_connect_signal', ffi_return: :int, args: [:pointer, :string] },
    { name: 'qt_ruby_qobject_disconnect_signal', ffi_return: :int, args: [:pointer, :string] }
  ]
end

def all_ffi_functions(specs)
  fns = free_functions.dup

  specs.each do |spec|
    ctor_args = spec[:constructor][:parent] ? [:pointer] : []
    fns << { name: ctor_function_name(spec), ffi_return: :pointer, args: ctor_args }

    if spec[:prefix] == 'qapplication'
      fns << { name: 'qt_ruby_qapplication_delete', ffi_return: :void, args: [:pointer] }
    end

    spec[:methods].each do |method|
      args = [:pointer] + method[:args].map { |arg| arg[:ffi] }
      fns << { name: method_function_name(spec, method), ffi_return: method[:ffi_return], args: args }
    end
  end

  fns
end

def pkg_config_cflags
  cflags = `pkg-config --cflags Qt6Widgets 2>/dev/null`.strip
  raise 'pkg-config Qt6Widgets is required' if cflags.empty?

  cflags
end

def ast_dump
  cflags = pkg_config_cflags

  Tempfile.create(['qt_ruby_probe', '.cpp']) do |file|
    required_includes.each { |inc| file.write("#include <#{inc}>\n") }
    file.flush

    cmd = "clang++ -std=c++17 -x c++ -Xclang -ast-dump=json -fsyntax-only #{cflags} #{file.path}"
    out = `#{cmd}`
    raise "clang AST dump failed: #{cmd}" unless $?.success?

    JSON.parse(out)
  end
end

def walk_ast(node, &block)
  return unless node.is_a?(Hash)

  yield node
  Array(node['inner']).each { |child| walk_ast(child, &block) }
end

def collect_class_api(ast, class_name)
  methods = []
  ctors = []

  walk_ast(ast) do |node|
    next unless node['kind'] == 'CXXRecordDecl'
    next unless node['name'] == class_name

    Array(node['inner']).each do |inner|
      case inner['kind']
      when 'CXXMethodDecl' then methods << inner['name'] if inner['name']
      when 'CXXConstructorDecl' then ctors << inner['name'] if inner['name']
      end
    end
  end

  { methods: methods.uniq, constructors: ctors.uniq }
end

def ast_class_index(ast)
  @ast_class_index_cache ||= {}
  cached = @ast_class_index_cache[ast.object_id]
  return cached if cached

  methods_by_class = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = [] } }
  bases_by_class = Hash.new { |h, k| h[k] = [] }

  walk_ast(ast) do |node|
    next unless node['kind'] == 'CXXRecordDecl'

    class_name = node['name']
    next if class_name.nil? || class_name.empty?

    Array(node['bases']).each do |base|
      type_info = base['type'] || {}
      raw = type_info['desugaredQualType'] || type_info['qualType']
      parsed_base = normalize_cpp_type_name(raw)
      bases_by_class[class_name] << parsed_base if parsed_base && !parsed_base.empty?
    end

    Array(node['inner']).each do |inner|
      next unless inner['kind'] == 'CXXMethodDecl'
      next unless inner['name']

      methods_by_class[class_name][inner['name']] << inner
    end
  end

  bases_by_class.each_value(&:uniq!)

  @ast_class_index_cache[ast.object_id] = {
    methods_by_class: methods_by_class,
    bases_by_class: bases_by_class
  }
end

def collect_method_decls(ast, class_name, method_name)
  index = ast_class_index(ast)
  index[:methods_by_class].dig(class_name, method_name) || []
end

def collect_method_decls_with_bases(ast, class_name, method_name, visited = {})
  return [] if class_name.nil? || class_name.empty? || visited[class_name]

  visited[class_name] = true
  all = collect_method_decls(ast, class_name, method_name)

  bases = collect_class_bases(ast, class_name)
  bases.each do |base|
    all.concat(collect_method_decls_with_bases(ast, base, method_name, visited))
  end

  all
end

def map_cpp_arg_type(type_name)
  type = type_name.to_s.strip
  type = type.sub(/\Aconst\s+/, '').sub(/\s*&\z/, '').strip

  if type == 'QString'
    return { ffi: :string, cast: :qstring }
  end

  if type.end_with?('*')
    base = type.sub(/\s*\*\z/, '').strip
    return { ffi: :pointer, cast: "#{base}*" }
  end

  case type
  when 'int'
    { ffi: :int }
  when 'bool'
    { ffi: :int, cast: 'bool' }
  else
    return { ffi: :int, cast: type } if type.include?('::')
    return { ffi: :int, cast: type } if type.match?(/\A[A-Z]\w*\z/)

    nil
  end
end

def normalized_cpp_type_name(type_name)
  type = type_name.to_s.strip
  type = type.sub(/\Aconst\s+/, '').sub(/\s*&\z/, '').strip
  type = type.sub(/\s*\*\z/, '*') if type.end_with?('*')
  type
end

def map_cpp_return_type(type_name)
  type = type_name.to_s.strip
  type = type.sub(/\Aconst\s+/, '').sub(/\s*&\z/, '').strip

  return { ffi_return: :void } if type == 'void'
  return { ffi_return: :int } if type == 'int'
  return { ffi_return: :int } if type == 'bool'
  return { ffi_return: :string, return_cast: :qstring_to_utf8 } if type == 'QString'
  return { ffi_return: :pointer } if type.end_with?('*')

  nil
end

def parse_method_signature(method_decl)
  qual = method_decl.dig('type', 'qualType').to_s
  md = qual.match(/\A(.+?)\s*\((.*)\)/)
  return nil unless md

  ret = md[1].strip
  params = Array(method_decl['inner']).select { |x| x['kind'] == 'ParmVarDecl' }
  {
    return_type: ret,
    params: params.each_with_index.map do |param, idx|
      { name: (param['name'] || "arg#{idx + 1}"), type: param.dig('type', 'qualType').to_s }
    end
  }
end

def build_auto_method_from_decl(method_decl, entry)
  parsed = parse_method_signature(method_decl)
  return nil unless parsed

  ret_info = map_cpp_return_type(parsed[:return_type])
  return nil unless ret_info

  arg_cast_overrides = Array(entry[:arg_casts])
  args = parsed[:params].each_with_index.map do |param, idx|
    arg_info = map_cpp_arg_type(param[:type])
    return nil unless arg_info

    arg_hash = { name: param[:name], ffi: arg_info[:ffi] }
    cast = arg_cast_overrides[idx] || arg_info[:cast]
    arg_hash[:cast] = cast if cast
    arg_hash
  end

  method = {
    qt_name: entry[:qt_name],
    ruby_name: entry[:ruby_name] || entry[:qt_name],
    ffi_return: ret_info[:ffi_return],
    args: args
  }
  method[:return_cast] = ret_info[:return_cast] if ret_info[:return_cast]
  method
end

def resolve_auto_method(ast, qt_class, auto_entry)
  entry = auto_entry.is_a?(String) ? { qt_name: auto_entry } : auto_entry.dup
  qt_name = entry.fetch(:qt_name)
  decls = collect_method_decls_with_bases(ast, qt_class, qt_name)
  return nil if decls.empty?

  built = decls.filter_map do |decl|
    parsed = parse_method_signature(decl)
    next unless parsed

    method = build_auto_method_from_decl(decl, entry)
    next unless method

    {
      method: method,
      param_types: parsed[:params].map { |param| normalized_cpp_type_name(param[:type]) }
    }
  end
  return nil if built.empty?

  if entry[:param_count]
    built.select! { |candidate| candidate[:method][:args].length == entry[:param_count] }
    return nil if built.empty?
  end

  if entry[:param_types]
    expected = entry[:param_types].map { |t| normalized_cpp_type_name(t) }
    built.select! { |candidate| candidate[:param_types] == expected }
    return nil if built.empty?
  end

  built.min_by { |candidate| candidate[:method][:args].length }[:method]
end

def expand_auto_methods(specs, ast)
  specs.map do |spec|
    auto_entries = Array(spec[:auto_methods])
    manual_methods = Array(spec[:methods])
    next spec if auto_entries.empty?

    existing_names = manual_methods.map { |m| m[:qt_name] }.to_set
    auto_methods = auto_entries.filter_map do |entry|
      qt_name = entry.is_a?(String) ? entry : entry[:qt_name]
      next if existing_names.include?(qt_name)

      resolved = resolve_auto_method(ast, spec[:qt_class], entry)
      raise "Failed to auto-resolve #{spec[:qt_class]}##{qt_name}" unless resolved

      resolved
    end

    spec.merge(methods: manual_methods + auto_methods)
  end
end

def normalize_cpp_type_name(raw)
  return nil if raw.nil? || raw.empty?

  name = raw.dup
  name = name.sub(/\A(class|struct)\s+/, '')
  name = name.split('<').first
  name = name.split(/\s+/).first
  name = name.split('::').last
  name&.strip
end

def collect_class_bases(ast, class_name)
  index = ast_class_index(ast)
  Array(index[:bases_by_class][class_name]).uniq
end

def class_has_method?(ast, class_name, method_name)
  collect_class_api(ast, class_name)[:methods].include?(method_name)
end

def build_generated_inheritance(ast, specs)
  known_qt = specs.map { |s| s[:qt_class] }
  base_cache = {}
  fetch_bases = lambda do |qt_class|
    base_cache[qt_class] ||= collect_class_bases(ast, qt_class)
  end

  super_qt_by_qt = {}

  known_qt.each do |qt_class|
    next if qt_class == 'QApplication'

    visited = {}
    prev = qt_class
    cur = qt_class

    loop do
      bases = Array(fetch_bases.call(cur))
      break if bases.empty?

      base = bases.first
      break if base.nil? || base.empty? || visited[base]

      visited[base] = true
      super_qt_by_qt[prev] ||= base

      break if known_qt.include?(base)

      prev = base
      cur = base
    end
  end

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
  class_decl = if super_ruby
                 "  class #{qt_class} < #{super_ruby}"
               else
                 "  class #{qt_class}"
               end
  lines << class_decl
  lines << "    QT_CLASS = '#{qt_class}'.freeze"
  lines << '    QT_API_QT_METHODS = [].freeze'
  lines << '    QT_API_RUBY_METHODS = [].freeze'
  lines << '    QT_API_PROPERTIES = [].freeze'
  lines << '  end'
  lines << ''
end

def enrich_specs_with_properties(specs, ast)
  specs.map do |spec|
    methods = spec[:methods].dup

    spec[:methods].each do |method|
      next unless method[:args].length == 1

      property = property_name_from_setter(method[:qt_name])
      next unless property
      next unless class_has_method?(ast, spec[:qt_class], property)
      next if methods.any? { |m| m[:qt_name] == property }

      arg = method[:args].first
      getter = {
        qt_name: property,
        ruby_name: property,
        ffi_return: arg[:ffi],
        args: [],
        property: property
      }
      getter[:return_cast] = :qstring_to_utf8 if arg[:ffi] == :string && arg[:cast] == :qstring
      methods << getter
    end

    spec.merge(methods: methods)
  end
end

def validate_qt_api!(ast, specs)
  errors = []

  specs.each do |spec|
    req = spec[:validate]
    api = collect_class_api(ast, spec[:qt_class])

    req[:constructors].each do |ctor|
      errors << "#{spec[:qt_class]}: constructor #{ctor} not found" unless api[:constructors].include?(ctor)
    end

    req[:methods].each do |method|
      errors << "#{spec[:qt_class]}: method #{method} not found" unless api[:methods].include?(method)
    end
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

def generate_cpp_constructor(lines, spec)
  name = ctor_function_name(spec)

  if spec[:constructor][:mode] == :qapplication
    lines << "extern \"C\" void* #{name}() {"
    lines << '  static int argc = 1;'
    lines << '  static char arg0[] = "qt-ruby";'
    lines << '  static char* argv[] = {arg0, nullptr};'
    lines << '  return new QApplication(argc, argv);'
    lines << '}'
    return
  end

  unless spec[:constructor][:parent]
    lines << "extern \"C\" void* #{name}() {"
    lines << "  return new #{spec[:qt_class]}();"
    lines << '}'
    return
  end

  lines << "extern \"C\" void* #{name}(void* parent_handle) {"
  lines << "  #{spec[:constructor][:parent_type].delete('*')}* parent = static_cast<#{spec[:constructor][:parent_type]}>(parent_handle);"
  lines << "  return new #{spec[:qt_class]}(parent);"
  lines << '}'
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

def generate_cpp_method(lines, spec, method)
  fn = method_function_name(spec, method)
  ret = ffi_return_to_cpp(method[:ffi_return])
  sig = ['void* handle'] + method[:args].map { |arg| "#{ffi_to_cpp_type(arg[:ffi])} #{arg[:name]}" }

  lines << "extern \"C\" #{ret} #{fn}(#{sig.join(', ')}) {"
  lines << '  if (!handle) {'
  lines << case method[:ffi_return]
           when :void
             '    return;'
           when :int
             '    return -1;'
           when :pointer
             '    return nullptr;'
           when :string
             '    return nullptr;'
           else
             '    return;'
           end
  lines << '  }'
  lines << ''
  lines << "  auto* obj = static_cast<#{spec[:qt_class]}*>(handle);"

  call_args = method[:args].map { |arg| arg_expr(arg) }.join(', ')
  invocation = "obj->#{method[:qt_name]}(#{call_args})"

  if method[:ffi_return] == :void
    lines << "  #{invocation};"
  elsif method[:ffi_return] == :string && method[:return_cast] == :qstring_to_utf8
    lines << "  const QString value = #{invocation};"
    lines << '  thread_local QByteArray utf8;'
    lines << '  utf8 = value.toUtf8();'
    lines << '  return utf8.constData();'
  else
    lines << "  return #{invocation};"
  end
  lines << '}'
end

def generate_cpp_bridge(specs)
  lines = []
  required_includes.each { |inc| lines << "#include <#{inc}>" }
  append_block(lines, cpp_bridge_prelude)

  specs.each do |spec|
    generate_cpp_constructor(lines, spec)
    lines << ''

    spec[:methods].each do |method|
      generate_cpp_method(lines, spec, method)
      lines << ''
    end
  end

  generate_cpp_delete(lines)
  lines.join("\n") + "\n"
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
  lines = []
  lines << '# frozen_string_literal: true'
  lines << ''
  lines << 'module Qt'
  lines << '  module BridgeAPI'
  lines << '    FUNCTIONS = ['
  all_ffi_functions(specs).each do |fn|
    args = fn[:args].map { |arg| ":#{arg}" }.join(', ')
    lines << "      { name: :#{fn[:name]}, args: [#{args}], return: :#{fn[:ffi_return]} },"
  end
  lines << '    ].freeze'
  lines << '  end'
  lines << 'end'
  lines.join("\n") + "\n"
end

def ruby_api_metadata(methods)
  qt_method_names = methods.map { |method| method[:qt_name] }.uniq
  ruby_method_names = methods.flat_map do |method|
    ruby_name = method[:ruby_name]
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

def append_ruby_native_call_method(lines, method:, native_call:, indent:)
  ruby_name = method[:ruby_name]
  snake_alias = to_snake(ruby_name)
  ruby_args = method[:args].map { |arg| arg[:name] }.join(', ')

  lines << "#{indent}def #{ruby_name}(#{ruby_args})"
  lines << "#{indent}  #{native_call}"
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
    lines << "#{indent}def initialize(parent = nil)"
    lines << "#{indent}  @handle = Native.#{spec[:prefix]}_new(parent&.handle)"
    lines << "#{indent}  init_children_tracking!" if widget_root
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
  else
    lines << "#{indent}def initialize(_argc = 0, _argv = [])"
    lines << "#{indent}  @handle = Native.#{spec[:prefix]}_new"
  end

  lines << "#{indent}  yield self if block_given?"
  lines << "#{indent}end"
end

def generate_ruby_qapplication(lines, spec)
  metadata = ruby_api_metadata(spec[:methods])

  lines << '  class QApplication'
  append_ruby_class_api_constants(lines, qt_class: spec[:qt_class], metadata: metadata, indent: '    ')
  lines << ''
  lines << '    attr_reader :handle'
  lines << '    include Inspectable'
  lines << '    include ApplicationLifecycle'
  lines << ''
  lines << '    class << self'
  lines << '      def current'
  lines << '        Thread.current[:qt_ruby_current_app]'
  lines << '      end'
  lines << ''
  lines << '      def current=(app)'
  lines << '        Thread.current[:qt_ruby_current_app] = app'
  lines << '      end'

  Array(spec[:class_methods]).each do |method|
    ruby_name = method[:ruby_name]
    snake_alias = to_snake(ruby_name)
    args = Array(method[:args]).join(', ')

    lines << ''
    lines << "      def #{ruby_name}(#{args})"
    if method[:native]
      native_args = Array(method[:args]).join(', ')
      call_suffix = native_args.empty? ? '' : "(#{native_args})"
      lines << "        Native.#{method[:native]}#{call_suffix}"
    else
      lines << '        nil'
    end
    lines << '      end'
    lines << "      alias_method :#{snake_alias}, :#{ruby_name}" if snake_alias != ruby_name
  end

  lines << '    end'
  lines << ''
  lines << '  end'
  lines << ''
end

def generate_ruby_widget_class(lines, spec, specs_by_qt, super_qt_by_qt, qt_to_ruby)
  inherited_methods = inherited_methods_for_spec(spec, specs_by_qt, super_qt_by_qt)
  all_methods = (inherited_methods + spec[:methods]).uniq { |m| m[:qt_name] }
  metadata = ruby_api_metadata(all_methods)

  super_qt = super_qt_by_qt[spec[:qt_class]]
  super_ruby = super_qt ? qt_to_ruby[super_qt] : nil
  widget_based = spec[:qt_class] != 'QWidget' && widget_based_qt_class?(spec[:qt_class], super_qt_by_qt)
  widget_root = spec[:ruby_class] == 'QWidget'

  class_decl = if super_ruby
                 "  class #{spec[:ruby_class]} < #{super_ruby}"
               else
                 "  class #{spec[:ruby_class]}"
               end
  lines << class_decl
  append_ruby_class_api_constants(lines, qt_class: spec[:qt_class], metadata: metadata, indent: '    ')
  lines << ''
  lines << '    attr_reader :handle'
  lines << '    attr_reader :children' if widget_root
  lines << '    include Inspectable'
  lines << '    include ChildrenTracking' if widget_root
  lines << '    include EventRuntime::WidgetMethods' if widget_root
  lines << ''
  append_widget_initializer(lines, spec: spec, widget_root: widget_root, indent: '    ')
  lines << ''

  spec[:methods].each do |method|
    call_args = ['@handle'] + method[:args].map { |arg| arg[:name] }
    native_call = "Native.#{spec[:prefix]}_#{to_snake(method[:qt_name])}(#{call_args.join(', ')})"
    append_ruby_native_call_method(lines, method: method, native_call: native_call, indent: '    ')
    append_ruby_property_writer(lines, method: method, indent: '    ')
    lines << ''
  end

  lines << '  end'
  lines << ''
end

def generate_ruby_widgets(specs, super_qt_by_qt, wrapper_qt_classes)
  lines = []
  lines << '# frozen_string_literal: true'
  lines << ''
  lines << 'module Qt'

  qapplication_spec = specs.find { |spec| spec[:ruby_class] == 'QApplication' }
  generate_ruby_qapplication(lines, qapplication_spec)

  specs_by_qt = specs.each_with_object({}) { |s, map| map[s[:qt_class]] = s }
  qt_to_ruby = specs.each_with_object({}) { |s, map| map[s[:qt_class]] = s[:ruby_class] }
  wrapper_qt_classes.each { |qt_class| qt_to_ruby[qt_class] = qt_class }
  qts_to_emit = (wrapper_qt_classes + specs.map { |s| s[:qt_class] }.reject { |q| q == 'QApplication' }).uniq

  emitted = {}
  emit_qt = lambda do |qt_class|
    return if emitted[qt_class]

    super_qt = super_qt_by_qt[qt_class]
    emit_qt.call(super_qt) if super_qt && qts_to_emit.include?(super_qt)

    spec = specs_by_qt[qt_class]
    if spec
      generate_ruby_widget_class(lines, spec, specs_by_qt, super_qt_by_qt, qt_to_ruby)
    else
      generate_ruby_wrapper_class(lines, qt_class, super_qt ? qt_to_ruby[super_qt] : nil)
    end

    emitted[qt_class] = true
  end

  qts_to_emit.sort.each { |qt_class| emit_qt.call(qt_class) }

  lines << 'end'
  lines.join("\n") + "\n"
end

ast = ast_dump
validate_qt_api!(ast, CLASS_SPECS)
expanded_specs = expand_auto_methods(CLASS_SPECS, ast)
effective_specs = enrich_specs_with_properties(expanded_specs, ast)
super_qt_by_qt, wrapper_qt_classes = build_generated_inheritance(ast, effective_specs)

FileUtils.mkdir_p(File.dirname(CPP_PATH))
File.write(CPP_PATH, generate_cpp_bridge(effective_specs))
FileUtils.mkdir_p(File.dirname(API_PATH))
File.write(API_PATH, generate_bridge_api(effective_specs))
FileUtils.mkdir_p(File.dirname(RUBY_WIDGETS_PATH))
File.write(RUBY_WIDGETS_PATH, generate_ruby_widgets(effective_specs, super_qt_by_qt, wrapper_qt_classes))

puts "Generated #{CPP_PATH}"
puts "Generated #{API_PATH}"
puts "Generated #{RUBY_WIDGETS_PATH}"

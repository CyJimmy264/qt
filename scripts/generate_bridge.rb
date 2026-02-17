#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tempfile'
require_relative 'specs/qt_widgets'

ROOT = File.expand_path('..', __dir__)
BUILD_DIR = File.join(ROOT, 'build')
GENERATED_DIR = File.join(BUILD_DIR, 'generated')
CPP_PATH = File.join(GENERATED_DIR, 'qt_ruby_bridge.cpp')
API_PATH = File.join(GENERATED_DIR, 'bridge_api.rb')
RUBY_WIDGETS_PATH = File.join(GENERATED_DIR, 'widgets.rb')

CLASS_SPECS = QtRubyGenerator::Specs::CLASS_SPECS

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

def ctor_function_name(spec)
  "qt_ruby_#{spec[:prefix]}_new"
end

def method_function_name(spec, method)
  "qt_ruby_#{spec[:prefix]}_#{to_snake(method[:qt_name])}"
end

def free_functions
  [
    { name: 'qt_ruby_qt_version', ffi_return: :string, args: [] }
  ]
end

def all_ffi_functions
  fns = free_functions.dup

  CLASS_SPECS.each do |spec|
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
    file.write("#include <QApplication>\n#include <QWidget>\n#include <QLabel>\n")
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

def validate_qt_api!(ast)
  errors = []

  CLASS_SPECS.each do |spec|
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
  lines << (method[:ffi_return] == :int ? '    return -1;' : '    return;')
  lines << '  }'
  lines << ''
  lines << "  auto* obj = static_cast<#{spec[:qt_class]}*>(handle);"

  call_args = method[:args].map { |arg| arg_expr(arg) }.join(', ')
  invocation = "obj->#{method[:qt_name]}(#{call_args})"

  if method[:ffi_return] == :void
    lines << "  #{invocation};"
  else
    lines << "  return #{invocation};"
  end
  lines << '}'
end

def generate_cpp_bridge
  lines = []
  lines << '#include <QApplication>'
  lines << '#include <QLabel>'
  lines << '#include <QString>'
  lines << '#include <QWidget>'
  lines << ''
  lines << 'namespace {'
  lines << 'QString as_qstring(const char* value, const char* fallback = "") {'
  lines << '  if (!value) {'
  lines << '    return QString::fromUtf8(fallback);'
  lines << '  }'
  lines << ''
  lines << '  return QString::fromUtf8(value);'
  lines << '}'
  lines << '}  // namespace'
  lines << ''
  lines << 'extern "C" const char* qt_ruby_qt_version() {'
  lines << '  return qVersion();'
  lines << '}'
  lines << ''

  CLASS_SPECS.each do |spec|
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

def generate_bridge_api
  lines = []
  lines << '# frozen_string_literal: true'
  lines << ''
  lines << 'module Qt'
  lines << '  module BridgeAPI'
  lines << '    FUNCTIONS = ['
  all_ffi_functions.each do |fn|
    args = fn[:args].map { |arg| ":#{arg}" }.join(', ')
    lines << "      { name: :#{fn[:name]}, args: [#{args}], return: :#{fn[:ffi_return]} },"
  end
  lines << '    ].freeze'
  lines << '  end'
  lines << 'end'
  lines.join("\n") + "\n"
end

def generate_ruby_qapplication(lines, spec)
  lines << '  class QApplication'
  lines << '    attr_reader :handle'
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
  lines << '    def initialize(_argc = 0, _argv = [])'
  lines << '      @windows = []'
  lines << '      @handle = Native.qapplication_new'
  lines << '      self.class.current = self'
  lines << '    end'
  lines << ''
  lines << '    def register_window(window)'
  lines << '      @windows << window unless @windows.include?(window)'
  lines << '    end'
  lines << ''
  lines << '    def exec'
  lines << '      @windows.each(&:show)'
  lines << '      Native.qapplication_exec(@handle)'
  lines << '    ensure'
  lines << '      dispose'
  lines << '    end'
  lines << ''
  lines << '    def dispose'
  lines << '      return if @handle.nil? || (@handle.respond_to?(:null?) && @handle.null?)'
  lines << ''
  lines << '      Native.qapplication_delete(@handle)'
  lines << '      @handle = nil'
  lines << '    end'
  lines << '  end'
  lines << ''
end

def generate_ruby_widget_class(lines, spec)
  lines << "  class #{spec[:ruby_class]}"
  lines << '    attr_reader :handle'
  lines << '    attr_reader :children' if spec[:ruby_class] == 'QWidget'
  lines << ''

  if spec[:constructor][:parent]
    lines << '    def initialize(parent = nil)'
    lines << "      @handle = Native.#{spec[:prefix]}_new(parent&.handle)"
    if spec[:ruby_class] == 'QWidget'
      lines << '      @children = []'
      lines << '      if parent'
      lines << '        parent.add_child(self)'
      lines << '      else'
      lines << '        app = QApplication.current'
      lines << '        app&.register_window(self)'
      lines << '      end'
    elsif spec[:ruby_class] == 'QLabel'
      lines << '      parent&.add_child(self)'
    end
  else
    lines << '    def initialize(_argc = 0, _argv = [])'
    lines << "      @handle = Native.#{spec[:prefix]}_new"
  end

  lines << '      yield self if block_given?'
  lines << '    end'
  lines << ''

  if spec[:ruby_class] == 'QWidget'
    lines << '    def add_child(child)'
    lines << '      @children << child'
    lines << '    end'
    lines << ''
  end

  spec[:methods].each do |method|
    ruby_name = method[:ruby_name]
    snake_alias = to_snake(ruby_name)
    ruby_args = method[:args].map { |arg| arg[:name] }.join(', ')
    lines << "    def #{ruby_name}(#{ruby_args})"
    call_args = ['@handle'] + method[:args].map { |arg| arg[:name] }
    lines << "      Native.#{spec[:prefix]}_#{to_snake(method[:qt_name])}(#{call_args.join(', ')})"
    lines << '    end'
    lines << "    alias_method :#{snake_alias}, :#{ruby_name}" if snake_alias != ruby_name
    lines << ''
  end

  lines << '  end'
  lines << ''
end

def generate_ruby_widgets
  lines = []
  lines << '# frozen_string_literal: true'
  lines << ''
  lines << 'module Qt'

  qapplication_spec = CLASS_SPECS.find { |spec| spec[:ruby_class] == 'QApplication' }
  generate_ruby_qapplication(lines, qapplication_spec)

  CLASS_SPECS.each do |spec|
    next if spec[:ruby_class] == 'QApplication'

    generate_ruby_widget_class(lines, spec)
  end

  lines << 'end'
  lines.join("\n") + "\n"
end

ast = ast_dump
validate_qt_api!(ast)

FileUtils.mkdir_p(File.dirname(CPP_PATH))
File.write(CPP_PATH, generate_cpp_bridge)
FileUtils.mkdir_p(File.dirname(API_PATH))
File.write(API_PATH, generate_bridge_api)
FileUtils.mkdir_p(File.dirname(RUBY_WIDGETS_PATH))
File.write(RUBY_WIDGETS_PATH, generate_ruby_widgets)

puts "Generated #{CPP_PATH}"
puts "Generated #{API_PATH}"
puts "Generated #{RUBY_WIDGETS_PATH}"

#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tempfile'
require_relative 'generate_bridge/free_function_specs'

ROOT = File.expand_path('..', __dir__)
BUILD_DIR = File.join(ROOT, 'build')
GENERATED_DIR = File.join(BUILD_DIR, 'generated')
CPP_PATH = File.join(GENERATED_DIR, 'qt_ruby_bridge.cpp')
API_PATH = File.join(GENERATED_DIR, 'bridge_api.rb')
RUBY_WIDGETS_PATH = File.join(GENERATED_DIR, 'widgets.rb')
RUBY_CONSTANTS_PATH = File.join(GENERATED_DIR, 'constants.rb')

# Universal generation policy: class set is discovered from AST per scope.
GENERATOR_SCOPE = (ENV['QT_RUBY_SCOPE'] || 'all').freeze
SUPPORTED_SCOPES = %w[widgets qobject all].freeze

def build_qapplication_spec(ast)
  instance_methods = [
    { qt_name: 'exec', ruby_name: 'exec', ffi_return: :int, args: [] }
  ]
  reserved_class_natives = instance_methods.map { |method| "qapplication_#{to_snake(method[:qt_name])}" }.to_set
  class_methods = qapplication_class_method_specs(ast).reject { |method| reserved_class_natives.include?(method[:native]) }

  {
    qt_class: 'QApplication',
    ruby_class: 'QApplication',
    include: 'QApplication',
    prefix: 'qapplication',
    constructor: { parent: false, mode: :qapplication },
    class_methods: class_methods,
    methods: instance_methods,
    validate: { constructors: ['QApplication'], methods: ['exec'] }
  }
end
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

def qobject_based_qt_class?(qt_class, super_qt_by_qt)
  return true if qt_class == 'QObject'

  cur = qt_class
  while (sup = super_qt_by_qt[cur])
    return true if sup == 'QObject'

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

    map_cpp_return_type(parsed[:return_type], ast: ast)
  end
end

def build_property_getter_method(ast, getter_decl, property)
  parsed_getter = parse_method_signature(getter_decl)
  ret_info = map_cpp_return_type(parsed_getter[:return_type], ast: ast)
  return nil unless ret_info

  getter = {
    qt_name: property,
    ruby_name: property,
    ffi_return: ret_info[:ffi_return],
    args: [],
    property: property
  }
  getter[:return_cast] = ret_info[:return_cast] if ret_info[:return_cast]
  getter[:pointer_class] = ret_info[:pointer_class] if ret_info[:pointer_class]
  getter
end

def enrich_spec_with_property_getter!(methods, ast, spec, method)
  property = property_name_from_setter(method[:qt_name])
  return unless property_candidate?(method, ast, spec, property)

  return if attach_existing_property_getter?(methods, property)

  getter_decl = find_getter_decl(ast, spec[:qt_class], property)
  return unless getter_decl

  getter = build_property_getter_method(ast, getter_decl, property)
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
  when :qdatetime_from_utf8 then "qdatetime_from_bridge_value(#{arg[:name]})"
  when :qdate_from_utf8 then "qdate_from_bridge_value(#{arg[:name]})"
  when :qtime_from_utf8 then "qtime_from_bridge_value(#{arg[:name]})"
  when :qkeysequence_from_utf8 then "QKeySequence(as_qstring(#{arg[:name]}))"
  when :qicon_ref then "*static_cast<QIcon*>(#{arg[:name]})"
  when :qany_string_view then "QAnyStringView(as_qstring(#{arg[:name]}))"
  when :qvariant_from_utf8 then "qvariant_from_bridge_value(#{arg[:name]})"
  when :alignment then "static_cast<Qt::Alignment>(#{arg[:name]})"
  when String then "static_cast<#{arg[:cast]}>(#{arg[:name]})"
  else
    arg[:name]
  end
end

def emit_cpp_qapplication_constructor(lines, name)
  lines << "extern \"C\" void* #{name}(const char* argv0) {"
  lines << '  // Delegate QApplication ownership/thread-contract policy to runtime.'
  lines << '  return QtRubyRuntime::qapplication_new(argv0);'
  lines << '}'
end

def emit_cpp_default_constructor(lines, name, qt_class)
  lines << "extern \"C\" void* #{name}() {"
  lines << "  return new #{qt_class}();"
  lines << '}'
end

def string_ctor_arg_expr(var_name, cast)
  case cast || :qstring
  when :qany_string_view then "QAnyStringView(as_qstring(#{var_name}))"
  when :cstr then var_name
  else "as_qstring(#{var_name})"
  end
end

def emit_cpp_string_path_constructor(lines, name, qt_class, arg_cast)
  lines << "extern \"C\" void* #{name}(const char* path) {"
  lines << '  const char* raw = path ? path : "";'
  lines << "  return new #{qt_class}(#{string_ctor_arg_expr('raw', arg_cast)});"
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

def emit_cpp_keysequence_parent_constructor(lines, name, spec)
  parent_type = spec[:constructor][:parent_type]
  parent_class = parent_type.delete('*')
  lines << "extern \"C\" void* #{name}(const char* key, void* parent_handle) {"
  lines << '  const char* raw = key ? key : "";'
  lines << "  #{parent_class}* parent = static_cast<#{parent_type}>(parent_handle);"
  lines << "  return new #{spec[:qt_class]}(QKeySequence(as_qstring(raw)), parent);"
  lines << '}'
end

def generate_cpp_constructor(lines, spec)
  name = ctor_function_name(spec)

  if spec[:constructor][:mode] == :qapplication
    emit_cpp_qapplication_constructor(lines, name)
    return
  end
  if spec[:constructor][:mode] == :string_path
    emit_cpp_string_path_constructor(lines, name, spec[:qt_class], spec[:constructor][:arg_cast])
    return
  end
  if spec[:constructor][:mode] == :keysequence_parent
    emit_cpp_keysequence_parent_constructor(lines, name, spec)
    return
  end

  unless spec[:constructor][:parent]
    emit_cpp_default_constructor(lines, name, spec[:qt_class])
    return
  end

  emit_cpp_parent_constructor(lines, name, spec)
end

def generate_cpp_delete(lines)
  lines << 'extern "C" bool qt_ruby_qapplication_delete(void* app_handle) {'
  lines << '  // Runtime performs safe shutdown ordering and thread checks.'
  lines << '  return QtRubyRuntime::qapplication_delete(app_handle);'
  lines << '}'
end

def cpp_method_signature(method)
  ['void* handle'] + method[:args].map { |arg| "#{ffi_to_cpp_type(arg[:ffi])} #{arg[:name]}" }
end

def cpp_null_handle_return(method)
  case method[:ffi_return]
  when :int
    '    return -1;'
  when :bool
    '    return false;'
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

def generate_cpp_bridge(specs, free_function_specs)
  lines = required_includes(GENERATOR_SCOPE).map { |inc| "#include <#{inc}>" }
  append_block(lines, cpp_bridge_prelude)
  append_cpp_free_function_definitions(lines, free_function_specs)

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
    #include <QAnyStringView>
    #include <QIcon>
    #include <QJsonDocument>
    #include <QJsonParseError>
    #include <QDateTime>
    #include <QDate>
    #include <QTime>
    #include <QKeySequence>
    #include <QString>
    #include <QVariant>
    #include "qt_ruby_runtime.hpp"

    namespace {

    QString as_qstring(const char* value, const char* fallback = "") {
      if (!value) {
        return QString::fromUtf8(fallback);
      }

      return QString::fromUtf8(value);
    }

    QVariant qvariant_from_bridge_value(const char* value) {
      const QString raw = as_qstring(value);
      if (!raw.startsWith(QStringLiteral("qtv:"))) {
        return QVariant(raw);
      }

      if (raw == QStringLiteral("qtv:nil")) {
        return QVariant();
      }

      const int first_colon = raw.indexOf(':', 4);
      if (first_colon < 0) {
        return QVariant(raw);
      }

      const QString tag = raw.mid(4, first_colon - 4);
      const QString payload = raw.mid(first_colon + 1);

      if (tag == QStringLiteral("bool")) {
        return QVariant(payload == QStringLiteral("1"));
      }

      if (tag == QStringLiteral("int")) {
        bool ok = false;
        const qlonglong parsed = payload.toLongLong(&ok);
        return ok ? QVariant(parsed) : QVariant(raw);
      }

      if (tag == QStringLiteral("float")) {
        bool ok = false;
        const double parsed = payload.toDouble(&ok);
        return ok ? QVariant(parsed) : QVariant(raw);
      }

      if (tag == QStringLiteral("str")) {
        const QByteArray decoded = QByteArray::fromBase64(payload.toUtf8());
        return QVariant(QString::fromUtf8(decoded));
      }

      if (tag == QStringLiteral("json")) {
        const QByteArray decoded = QByteArray::fromBase64(payload.toUtf8());
        QJsonParseError err{};
        const QJsonDocument doc = QJsonDocument::fromJson(decoded, &err);
        if (err.error == QJsonParseError::NoError) {
          return doc.toVariant();
        }
      }

      return QVariant(raw);
    }

    QDateTime qdatetime_from_bridge_value(const char* value) {
      const QString raw = as_qstring(value);
      const QString payload = raw.startsWith(QStringLiteral("qtdt:")) ? raw.mid(5) : raw;
      QDateTime parsed = QDateTime::fromString(payload, Qt::ISODateWithMs);
      if (!parsed.isValid()) {
        parsed = QDateTime::fromString(payload, Qt::ISODate);
      }
      return parsed;
    }

    QDate qdate_from_bridge_value(const char* value) {
      const QString raw = as_qstring(value);
      const QString payload = raw.startsWith(QStringLiteral("qtdate:")) ? raw.mid(7) : raw;
      QDate parsed = QDate::fromString(payload, QStringLiteral("yyyy-MM-dd"));
      if (!parsed.isValid()) {
        parsed = QDate::fromString(payload, Qt::ISODate);
      }
      return parsed;
    }

    QTime qtime_from_bridge_value(const char* value) {
      const QString raw = as_qstring(value);
      const QString payload = raw.startsWith(QStringLiteral("qttime:")) ? raw.mid(7) : raw;
      QTime parsed = QTime::fromString(payload, QStringLiteral("HH:mm:ss"));
      if (!parsed.isValid()) {
        parsed = QTime::fromString(payload, QStringLiteral("HH:mm"));
      }
      return parsed;
    }

    QString qdatetime_to_bridge_string(const QDateTime& value) {
      return QStringLiteral("qtdt:") + value.toString(Qt::ISODateWithMs);
    }

    QString qdate_to_bridge_string(const QDate& value) {
      return QStringLiteral("qtdate:") + value.toString(QStringLiteral("yyyy-MM-dd"));
    }

    QString qtime_to_bridge_string(const QTime& value) {
      return QStringLiteral("qttime:") + value.toString(QStringLiteral("HH:mm:ss"));
    }

    QString qvariant_to_bridge_string(const QVariant& value) {
      if (!value.isValid() || value.isNull()) {
        return QStringLiteral("qtv:nil");
      }

      switch (value.metaType().id()) {
        case QMetaType::Bool:
          return QStringLiteral("qtv:bool:") + (value.toBool() ? QStringLiteral("1") : QStringLiteral("0"));
        case QMetaType::Int:
        case QMetaType::UInt:
        case QMetaType::LongLong:
        case QMetaType::ULongLong:
          return QStringLiteral("qtv:int:") + QString::number(value.toLongLong());
        case QMetaType::Float:
        case QMetaType::Double:
          return QStringLiteral("qtv:float:") + QString::number(value.toDouble(), 'g', 17);
        case QMetaType::QString: {
          const QByteArray b64 = value.toString().toUtf8().toBase64();
          return QStringLiteral("qtv:str:") + QString::fromUtf8(b64);
        }
        default:
          break;
      }

      const QJsonDocument doc = QJsonDocument::fromVariant(value);
      if (!doc.isNull()) {
        const QByteArray b64 = doc.toJson(QJsonDocument::Compact).toBase64();
        return QStringLiteral("qtv:json:") + QString::fromUtf8(b64);
      }

      const QByteArray fallback = value.toString().toUtf8().toBase64();
      return QStringLiteral("qtv:str:") + QString::fromUtf8(fallback);
    }
    }  // namespace
  CPP
end

def generate_bridge_api(specs, free_function_specs)
  lines = bridge_api_prelude_lines
  append_bridge_api_function_lines(lines, specs, free_function_specs)
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

def append_bridge_api_function_lines(lines, specs, free_function_specs)
  all_ffi_functions(specs, free_function_specs: free_function_specs).each do |fn|
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
  when :bool then "(#{safe}.nil? ? false : #{safe})"
  when :pointer then safe
  when :string
    return "(#{safe}.nil? ? '' : Qt::VariantCodec.encode(#{safe}))" if arg[:cast] == :qvariant_from_utf8
    return "(#{safe}.nil? ? '' : Qt::DateTimeCodec.encode_qdatetime(#{safe}))" if arg[:cast] == :qdatetime_from_utf8
    return "(#{safe}.nil? ? '' : Qt::DateTimeCodec.encode_qdate(#{safe}))" if arg[:cast] == :qdate_from_utf8
    return "(#{safe}.nil? ? '' : Qt::DateTimeCodec.encode_qtime(#{safe}))" if arg[:cast] == :qtime_from_utf8
    return "(#{safe}.nil? ? '' : Qt::KeySequenceCodec.encode(#{safe}))" if arg[:cast] == :qkeysequence_from_utf8
    return "(#{safe}.nil? ? '' : Qt::StringCodec.to_qt_text(#{safe}))" if text_bridge_arg?(arg)

    "(#{safe}.nil? ? '' : #{safe})"
  else "(#{safe}.nil? ? '' : #{safe})"
  end
end

def ruby_arg_call_value(arg, safe, optional:)
  return "Qt::StringCodec.to_qt_text(#{safe})" if text_bridge_arg?(arg) && !optional
  return "Qt::VariantCodec.encode(#{safe})" if arg[:cast] == :qvariant_from_utf8 && !optional
  return "Qt::DateTimeCodec.encode_qdatetime(#{safe})" if arg[:cast] == :qdatetime_from_utf8 && !optional
  return "Qt::DateTimeCodec.encode_qdate(#{safe})" if arg[:cast] == :qdate_from_utf8 && !optional
  return "Qt::DateTimeCodec.encode_qtime(#{safe})" if arg[:cast] == :qtime_from_utf8 && !optional
  return "Qt::KeySequenceCodec.encode(#{safe})" if arg[:cast] == :qkeysequence_from_utf8 && !optional

  optional ? optional_arg_replacement(arg, safe) : safe
end

def text_bridge_arg?(arg)
  arg[:ffi] == :string && %i[qstring qany_string_view].include?(arg[:cast])
end

def rewrite_native_call_args(native_call, method, arg_map, required_arg_count)
  rewritten_native_call = native_call
  method[:args].each_with_index do |arg, idx|
    safe = arg_map[arg[:name]]
    replacement = ruby_arg_call_value(arg, safe, optional: idx >= required_arg_count)
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
  method_body = ruby_native_method_body(method, rewritten_native_call)

  lines << "#{indent}def #{ruby_name}(#{ruby_args})"
  lines << "#{indent}  #{method_body}"
  lines << "#{indent}end"
  lines << "#{indent}alias_method :#{snake_alias}, :#{ruby_name}" if snake_alias != ruby_name
end

def ruby_native_method_body(method, rewritten_native_call)
  return "Qt::StringCodec.from_qt_text(#{rewritten_native_call})" if method[:return_cast] == :qstring_to_utf8
  return "Qt::VariantCodec.decode(#{rewritten_native_call})" if method[:return_cast] == :qvariant_to_utf8
  return "Qt::DateTimeCodec.decode_qdatetime(#{rewritten_native_call})" if method[:return_cast] == :qdatetime_to_utf8
  return "Qt::DateTimeCodec.decode_qdate(#{rewritten_native_call})" if method[:return_cast] == :qdate_to_utf8
  return "Qt::DateTimeCodec.decode_qtime(#{rewritten_native_call})" if method[:return_cast] == :qtime_to_utf8
  return "Qt::ObjectWrapper.wrap(#{rewritten_native_call}, '#{method[:pointer_class]}')" if method[:pointer_class]

  rewritten_native_call
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
  if spec[:constructor][:mode] == :string_path
    append_string_path_initializer(lines, spec, indent)
  elsif spec[:constructor][:mode] == :keysequence_parent
    append_keysequence_parent_initializer(lines, spec, widget_root, indent)
  elsif spec[:constructor][:parent]
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

def append_string_path_initializer(lines, spec, indent)
  lines << "#{indent}def initialize(path = nil)"
  lines << "#{indent}  @handle = Native.#{spec[:prefix]}_new(Qt::StringCodec.to_qt_text(path))"
end

def append_keysequence_parent_initializer(lines, spec, widget_root, indent)
  lines << "#{indent}def initialize(key = nil, parent = nil)"
  lines << "#{indent}  if parent.nil? && (key.nil? || key.respond_to?(:handle))"
  lines << "#{indent}    parent = key"
  lines << "#{indent}    key = nil"
  lines << "#{indent}  end"
  lines << "#{indent}  @handle = Native.#{spec[:prefix]}_new(Qt::KeySequenceCodec.encode(key), parent&.handle)"
  lines << "#{indent}  init_children_tracking!" if widget_root
  append_parent_registration_logic(lines, spec, indent)
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
  arg_hashes = Array(method[:args]).each_with_index.map { |arg, idx| qapplication_arg_spec(arg, idx) }
  arg_map = ruby_arg_name_map(arg_hashes)
  rendered_args = arg_hashes.map { |arg| arg_map[arg[:name]] }.join(', ')
  [arg_hashes, arg_map, rendered_args]
end

def qapplication_arg_spec(arg, idx)
  return arg.transform_keys(&:to_sym) if arg.is_a?(Hash)

  { name: (arg || "arg#{idx + 1}").to_sym }
end

def qapplication_method_call_suffix(arg_hashes, arg_map, method)
  required_arg_count = method.fetch(:required_arg_count, arg_hashes.length)
  native_args = arg_hashes.each_with_index.map do |arg, idx|
    safe = arg_map[arg[:name]]
    ruby_arg_call_value(arg, safe, optional: idx >= required_arg_count)
  end.join(', ')
  native_args.empty? ? '' : "(#{native_args})"
end

def append_ruby_qapplication_class_method(lines, method)
  ruby_name = ruby_safe_method_name(method[:ruby_name])
  snake_alias = to_snake(ruby_name)
  method_arg_hashes, arg_map, args = qapplication_method_arguments(method)
  call_suffix = qapplication_method_call_suffix(method_arg_hashes, arg_map, method)

  lines << ''
  lines << "      def #{ruby_name}(#{args})"
  lines << if method[:native]
             qapplication_class_method_body(method, "Native.#{method[:native]}#{call_suffix}")
           else
             '        nil'
           end
  lines << '      end'
  lines << "      alias_method :#{snake_alias}, :#{ruby_name}" if snake_alias != ruby_name
end

def qapplication_class_method_body(method, native_call)
  return "        Qt::StringCodec.from_qt_text(#{native_call})" if method[:return_cast] == :qstring_to_utf8
  return "        Qt::DateTimeCodec.decode_qdatetime(#{native_call})" if method[:return_cast] == :qdatetime_to_utf8
  return "        Qt::DateTimeCodec.decode_qdate(#{native_call})" if method[:return_cast] == :qdate_to_utf8
  return "        Qt::DateTimeCodec.decode_qtime(#{native_call})" if method[:return_cast] == :qtime_to_utf8
  return "        Qt::ObjectWrapper.wrap(#{native_call}, '#{method[:pointer_class]}')" if method[:pointer_class]

  "        #{native_call}"
end

def generate_ruby_widget_class_header(lines, spec, metadata:, super_ruby:, class_flags:)
  widget_root = class_flags[:widget_root]
  qobject_based = class_flags[:qobject_based]
  class_decl = super_ruby ? "  class #{spec[:ruby_class]} < #{super_ruby}" : "  class #{spec[:ruby_class]}"
  lines << class_decl
  append_ruby_class_api_constants(lines, qt_class: spec[:qt_class], metadata: metadata, indent: '    ')
  lines << ''
  lines << '    attr_reader :handle'
  lines << '    attr_reader :children' if widget_root
  lines << '    include Inspectable'
  lines << '    include ChildrenTracking' if widget_root
  lines << '    include EventRuntime::QObjectMethods' if qobject_based
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
  qobject_based = qobject_based_qt_class?(spec[:qt_class], super_qt_by_qt)

  generate_ruby_widget_class_header(
    lines,
    spec,
    metadata: metadata,
    super_ruby: super_ruby,
    class_flags: { widget_root: widget_root, qobject_based: qobject_based }
  )
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

def ast_extract_first_value(node)
  return nil unless node.is_a?(Hash)

  value = node['value']
  return value if value && !value.to_s.empty?

  Array(node['inner']).each do |child|
    nested = ast_extract_first_value(child)
    return nested if nested
  end
  nil
end

def parse_ast_integer_value(raw)
  return nil if raw.nil?

  text = raw.to_s.strip
  return nil if text.empty?

  text = text.delete("'")
  text = text.gsub(/([0-9A-Fa-fxX]+)(?:[uUlL]+)\z/, '\1')
  Integer(text, 0)
rescue ArgumentError
  nil
end

def append_constant_with_conflict_warning(constants, name, value, warnings, context)
  existing = constants[name]
  if existing.nil?
    constants[name] = value
    return
  end

  return if existing == value

  warnings << "#{context}: #{name}=#{value} conflicts with existing #{existing}; keeping existing #{existing}"
end

def collect_enum_constants_for_scope(ast, target_scope, warnings = [])
  constants = {}

  walk_ast_scoped(ast) do |node, scope|
    next unless node['kind'] == 'EnumDecl'
    next unless scope == target_scope

    Array(node['inner']).each do |entry|
      next unless entry['kind'] == 'EnumConstantDecl'

      name = entry['name'].to_s
      next unless name.match?(/\A[A-Z][A-Za-z0-9_]*\z/)
      next if constants.key?(name)

      raw_value = ast_extract_first_value(entry)
      value = parse_ast_integer_value(raw_value)
      next if value.nil?

      append_constant_with_conflict_warning(constants, name, value, warnings, target_scope.join('::'))
    end
  end

  constants
end

def collect_qt_namespace_enum_constants(ast, warnings = [])
  constants = collect_enum_constants_for_scope(ast, ['Qt'], warnings)
  collect_enum_constants_for_scope(ast, ['QEvent'], warnings).each do |name, value|
    alias_name = "Event#{name}"
    next unless alias_name.match?(/\A[A-Z][A-Za-z0-9_]*\z/)

    append_constant_with_conflict_warning(constants, alias_name, value, warnings, 'Qt::QEventAlias')
  end
  constants
end

def qevent_symbol_name(name)
  to_snake(name).to_sym
end

def collect_qevent_symbol_map(ast, warnings = [])
  symbol_map = {}

  collect_enum_constants_for_scope(ast, ['QEvent'], warnings).each do |name, value|
    symbol_name = qevent_symbol_name(name)
    existing = symbol_map[symbol_name]
    if existing.nil?
      symbol_map[symbol_name] = { constant_name: "Event#{name}", value: value }
      next
    end

    next if existing[:value] == value && existing[:constant_name] == "Event#{name}"

    warnings << "Qt::QEventSymbolMap: #{symbol_name}=Event#{name}(#{value}) conflicts with existing " \
                "#{existing[:constant_name]}(#{existing[:value]}); keeping existing #{existing[:constant_name]}"
  end

  symbol_map
end

def collect_qt_scoped_enum_constants(ast, warnings = [])
  constants_by_owner = Hash.new { |h, k| h[k] = {} }

  walk_ast_scoped(ast) do |node, scope|
    next unless node['kind'] == 'EnumDecl'
    next if scope.empty?

    owner = scope.first
    next unless owner.match?(/\AQ[A-Z]\w*\z/)
    next if owner == 'Qt' || owner == 'QEvent'

    Array(node['inner']).each do |entry|
      next unless entry['kind'] == 'EnumConstantDecl'

      name = entry['name'].to_s
      next unless name.match?(/\A[A-Z][A-Za-z0-9_]*\z/)

      raw_value = ast_extract_first_value(entry)
      value = parse_ast_integer_value(raw_value)
      next if value.nil?

      append_constant_with_conflict_warning(
        constants_by_owner[owner],
        name,
        value,
        warnings,
        "Qt::#{owner}"
      )
    end
  end

  constants_by_owner
end

def emit_generation_warnings(warnings)
  warnings.uniq.each { |message| warn("WARNING: #{message}") }
end

def generate_ruby_constants(ast)
  warnings = []
  constants = collect_qt_namespace_enum_constants(ast, warnings)
  scoped_constants = collect_qt_scoped_enum_constants(ast, warnings)
  event_symbol_map = collect_qevent_symbol_map(ast, warnings)
  emit_generation_warnings(warnings)
  lines = ['# frozen_string_literal: true', '', 'module Qt']

  constants.sort.each do |name, value|
    lines << "  #{name} = #{value} unless const_defined?(:#{name}, false)"
  end

  lines << ''
  lines << '  GENERATED_SCOPED_CONSTANTS = {'
  scoped_constants.sort.each do |owner, owner_constants|
    lines << "    '#{owner}' => {"
    owner_constants.sort.each do |name, value|
      lines << "      '#{name}' => #{value},"
    end
    lines << '    },'
  end
  lines << '  }.freeze unless const_defined?(:GENERATED_SCOPED_CONSTANTS, false)'
  lines << ''
  lines << '  GENERATED_EVENT_TYPES = {'
  event_symbol_map.sort.each do |symbol_name, entry|
    lines << "    #{symbol_name.inspect} => #{entry[:constant_name]},"
  end
  lines << '  }.freeze unless const_defined?(:GENERATED_EVENT_TYPES, false)'

  lines << 'end'
  "#{lines.join("\n")}\n"
end

total_start = monotonic_now
ast = timed('ast_dump_total') { ast_dump }
free_function_specs = timed('build_free_function_specs') { qt_free_function_specs(ast) }
base_specs = timed('build_base_specs') { build_base_specs(ast) }
timed('validate_qt_api') { validate_qt_api!(ast, base_specs) }
expanded_specs = timed('expand_auto_methods') { expand_auto_methods(base_specs, ast) }
effective_specs = timed('enrich_specs_with_properties') { enrich_specs_with_properties(expanded_specs, ast) }
super_qt_by_qt, wrapper_qt_classes = timed('build_generated_inheritance') do
  build_generated_inheritance(ast, effective_specs)
end

timed('write_cpp_bridge') do
  FileUtils.mkdir_p(File.dirname(CPP_PATH))
  File.write(CPP_PATH, generate_cpp_bridge(effective_specs, free_function_specs))
end
timed('write_bridge_api') do
  FileUtils.mkdir_p(File.dirname(API_PATH))
  File.write(API_PATH, generate_bridge_api(effective_specs, free_function_specs))
end
timed('write_ruby_constants') do
  FileUtils.mkdir_p(File.dirname(RUBY_CONSTANTS_PATH))
  File.write(RUBY_CONSTANTS_PATH, generate_ruby_constants(ast))
end
timed('write_ruby_widgets') do
  FileUtils.mkdir_p(File.dirname(RUBY_WIDGETS_PATH))
  File.write(RUBY_WIDGETS_PATH, generate_ruby_widgets(effective_specs, super_qt_by_qt, wrapper_qt_classes))
end
debug_log("total=#{format('%.3fs', monotonic_now - total_start)}")

puts "Generated #{CPP_PATH}"
puts "Generated #{API_PATH}"
puts "Generated #{RUBY_CONSTANTS_PATH}"
puts "Generated #{RUBY_WIDGETS_PATH}"

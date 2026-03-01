# frozen_string_literal: true

RUNTIME_HEADER_PATH = File.expand_path('../../ext/qt_ruby_bridge/qt_ruby_runtime.hpp', __dir__)

SCALAR_CLASS_METHOD_FFI_RETURNS = %i[void int bool].freeze
QAPPLICATION_STATIC_METHOD_EXCLUSIONS = %w[exec].freeze

def qt_free_function_specs(ast)
  @qt_free_function_specs_cache ||= {}.compare_by_identity
  return @qt_free_function_specs_cache[ast] if @qt_free_function_specs_cache.key?(ast)

  qt_specs = []
  qt_specs << qversion_free_function_spec(ast)
  qt_specs.concat(qapplication_static_free_function_specs(ast))
  qt_specs << qapplication_top_level_widgets_count_spec(ast)
  runtime_specs = runtime_free_function_specs_from_header
  @qt_free_function_specs_cache[ast] = merge_free_function_specs(qt_specs, runtime_specs).freeze
end

def merge_free_function_specs(primary_specs, secondary_specs)
  merged = primary_specs.dup
  existing_names = merged.to_set { |spec| spec[:name] }
  secondary_specs.each do |spec|
    if existing_names.include?(spec[:name])
      warn "[gen][warn] skip runtime free-function #{spec[:name]}: already provided by Qt-derived spec"
      next
    end

    merged << spec
    existing_names << spec[:name]
  end
  merged
end

def runtime_free_function_specs_from_header
  @runtime_free_function_specs_from_header ||= begin
    raw = File.read(RUNTIME_HEADER_PATH)
    parse_runtime_free_function_specs(raw).freeze
  end
end

def parse_runtime_free_function_specs(raw)
  in_namespace = false
  specs = []
  raw.each_line do |line|
    in_namespace = true if line.include?('namespace QtRubyRuntime')
    in_namespace = false if in_namespace && line.include?('}  // namespace QtRubyRuntime')
    next unless in_namespace

    decl = parse_runtime_function_decl(line)
    next unless decl

    specs << runtime_decl_to_free_function_spec(decl)
  end
  specs
end

def parse_runtime_function_decl(line)
  md = line.strip.match(/\A(void|int)\s+([a-zA-Z_]\w*)\s*\(([^)]*)\)\s*;\z/)
  return nil unless md

  {
    return_type: md[1],
    name: md[2],
    args: parse_runtime_decl_args(md[3])
  }
end

def parse_runtime_decl_args(args_raw)
  stripped = args_raw.to_s.strip
  return [] if stripped.empty?

  stripped.split(',').map { |arg| parse_runtime_decl_arg(arg) }
end

def parse_runtime_decl_arg(arg)
  normalized = arg.to_s.strip.gsub(/\s+/, ' ')
  md = normalized.match(/\A(.+?)\s+([a-zA-Z_]\w*)\z/)
  raise "Unsupported runtime declaration argument: #{arg.inspect}" unless md

  { cpp_type: md[1].strip, name: md[2] }
end

def runtime_cpp_type_to_ffi(cpp_type)
  normalized = cpp_type.to_s.strip.gsub(/\s+/, ' ').gsub(/\s*\*\s*/, '*')
  return :pointer if normalized == 'void*'
  return :string if normalized == 'const char*'
  return :int if normalized == 'int'

  raise "Unsupported runtime declaration type for FFI: #{cpp_type.inspect}"
end

def runtime_decl_to_free_function_spec(decl)
  cpp_args = decl[:args].map { |arg| "#{arg[:cpp_type]} #{arg[:name]}" }.join(', ')
  call_args = decl[:args].map { |arg| arg[:name] }.join(', ')
  cpp_body =
    if decl[:return_type] == 'void'
      ["QtRubyRuntime::#{decl[:name]}(#{call_args});"]
    else
      ["return QtRubyRuntime::#{decl[:name]}(#{call_args});"]
    end

  {
    name: "qt_ruby_#{decl[:name]}",
    ffi_return: decl[:return_type].to_sym,
    args: decl[:args].map { |arg| runtime_cpp_type_to_ffi(arg[:cpp_type]) },
    cpp_return: decl[:return_type],
    cpp_args: cpp_args,
    cpp_body: cpp_body
  }
end

def qversion_free_function_spec(ast)
  found = false
  walk_ast(ast) do |node|
    next unless node['kind'] == 'FunctionDecl'
    next unless node['name'] == 'qVersion'
    next unless node.dig('type', 'qualType').to_s.include?('const char *()')

    found = true
    break
  end
  raise 'Unable to find qVersion() in AST' unless found

  {
    name: 'qt_ruby_qt_version',
    ffi_return: :string,
    args: [],
    cpp_return: 'const char*',
    cpp_args: '',
    cpp_body: ['return qVersion();'],
    qapplication_method: { ruby_name: 'qtVersion', native: 'qt_version', args: [], return_cast: :qstring_to_utf8 }
  }
end

def qapplication_top_level_widgets_count_spec(ast)
  has_top_level_widgets = collect_method_decls_with_bases(ast, 'QApplication', 'topLevelWidgets').any?
  raise 'Unable to find QApplication::topLevelWidgets in AST' unless has_top_level_widgets

  {
    name: 'qt_ruby_qapplication_top_level_widgets_count',
    ffi_return: :int,
    args: [],
    cpp_return: 'int',
    cpp_args: '',
    cpp_body: ['return QApplication::topLevelWidgets().size();'],
    qapplication_method: { ruby_name: 'topLevelWidgetsCount', native: 'qapplication_top_level_widgets_count', args: [] }
  }
end

def qapplication_static_free_function_specs(ast)
  int_cast_types = ast_int_cast_type_set(ast)
  method_names = collect_method_names_with_bases(ast, 'QApplication').uniq
  method_names -= QAPPLICATION_STATIC_METHOD_EXCLUSIONS
  method_names.filter_map do |qt_name|
    build_qapplication_static_free_function_spec(ast, qt_name, int_cast_types)
  end
end

def build_qapplication_static_free_function_spec(ast, qt_name, int_cast_types)
  candidate = resolve_qapplication_static_noarg_candidate(ast, qt_name, int_cast_types)
  return nil unless candidate

  native_name = "qapplication_#{to_snake(qt_name)}"
  cpp_body =
    if candidate[:ffi_return] == :void
      ["QApplication::#{qt_name}();"]
    elsif candidate[:return_cast]
      ["return static_cast<int>(QApplication::#{qt_name}());"]
    else
      ["return QApplication::#{qt_name}();"]
    end

  {
    name: "qt_ruby_#{native_name}",
    ffi_return: candidate[:ffi_return],
    args: [],
    cpp_return: ffi_return_to_cpp(candidate[:ffi_return]),
    cpp_args: '',
    cpp_body: cpp_body,
    qapplication_method: { ruby_name: qt_name, native: native_name, args: [] }
  }
end

def resolve_qapplication_static_noarg_candidate(ast, qt_name, int_cast_types)
  decls = collect_method_decls_with_bases(ast, 'QApplication', qt_name)
  candidates = decls.filter_map do |decl|
    next unless decl['storageClass'] == 'static'
    next unless decl['__effective_access'] == 'public'

    parsed = parse_method_signature(decl)
    next unless parsed && parsed[:required_arg_count].zero?

    ret_info = qapplication_static_return_info(parsed[:return_type], int_cast_types)
    next unless ret_info

    { decl: decl, param_count: parsed[:params].length }.merge(ret_info)
  end
  return nil if candidates.empty?

  candidates.min_by { |item| item[:param_count] }
end

def qapplication_static_return_info(return_type, int_cast_types)
  mapped = map_cpp_return_type(return_type)
  if mapped && SCALAR_CLASS_METHOD_FFI_RETURNS.include?(mapped[:ffi_return])
    return { ffi_return: mapped[:ffi_return], return_cast: nil }
  end

  normalized = normalized_cpp_type_name(return_type)
  return nil unless normalized.include?('::') && int_cast_types.include?(normalized)

  { ffi_return: :int, return_cast: normalized }
end

def qapplication_class_method_specs(ast)
  qt_free_function_specs(ast).filter_map { |spec| spec[:qapplication_method] }
end

def append_cpp_free_function_definitions(lines, free_function_specs)
  free_function_specs.each do |spec|
    lines << "extern \"C\" #{spec[:cpp_return]} #{spec[:name]}(#{spec[:cpp_args]}) {"
    Array(spec[:cpp_body]).each { |line| lines << "  #{line}" }
    lines << '}'
    lines << ''
  end
end

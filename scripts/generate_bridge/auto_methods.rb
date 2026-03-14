# frozen_string_literal: true

def unsupported_cpp_type?(type_name)
  type_name.include?('<') || type_name.include?('>') || type_name.include?('[') || type_name.include?('(')
end

def map_cpp_pointer_arg_type(type_name, qt_class)
  return nil unless type_name.end_with?('*')

  base = type_name.sub(/\s*\*\z/, '').strip
  if qt_class && !base.include?('::') && base.match?(/\A[A-Z]\w*\z/) && !base.start_with?('Q')
    base = "#{qt_class}::#{base}"
  end
  { ffi: :pointer, cast: "#{base}*" }
end

def map_builtin_intlike_arg_type(type_name)
  return { ffi: :int } if type_name == 'int'
  return { ffi: :bool } if type_name == 'bool'

  nil
end

def map_qualified_intlike_arg_type(type_name, qt_class, int_cast_types)
  return nil unless qt_class && type_name.match?(/\A[A-Z]\w*\z/)

  qualified = "#{qt_class}::#{type_name}"
  return { ffi: :int, cast: qualified } if int_cast_types&.include?(qualified)

  nil
end

def map_cpp_intlike_arg_type(type_name, qt_class, int_cast_types)
  builtin = map_builtin_intlike_arg_type(type_name)
  return builtin if builtin
  return { ffi: :int, cast: type_name } if type_name.include?('::') && int_cast_types&.include?(type_name)

  map_qualified_intlike_arg_type(type_name, qt_class, int_cast_types)
end

def map_cpp_arg_type(type_name, qt_class: nil, int_cast_types: nil)
  raw = type_name.to_s.strip
  return nil if raw.end_with?('&') && !raw.start_with?('const ')

  compact_raw = raw.gsub(/\s+/, ' ')

  type = raw
  type = type.sub(/\Aconst\s+/, '').sub(/\s*&\z/, '').strip
  return nil if unsupported_cpp_type?(type)
  return { ffi: :string, cast: :qstring } if type == 'QString'
  return { ffi: :string, cast: :qdatetime_from_utf8 } if type == 'QDateTime'
  return { ffi: :string, cast: :qdate_from_utf8 } if type == 'QDate'
  return { ffi: :string, cast: :qtime_from_utf8 } if type == 'QTime'
  return { ffi: :string, cast: :qkeysequence_from_utf8 } if type == 'QKeySequence'
  return { ffi: :pointer, cast: :qicon_ref } if type == 'QIcon'
  return { ffi: :string, cast: :qany_string_view } if type == 'QAnyStringView'
  return { ffi: :string, cast: :qvariant_from_utf8 } if type == 'QVariant'
  return { ffi: :string } if compact_raw.match?(/\Aconst\s+char\s*\*\z/)

  map_cpp_pointer_arg_type(type, qt_class) || map_cpp_intlike_arg_type(type, qt_class, int_cast_types)
end

def normalized_cpp_type_name(type_name)
  type = type_name.to_s.strip
  type = type.sub(/\Aconst\s+/, '').sub(/\s*&\z/, '').strip
  type = type.sub(/\s*\*\z/, '*') if type.end_with?('*')
  type
end

def map_cpp_return_type(type_name, ast: nil)
  raw = type_name.to_s.strip
  return nil if unsupported_cpp_type?(raw)
  return nil if raw.start_with?('const ') && raw.end_with?('*')

  type = raw.sub(/\Aconst\s+/, '').sub(/\s*&\z/, '').strip
  map_scalar_cpp_return_type(type) || map_pointer_cpp_return_type(type, ast: ast)
end

def map_scalar_cpp_return_type(type)
  return { ffi_return: :void } if type == 'void'
  return { ffi_return: :int } if type == 'int'
  return { ffi_return: :bool } if type == 'bool'
  return { ffi_return: :string, return_cast: :qstring_to_utf8 } if type == 'QString'
  return { ffi_return: :string, return_cast: :qdatetime_to_utf8 } if type == 'QDateTime'
  return { ffi_return: :string, return_cast: :qdate_to_utf8 } if type == 'QDate'
  return { ffi_return: :string, return_cast: :qtime_to_utf8 } if type == 'QTime'
  return { ffi_return: :string, return_cast: :qvariant_to_utf8 } if type == 'QVariant'

  nil
end

def map_pointer_cpp_return_type(type, ast: nil)
  return nil unless type.end_with?('*')

  info = { ffi_return: :pointer }
  base_type = type.sub(/\s*\*\z/, '').strip
  if ast && class_inherits?(ast, base_type, 'QObject')
    info[:pointer_class] = base_type
  end

  info
end

def parse_method_param_nodes(method_decl)
  Array(method_decl['inner']).select { |node| node['kind'] == 'ParmVarDecl' }
end

def parse_method_param(param, idx)
  {
    name: param['name'] || "arg#{idx + 1}",
    type: param.dig('type', 'qualType').to_s,
    has_default: !param['init'].nil?
  }
end

def parse_method_params(method_decl)
  params = parse_method_param_nodes(method_decl)
  required_arg_count = params.count { |param| param['init'].nil? }
  parsed_params = params.each_with_index.map { |param, idx| parse_method_param(param, idx) }
  [parsed_params, required_arg_count]
end

def parse_method_signature(method_decl)
  qual = method_decl.dig('type', 'qualType').to_s
  md = qual.match(/\A(.+?)\s*\((.*)\)/)
  return nil unless md

  parsed_params, required_arg_count = parse_method_params(method_decl)
  {
    return_type: md[1].strip,
    required_arg_count: required_arg_count,
    params: parsed_params
  }
end

def build_auto_method_args(parsed, entry, qt_class, int_cast_types)
  arg_cast_overrides = Array(entry[:arg_casts])
  params = parsed[:params]
  required_arg_count = 0
  args = []

  params.each_with_index do |param, idx|
    cast_override = arg_cast_overrides[idx]
    arg_info = map_cpp_arg_type(param[:type], qt_class: qt_class, int_cast_types: int_cast_types)
    arg_info ||= { ffi: :int } if cast_override
    unless arg_info
      return nil unless skip_unsupported_optional_tail?(params, idx, param)

      break
    end

    args << { name: param[:name], ffi: arg_info[:ffi], cast: cast_override || arg_info[:cast] }.compact
    required_arg_count += 1 unless param[:has_default]
  end

  [args, required_arg_count]
end

def skip_unsupported_optional_tail?(params, idx, param)
  return false unless param[:has_default]

  params[(idx + 1)..].all? { |rest| rest[:has_default] }
end

def build_auto_method_hash(entry, ret_info, args, required_arg_count)
  method = {
    qt_name: entry[:qt_name],
    ruby_name: ruby_public_method_name(entry[:qt_name], entry[:ruby_name]),
    ffi_return: ret_info[:ffi_return],
    args: args,
    required_arg_count: required_arg_count
  }
  method[:return_cast] = ret_info[:return_cast] if ret_info[:return_cast]
  method[:pointer_class] = ret_info[:pointer_class] if ret_info[:pointer_class]
  method
end

def build_auto_method_from_decl(method_decl, entry, qt_class:, int_cast_types:, ast:)
  parsed = parse_method_signature(method_decl)
  return nil unless parsed

  ret_info = map_cpp_return_type(parsed[:return_type], ast: ast)
  return nil unless ret_info

  args, required_arg_count = build_auto_method_args(parsed, entry, qt_class, int_cast_types)
  return nil unless args

  build_auto_method_hash(entry, ret_info, args, required_arg_count)
end

def valid_auto_exportable_identifier?(name)
  return false if name.nil? || name.empty?
  return false unless name.match?(/\A[A-Za-z_]\w*\z/)

  true
end

def forbidden_auto_exportable_method_name?(name)
  return true if name.start_with?('~')
  return true if name.include?('operator')
  return true if name.end_with?('Event')
  return true if name.start_with?('qt_check_for_')

  forbidden_names = %w[
    event eventFilter childEvent customEvent timerEvent connectNotify disconnectNotify d_func connect disconnect
    initialize
  ]
  return true if forbidden_names.include?(name)

  false
end

def auto_exportable_method_name?(name)
  return false unless valid_auto_exportable_identifier?(name)
  return false if forbidden_auto_exportable_method_name?(name)

  true
end

def deprecated_method_decl?(decl)
  Array(decl['inner']).any? { |node| node['kind'] == 'DeprecatedAttr' }
end

def method_names_cache_entry(ast, class_name)
  @method_names_with_bases_cache ||= {}.compare_by_identity
  per_ast = (@method_names_with_bases_cache[ast] ||= {})
  [per_ast, class_name]
end

def invalid_method_name_scope?(class_name, visited)
  class_name.nil? || class_name.empty? || visited[class_name]
end

def build_auto_method_candidate(ast, decl, entry, qt_class, int_cast_types)
  parsed = parse_method_signature(decl)
  return nil unless parsed

  method = build_auto_method_from_decl(decl, entry, qt_class: qt_class, int_cast_types: int_cast_types, ast: ast)
  return nil unless method

  {
    method: method,
    param_types: parsed[:params].map { |param| normalized_cpp_type_name(param[:type]) }
  }
end

def auto_method_decl_candidate?(decl)
  return false unless decl['__effective_access'] == 'public'
  return false if deprecated_method_decl?(decl)
  return false unless auto_exportable_method_name?(decl['name'])

  true
end

def collect_method_names_with_bases(ast, class_name, visited = {})
  cache, cache_key = method_names_cache_entry(ast, class_name)
  return cache[cache_key] if cache[cache_key]
  return [] if invalid_method_name_scope?(class_name, visited)

  visited[class_name] = true
  index = ast_class_index(ast)
  own_names = index[:methods_by_class].fetch(class_name, {}).keys
  base_names = collect_base_method_names_with_bases(ast, class_name, visited)
  combined = (own_names + base_names).uniq
  cache[cache_key] = combined
  combined
end

def collect_base_method_names_with_bases(ast, class_name, visited)
  collect_class_bases(ast, class_name).flat_map do |base|
    collect_method_names_with_bases(ast, base, visited)
  end
end

def resolve_auto_method_cache_key(qt_class, entry)
  [
    qt_class,
    entry[:qt_name],
    entry[:ruby_name],
    entry[:param_count],
    Array(entry[:param_types]).map { |type_name| normalized_cpp_type_name(type_name) },
    Array(entry[:arg_casts])
  ]
end

def build_auto_method_candidates(ast, decls, entry, qt_class, int_cast_types)
  decls.filter_map do |decl|
    next unless auto_method_decl_candidate?(decl)

    build_auto_method_candidate(ast, decl, entry, qt_class, int_cast_types)
  end
end

def filter_auto_method_candidates(candidates, entry)
  filtered = candidates

  if entry[:param_count]
    filtered = filtered.select { |candidate| candidate[:method][:args].length == entry[:param_count] }
  end

  if entry[:param_types]
    expected = entry[:param_types].map { |type_name| normalized_cpp_type_name(type_name) }
    filtered = filtered.select { |candidate| candidate[:param_types] == expected }
  end

  filtered
end

def resolve_auto_method_entry(auto_entry)
  auto_entry.is_a?(String) ? { qt_name: auto_entry } : auto_entry.dup
end

def resolve_auto_method_cached(cache, cache_key)
  return [false, nil] unless cache.key?(cache_key)

  [true, cache[cache_key]]
end

def resolve_auto_method_cache(ast)
  @resolve_auto_method_cache ||= {}.compare_by_identity
  @resolve_auto_method_cache[ast] ||= {}
end

def cached_auto_method(per_ast_cache, qt_class, entry)
  cache_key = resolve_auto_method_cache_key(qt_class, entry)
  cache_hit, cached = resolve_auto_method_cached(per_ast_cache, cache_key)
  [cache_key, cache_hit, cached]
end

def resolve_auto_method_built_candidates(ast, qt_class, entry)
  decls = collect_method_decls_with_bases(ast, qt_class, entry.fetch(:qt_name))
  return nil if decls.empty?

  int_cast_types = ast_int_cast_type_set(ast)
  built = build_auto_method_candidates(ast, decls, entry, qt_class, int_cast_types)
  return nil if built.empty?

  built = filter_auto_method_candidates(built, entry)
  return nil if built.empty?

  built
end

def resolve_auto_method(ast, qt_class, auto_entry)
  entry = resolve_auto_method_entry(auto_entry)
  per_ast_cache = resolve_auto_method_cache(ast)
  cache_key, cache_hit, cached = cached_auto_method(per_ast_cache, qt_class, entry)
  return cached if cache_hit

  built = resolve_auto_method_built_candidates(ast, qt_class, entry)
  return per_ast_cache[cache_key] = nil unless built

  per_ast_cache[cache_key] = built.min_by { |candidate| candidate[:method][:args].length }[:method]
end

def auto_entries_for_spec(spec, ast)
  auto_mode = spec[:auto_methods]
  return Array(auto_mode) unless auto_mode == :all

  names = collect_method_names_with_bases(ast, spec[:qt_class]).select { |name| auto_exportable_method_name?(name) }
  rules = spec.fetch(:auto_method_rules, {})
  names.sort.map do |name|
    rule = rules[name.to_sym] || rules[name]
    rule ? { qt_name: name }.merge(rule) : { qt_name: name }
  end
end

def resolve_auto_methods_for_spec(ast, spec, auto_entries, manual_methods, auto_mode)
  resolver = build_auto_method_resolver(ast, spec, manual_methods, auto_mode)
  spec_resolved = 0
  spec_skipped = 0
  auto_methods = auto_entries.filter_map do |entry|
    method, spec_skipped, spec_resolved = resolve_with_resolver(resolver, entry, spec_skipped, spec_resolved)
    method
  end

  [auto_methods, spec_resolved, spec_skipped]
end

def build_auto_method_resolver(ast, spec, manual_methods, auto_mode)
  existing_names = manual_methods.to_set { |method| method[:qt_name] }
  resolve_method = ->(entry) { resolve_auto_method(ast, spec[:qt_class], entry) }
  AutoMethodSpecResolver.new(
    spec: spec,
    auto_mode: auto_mode,
    existing_names: existing_names,
    resolve_method: resolve_method
  )
end

def resolve_with_resolver(resolver, entry, spec_skipped, spec_resolved)
  resolver.resolve(entry, skipped: spec_skipped, resolved: spec_resolved)
end

def expand_auto_methods(specs, ast)
  totals = { candidates: 0, resolved: 0, skipped: 0 }

  expanded_specs = specs.map do |spec|
    expand_auto_methods_for_spec(spec, ast, totals)
  end
  debug_log("auto totals candidates=#{totals[:candidates]} resolved=#{totals[:resolved]} skipped=#{totals[:skipped]}")
  expanded_specs
end

def expand_auto_methods_for_spec(spec, ast, totals)
  spec_start = monotonic_now
  auto_mode = spec[:auto_methods]
  auto_entries = auto_entries_for_spec(spec, ast)
  manual_methods = Array(spec[:methods])
  return spec if auto_entries.empty?

  auto_result = resolve_spec_auto_methods(ast, spec, auto_entries, manual_methods, auto_mode)
  apply_auto_method_result!(totals, spec, auto_mode, spec_start, auto_result)
  spec.merge(methods: manual_methods + auto_result[:methods])
end

def resolve_spec_auto_methods(ast, spec, auto_entries, manual_methods, auto_mode)
  auto_methods, spec_resolved, spec_skipped = resolve_auto_methods_for_spec(
    ast, spec, auto_entries, manual_methods, auto_mode
  )
  { methods: auto_methods, candidates: auto_entries.length, resolved: spec_resolved, skipped: spec_skipped }
end

def update_auto_method_totals!(totals, spec_candidates, spec_resolved, spec_skipped)
  totals[:candidates] += spec_candidates
  totals[:resolved] += spec_resolved
  totals[:skipped] += spec_skipped
end

def apply_auto_method_result!(totals, spec, auto_mode, spec_start, auto_result)
  update_auto_method_totals!(
    totals, auto_result[:candidates], auto_result[:resolved], auto_result[:skipped]
  )
  log_auto_method_expansion(spec: spec, auto_mode: auto_mode, counts: auto_result, spec_start: spec_start)
end

def log_auto_method_expansion(spec:, auto_mode:, counts:, spec_start:)
  elapsed = monotonic_now - spec_start
  message = "auto #{spec[:qt_class]} mode=#{auto_mode || :list} " \
            "candidates=#{counts[:candidates]} resolved=#{counts[:resolved]} " \
            "skipped=#{counts[:skipped]} #{format('%.3fs', elapsed)}"
  debug_log(
    message
  )
end

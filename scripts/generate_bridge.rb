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

def debug_enabled?
  ENV['QT_RUBY_GENERATOR_DEBUG'] == '1'
end

def monotonic_now
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

def debug_log(message)
  puts "[gen] #{message}" if debug_enabled?
end

def timed(label)
  start = monotonic_now
  value = yield
  elapsed = monotonic_now - start
  debug_log("#{label}=#{format('%.3fs', elapsed)}")
  value
end

def required_includes(scope)
  case scope
  when 'widgets'
    ['QApplication', 'QtWidgets']
  else
    raise "Unsupported QT_RUBY_SCOPE=#{scope.inspect}. Supported: #{SUPPORTED_SCOPES.join(', ')}"
  end
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

def prefix_for_qt_class(qt_class)
  core = qt_class.delete_prefix('Q')
  "q#{to_snake(core)}"
end

def ruby_safe_method_name(name)
  RUBY_RESERVED_WORDS.include?(name) ? "#{name}_" : name
end

def ruby_public_method_name(qt_name, explicit_name = nil)
  base = explicit_name || qt_name
  safe = ruby_safe_method_name(base)
  return safe unless RUNTIME_RESERVED_RUBY_METHODS.include?(safe)

  RUNTIME_METHOD_RENAMES.fetch(safe, "#{safe}_qt")
end

def ruby_safe_arg_name(name, index, used)
  base = name.to_s
  base = "arg#{index + 1}" unless base.match?(/\A[A-Za-z_]\w*\z/)
  base = "#{base}_arg" if RUBY_RESERVED_WORDS.include?(base)

  candidate = base
  counter = 2
  while used.include?(candidate)
    candidate = "#{base}_#{counter}"
    counter += 1
  end
  used << candidate
  candidate
end

def ruby_arg_name_map(args)
  used = Set.new
  args.each_with_index.to_h { |arg, idx| [arg[:name], ruby_safe_arg_name(arg[:name], idx, used)] }
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
  cflags = timed('pkg_config_cflags') { pkg_config_cflags }

  Tempfile.create(['qt_ruby_probe', '.cpp']) do |file|
    required_includes(GENERATOR_SCOPE).each { |inc| file.write("#include <#{inc}>\n") }
    file.flush

    cmd = "clang++ -std=c++17 -x c++ -Xclang -ast-dump=json -fsyntax-only #{cflags} #{file.path}"
    out = timed('clang_ast_dump') { `#{cmd}` }
    raise "clang AST dump failed: #{cmd}" unless $?.success?

    timed('ast_json_parse') { JSON.parse(out, max_nesting: false) }
  end
end

def walk_ast(node, &)
  return unless node.is_a?(Hash)

  yield node
  Array(node['inner']).each { |child| walk_ast(child, &) }
end

def walk_ast_scoped(node, scope = [], &)
  return unless node.is_a?(Hash)

  local_scope = scope
  name = node['name']
  if name && !name.empty? && %w[NamespaceDecl CXXRecordDecl].include?(node['kind'])
    local_scope = scope + [name]
  end

  yield node, local_scope
  Array(node['inner']).each { |child| walk_ast_scoped(child, local_scope, &) }
end

def ast_append_int_cast_type!(types, integer_alias_pattern, node, qualified)
  case node['kind']
  when 'EnumDecl'
    types << qualified
  when 'TypedefDecl', 'TypeAliasDecl'
    aliased = node.dig('type', 'qualType').to_s.strip
    return if aliased.empty?

    types << qualified if aliased.match?(integer_alias_pattern)
    types << qualified if aliased.include?('QFlags<')
  end
end

def ast_int_cast_type_set(ast)
  @ast_int_cast_type_set_cache ||= {}
  cached = @ast_int_cast_type_set_cache[ast.object_id]
  return cached if cached

  types = Set.new
  integer_alias_pattern = /\A(?:unsigned\s+|signed\s+)?(?:char|short|int|long|long long)\z/

  walk_ast_scoped(ast) do |node, scope|
    name = node['name']
    next if name.nil? || name.empty?

    qualified = (scope + [name]).join('::')
    ast_append_int_cast_type!(types, integer_alias_pattern, node, qualified)
  end

  @ast_int_cast_type_set_cache[ast.object_id] = types
end

def collect_class_api(ast, class_name)
  index = ast_class_index(ast)
  methods = index[:methods_by_class].fetch(class_name, {}).keys
  ctors = index[:ctors_by_class].fetch(class_name, [])
  { methods: methods, constructors: ctors }
end

def ast_record_base_classes(node, class_name, bases_by_class)
  Array(node['bases']).each do |base|
    type_info = base['type'] || {}
    raw = type_info['desugaredQualType'] || type_info['qualType']
    parsed_base = normalize_cpp_type_name(raw)
    bases_by_class[class_name] << parsed_base if parsed_base && !parsed_base.empty?
  end
end

def ast_record_class_members(node, class_name, methods_by_class, ctors_by_class, ctor_decls_by_class)
  current_access = node['tagUsed'] == 'struct' ? 'public' : 'private'
  method_decl_count = 0
  ctor_decl_count = 0

  Array(node['inner']).each do |inner|
    if inner['kind'] == 'AccessSpecDecl'
      current_access = inner['access'] if inner['access']
      next
    end

    if ast_record_method_member?(inner, class_name, current_access, methods_by_class)
      method_decl_count += 1
      next
    end

    ctor_decl_count += 1 if ast_record_constructor_member?(inner, class_name, current_access, ctors_by_class, ctor_decls_by_class)
  end

  [method_decl_count, ctor_decl_count]
end

def ast_record_method_member?(inner, class_name, current_access, methods_by_class)
  return false unless inner['kind'] == 'CXXMethodDecl' && inner['name']

  access = inner['access'] || current_access
  methods_by_class[class_name][inner['name']] << inner.merge('__effective_access' => access)
  true
end

def ast_record_constructor_member?(inner, class_name, current_access, ctors_by_class, ctor_decls_by_class)
  return false unless inner['kind'] == 'CXXConstructorDecl' && inner['name']

  ctors_by_class[class_name] << inner['name']
  ctor_decls_by_class[class_name] << inner.merge('__effective_access' => current_access)
  true
end

def init_ast_class_index_data
  {
    methods_by_class: Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = [] } },
    bases_by_class: Hash.new { |h, k| h[k] = [] },
    ctors_by_class: Hash.new { |h, k| h[k] = [] },
    ctor_decls_by_class: Hash.new { |h, k| h[k] = [] },
    abstract_by_class: Hash.new(false),
    method_decl_count: 0,
    ctor_decl_count: 0
  }
end

def ast_index_track_record_decl(node, data)
  class_name = node['name']
  return if class_name.nil? || class_name.empty?

  data[:abstract_by_class][class_name] ||= node.dig('definitionData', 'isAbstract') == true
  ast_record_base_classes(node, class_name, data[:bases_by_class])
  method_count, ctor_count = ast_record_class_members(
    node, class_name, data[:methods_by_class], data[:ctors_by_class], data[:ctor_decls_by_class]
  )
  data[:method_decl_count] += method_count
  data[:ctor_decl_count] += ctor_count
end

def finalize_ast_class_index!(data)
  data[:bases_by_class].each_value(&:uniq!)
  data[:ctors_by_class].each_value(&:uniq!)
  debug_log("ast_class_index classes=#{data[:methods_by_class].length} method_decls=#{data[:method_decl_count]}")
  debug_log("ast_class_index ctor_decls=#{data[:ctor_decl_count]}")
  data.slice(:methods_by_class, :bases_by_class, :ctors_by_class, :ctor_decls_by_class, :abstract_by_class)
end

def ast_class_index(ast)
  @ast_class_index_cache ||= {}
  cached = @ast_class_index_cache[ast.object_id]
  return cached if cached

  data = init_ast_class_index_data

  timed('ast_class_index_build') do
    walk_ast(ast) do |node|
      next unless node['kind'] == 'CXXRecordDecl'

      ast_index_track_record_decl(node, data)
    end
  end

  @ast_class_index_cache[ast.object_id] = finalize_ast_class_index!(data)
end

def collect_method_decls(ast, class_name, method_name)
  index = ast_class_index(ast)
  index[:methods_by_class].dig(class_name, method_name) || []
end

def collect_method_decls_with_bases(ast, class_name, method_name, visited = {})
  return [] if class_name.nil? || class_name.empty? || visited[class_name]

  visited[class_name] = true
  own = collect_method_decls(ast, class_name, method_name)
  return own unless own.empty?

  all = []

  bases = collect_class_bases(ast, class_name)
  bases.each do |base|
    all.concat(collect_method_decls_with_bases(ast, base, method_name, visited))
  end

  all
end

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

def map_cpp_intlike_arg_type(type_name, qt_class, int_cast_types)
  return { ffi: :int } if type_name == 'int'
  return { ffi: :int, cast: 'bool' } if type_name == 'bool'
  return { ffi: :int, cast: type_name } if type_name.include?('::') && int_cast_types&.include?(type_name)

  return nil unless qt_class && type_name.match?(/\A[A-Z]\w*\z/)

  qualified = "#{qt_class}::#{type_name}"
  return { ffi: :int, cast: qualified } if int_cast_types&.include?(qualified)

  nil
end

def map_cpp_arg_type(type_name, qt_class: nil, int_cast_types: nil)
  raw = type_name.to_s.strip
  return nil if raw.end_with?('&') && !raw.start_with?('const ')

  type = raw
  type = type.sub(/\Aconst\s+/, '').sub(/\s*&\z/, '').strip
  return nil if unsupported_cpp_type?(type)
  return { ffi: :string, cast: :qstring } if type == 'QString'

  map_cpp_pointer_arg_type(type, qt_class) || map_cpp_intlike_arg_type(type, qt_class, int_cast_types)
end

def normalized_cpp_type_name(type_name)
  type = type_name.to_s.strip
  type = type.sub(/\Aconst\s+/, '').sub(/\s*&\z/, '').strip
  type = type.sub(/\s*\*\z/, '*') if type.end_with?('*')
  type
end

def map_cpp_return_type(type_name)
  raw = type_name.to_s.strip
  return nil if raw.include?('<') || raw.include?('>') || raw.include?('[') || raw.include?('(')
  return nil if raw.start_with?('const ') && raw.end_with?('*')

  type = raw.sub(/\Aconst\s+/, '').sub(/\s*&\z/, '').strip

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
  required_arg_count = params.count { |param| param['init'].nil? }
  {
    return_type: ret,
    required_arg_count: required_arg_count,
    params: params.each_with_index.map do |param, idx|
      { name: (param['name'] || "arg#{idx + 1}"), type: param.dig('type', 'qualType').to_s, has_default: !param['init'].nil? }
    end
  }
end

def build_auto_method_args(parsed, entry, qt_class, int_cast_types)
  arg_cast_overrides = Array(entry[:arg_casts])
  parsed[:params].each_with_index.map do |param, idx|
    cast_override = arg_cast_overrides[idx]
    arg_info = map_cpp_arg_type(param[:type], qt_class: qt_class, int_cast_types: int_cast_types)
    arg_info ||= { ffi: :int } if cast_override
    return nil unless arg_info

    arg_hash = { name: param[:name], ffi: arg_info[:ffi] }
    cast = cast_override || arg_info[:cast]
    arg_hash[:cast] = cast if cast
    arg_hash
  end
end

def build_auto_method_hash(entry, ret_info, args, parsed)
  method = {
    qt_name: entry[:qt_name],
    ruby_name: ruby_public_method_name(entry[:qt_name], entry[:ruby_name]),
    ffi_return: ret_info[:ffi_return],
    args: args,
    required_arg_count: parsed[:required_arg_count]
  }
  method[:return_cast] = ret_info[:return_cast] if ret_info[:return_cast]
  method
end

def build_auto_method_from_decl(method_decl, entry, qt_class:, int_cast_types:)
  parsed = parse_method_signature(method_decl)
  return nil unless parsed

  ret_info = map_cpp_return_type(parsed[:return_type])
  return nil unless ret_info

  args = build_auto_method_args(parsed, entry, qt_class, int_cast_types)
  return nil unless args

  build_auto_method_hash(entry, ret_info, args, parsed)
end

def auto_exportable_method_name?(name)
  return false if name.nil? || name.empty?
  return false if name.start_with?('~')
  return false if name.include?('operator')
  return false unless name.match?(/\A[A-Za-z_]\w*\z/)
  return false if name.end_with?('Event')
  return false if %w[event eventFilter childEvent customEvent timerEvent connectNotify disconnectNotify d_func connect disconnect].include?(name)

  true
end

def deprecated_method_decl?(decl)
  Array(decl['inner']).any? { |node| node['kind'] == 'DeprecatedAttr' }
end

def collect_method_names_with_bases(ast, class_name, visited = {})
  @method_names_with_bases_cache ||= {}
  cache_key = [ast.object_id, class_name]
  cached = @method_names_with_bases_cache[cache_key]
  return cached if cached

  return [] if class_name.nil? || class_name.empty? || visited[class_name]

  visited[class_name] = true
  index = ast_class_index(ast)
  own_names = index[:methods_by_class].fetch(class_name, {}).keys
  base_names = collect_class_bases(ast, class_name).flat_map do |base|
    collect_method_names_with_bases(ast, base, visited)
  end

  combined = (own_names + base_names).uniq
  @method_names_with_bases_cache[cache_key] = combined
  combined
end

def resolve_auto_method_cache_key(ast, qt_class, entry)
  [
    ast.object_id,
    qt_class,
    entry[:qt_name],
    entry[:ruby_name],
    entry[:param_count],
    Array(entry[:param_types]).map { |t| normalized_cpp_type_name(t) },
    Array(entry[:arg_casts])
  ]
end

def build_auto_method_candidates(decls, entry, qt_class, int_cast_types)
  decls.filter_map do |decl|
    next unless decl['__effective_access'] == 'public'
    next if deprecated_method_decl?(decl)
    next unless auto_exportable_method_name?(decl['name'])

    parsed = parse_method_signature(decl)
    next unless parsed

    method = build_auto_method_from_decl(decl, entry, qt_class: qt_class, int_cast_types: int_cast_types)
    next unless method

    {
      method: method,
      param_types: parsed[:params].map { |param| normalized_cpp_type_name(param[:type]) }
    }
  end
end

def filter_auto_method_candidates(candidates, entry)
  filtered = candidates

  if entry[:param_count]
    filtered = filtered.select { |candidate| candidate[:method][:args].length == entry[:param_count] }
  end

  if entry[:param_types]
    expected = entry[:param_types].map { |t| normalized_cpp_type_name(t) }
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

def resolve_auto_method_built_candidates(ast, qt_class, entry)
  decls = collect_method_decls_with_bases(ast, qt_class, entry.fetch(:qt_name))
  return nil if decls.empty?

  int_cast_types = ast_int_cast_type_set(ast)
  built = build_auto_method_candidates(decls, entry, qt_class, int_cast_types)
  return nil if built.empty?

  built = filter_auto_method_candidates(built, entry)
  return nil if built.empty?

  built
end

def resolve_auto_method(ast, qt_class, auto_entry)
  @resolve_auto_method_cache ||= {}
  entry = resolve_auto_method_entry(auto_entry)
  cache_key = resolve_auto_method_cache_key(ast, qt_class, entry)
  cache_hit, cached = resolve_auto_method_cached(@resolve_auto_method_cache, cache_key)
  return cached if cache_hit

  built = resolve_auto_method_built_candidates(ast, qt_class, entry)
  return @resolve_auto_method_cache[cache_key] = nil unless built

  @resolve_auto_method_cache[cache_key] = built.min_by { |candidate| candidate[:method][:args].length }[:method]
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
  existing_names = manual_methods.to_set { |m| m[:qt_name] }
  spec_resolved = 0
  spec_skipped = 0

  auto_methods = auto_entries.filter_map do |entry|
    qt_name = entry.is_a?(String) ? entry : entry[:qt_name]
    if existing_names.include?(qt_name)
      spec_skipped += 1
      next
    end

    resolved = resolve_auto_method(ast, spec[:qt_class], entry)
    if resolved.nil?
      if auto_mode == :all
        spec_skipped += 1
        next
      end

      raise "Failed to auto-resolve #{spec[:qt_class]}##{qt_name}"
    end

    spec_resolved += 1
    resolved
  end

  [auto_methods, spec_resolved, spec_skipped]
end

def expand_auto_methods(specs, ast)
  totals = { candidates: 0, resolved: 0, skipped: 0 }

  specs.map do |spec|
    expand_auto_methods_for_spec(spec, ast, totals)
  end.tap do
    debug_log("auto totals candidates=#{totals[:candidates]} resolved=#{totals[:resolved]} skipped=#{totals[:skipped]}")
  end
end

def expand_auto_methods_for_spec(spec, ast, totals)
  spec_start = monotonic_now
  auto_mode = spec[:auto_methods]
  auto_entries = auto_entries_for_spec(spec, ast)
  manual_methods = Array(spec[:methods])
  return spec if auto_entries.empty?

  spec_candidates = auto_entries.length
  auto_methods, spec_resolved, spec_skipped = resolve_auto_methods_for_spec(ast, spec, auto_entries, manual_methods, auto_mode)
  totals[:candidates] += spec_candidates
  totals[:resolved] += spec_resolved
  totals[:skipped] += spec_skipped
  elapsed = monotonic_now - spec_start
  debug_log("auto #{spec[:qt_class]} mode=#{auto_mode || :list} candidates=#{spec_candidates} resolved=#{spec_resolved} skipped=#{spec_skipped} #{format('%.3fs', elapsed)}")

  spec.merge(methods: manual_methods + auto_methods)
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

def collect_constructor_decls(ast, class_name)
  index = ast_class_index(ast)
  Array(index[:ctor_decls_by_class][class_name])
end

def abstract_class?(ast, class_name)
  index = ast_class_index(ast)
  index[:abstract_by_class][class_name] == true
end

def class_inherits?(ast, class_name, ancestor, visited = {})
  return false if class_name.nil? || class_name.empty? || visited[class_name]
  return true if class_name == ancestor

  visited[class_name] = true
  collect_class_bases(ast, class_name).any? { |base| class_inherits?(ast, base, ancestor, visited) }
end

def constructor_supports_parent_only?(decl)
  return false unless decl['__effective_access'] == 'public'

  parsed = parse_method_signature(decl)
  return false unless parsed

  params = parsed[:params]
  return false if params.empty?

  first_type = normalized_cpp_type_name(params.first[:type])
  return false unless first_type == 'QWidget*'

  params.drop(1).all? { |param| param[:has_default] }
end

def constructor_supports_no_args?(decl)
  return false unless decl['__effective_access'] == 'public'

  parsed = parse_method_signature(decl)
  return false unless parsed

  parsed[:required_arg_count].zero?
end

def discover_target_qt_classes(ast, scope)
  index = ast_class_index(ast)
  all_classes = index[:methods_by_class].keys.select { |name| name.start_with?('Q') }.uniq

  case scope
  when 'widgets'
    all_classes.select do |qt_class|
      next false unless widget_target_qt_class?(ast, qt_class)

      constructor_usable_for_codegen?(ast, qt_class)
    end.sort
  else
    raise "Unsupported QT_RUBY_SCOPE=#{scope.inspect}. Supported: #{SUPPORTED_SCOPES.join(', ')}"
  end
end

def widget_target_qt_class?(ast, qt_class)
  return false if qt_class.end_with?('Private')
  return false if qt_class == 'QApplication'
  return false if abstract_class?(ast, qt_class)

  class_inherits?(ast, qt_class, 'QWidget') ||
    class_inherits?(ast, qt_class, 'QLayout') ||
    qt_class == 'QTableWidgetItem'
end

def constructor_usable_for_codegen?(ast, qt_class)
  ctor_decls = collect_constructor_decls(ast, qt_class)
  ctor_decls.any? { |decl| constructor_supports_parent_only?(decl) || constructor_supports_no_args?(decl) }
end

def build_base_specs(ast)
  specs = [QAPPLICATION_SPEC.dup]
  target_qt_classes = discover_target_qt_classes(ast, GENERATOR_SCOPE)
  debug_log("target_classes scope=#{GENERATOR_SCOPE} count=#{target_qt_classes.length}")

  target_qt_classes.each do |qt_class|
    ctor_decls = collect_constructor_decls(ast, qt_class)
    supports_parent = ctor_decls.any? { |decl| constructor_supports_parent_only?(decl) }
    parent_ctor = supports_parent
    widget_child = qt_class != 'QWidget' && class_inherits?(ast, qt_class, 'QWidget')

    specs << {
      qt_class: qt_class,
      ruby_class: qt_class,
      include: qt_class,
      prefix: prefix_for_qt_class(qt_class),
      constructor: parent_ctor ? { parent: true, parent_type: 'QWidget*', register_in_parent: widget_child } : { parent: false },
      methods: [],
      auto_methods: :all,
      validate: { constructors: [qt_class], methods: [] }
    }
  end

  specs
end

def class_has_method?(ast, class_name, method_name)
  collect_class_api(ast, class_name)[:methods].include?(method_name)
end

def trace_generated_super_chain(fetch_bases, known_qt, qt_class, super_qt_by_qt)
  return if qt_class == 'QApplication'

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
  return unless method[:args].length == 1

  property = property_name_from_setter(method[:qt_name])
  return unless property
  return unless class_has_method?(ast, spec[:qt_class], property)

  existing_getter = methods.find { |m| m[:qt_name] == property && m[:args].empty? }
  if existing_getter
    existing_getter[:property] ||= property
    return
  end

  getter_decl = find_getter_decl(ast, spec[:qt_class], property)
  return unless getter_decl

  getter = build_property_getter_method(getter_decl, property)
  methods << getter if getter
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
  lines << "extern \"C\" void* #{name}(void* parent_handle) {"
  lines << "  #{spec[:constructor][:parent_type].delete('*')}* parent = static_cast<#{spec[:constructor][:parent_type]}>(parent_handle);"
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
  when :void
    '    return;'
  when :int
    '    return -1;'
  when :pointer, :string
    '    return nullptr;'
  else
    '    return;'
  end
end

def emit_cpp_method_return(lines, method, invocation)
  if method[:ffi_return] == :void
    lines << "  #{invocation};"
    return
  end

  if method[:ffi_return] == :string && method[:return_cast] == :qstring_to_utf8
    lines << "  const QString value = #{invocation};"
    lines << '  thread_local QByteArray utf8;'
    lines << '  utf8 = value.toUtf8();'
    lines << '  return utf8.constData();'
    return
  end

  if method[:ffi_return] == :pointer
    lines << "  return const_cast<void*>(static_cast<const void*>(#{invocation}));"
    return
  end

  lines << "  return #{invocation};"
end

def generate_cpp_method(lines, spec, method)
  fn = method_function_name(spec, method)
  ret = ffi_return_to_cpp(method[:ffi_return])
  sig = cpp_method_signature(method)

  lines << "extern \"C\" #{ret} #{fn}(#{sig.join(', ')}) {"
  lines << '  if (!handle) {'
  lines << cpp_null_handle_return(method)
  lines << '  }'
  lines << ''
  lines << "  auto* self_obj = static_cast<#{spec[:qt_class]}*>(handle);"

  call_args = method[:args].map { |arg| arg_expr(arg) }.join(', ')
  invocation = "self_obj->#{method[:qt_name]}(#{call_args})"
  emit_cpp_method_return(lines, method, invocation)
  lines << '}'
end

def generate_cpp_bridge(specs)
  lines = required_includes(GENERATOR_SCOPE).map { |inc| "#include <#{inc}>" }
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
  inherited_methods = inherited_methods_for_spec(spec, specs_by_qt, super_qt_by_qt)
  all_methods = (inherited_methods + spec[:methods]).uniq { |m| m[:qt_name] }
  metadata = ruby_api_metadata(all_methods)

  super_qt = super_qt_by_qt[spec[:qt_class]]
  super_ruby = super_qt ? qt_to_ruby[super_qt] : nil
  widget_root = spec[:ruby_class] == 'QWidget'
  widget_based = spec[:qt_class] != 'QWidget' && widget_based_qt_class?(spec[:qt_class], super_qt_by_qt)

  generate_ruby_widget_class_header(lines, spec, metadata: metadata, super_ruby: super_ruby, widget_root: widget_root)
  append_widget_initializer(lines, spec: spec, widget_root: widget_root, indent: '    ')
  lines << ''
  append_ruby_widget_methods(lines, spec)

  lines << '  end'
  lines << ''
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

    spec = specs_by_qt[qt_class]
    if spec
      generate_ruby_widget_class(lines, spec, specs_by_qt, super_qt_by_qt, qt_to_ruby)
    else
      generate_ruby_wrapper_class(lines, qt_class, super_qt ? qt_to_ruby[super_qt] : nil)
    end

    emitted[qt_class] = true
  end
  qts_to_emit.sort.each { |qt_class| emit_qt.call(qt_class) }
end

def generate_ruby_widgets(specs, super_qt_by_qt, wrapper_qt_classes)
  lines = []
  lines << '# frozen_string_literal: true'
  lines << ''
  lines << 'module Qt'

  qapplication_spec = specs.find { |spec| spec[:ruby_class] == 'QApplication' }
  generate_ruby_qapplication(lines, qapplication_spec)

  specs_by_qt = specs.each_with_object({}) { |s, map| map[s[:qt_class]] = s }
  qt_to_ruby = build_qt_to_ruby_map(specs, wrapper_qt_classes)
  emitted_qts = qts_to_emit(specs, wrapper_qt_classes)
  emit_qt_classes(lines, emitted_qts, specs_by_qt, super_qt_by_qt, qt_to_ruby)

  lines << 'end'
  lines.join("\n") + "\n"
end

total_start = monotonic_now
ast = timed('ast_dump_total') { ast_dump }
base_specs = timed('build_base_specs') { build_base_specs(ast) }
timed('validate_qt_api') { validate_qt_api!(ast, base_specs) }
expanded_specs = timed('expand_auto_methods') { expand_auto_methods(base_specs, ast) }
effective_specs = timed('enrich_specs_with_properties') { enrich_specs_with_properties(expanded_specs, ast) }
super_qt_by_qt, wrapper_qt_classes = timed('build_generated_inheritance') { build_generated_inheritance(ast, effective_specs) }

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

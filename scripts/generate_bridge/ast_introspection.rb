# frozen_string_literal: true

# Collects enum/typedef names that should be cast as integers for FFI.
class IntCastTypeCollector
  INTEGER_ALIAS_PATTERN = /\A(?:unsigned\s+|signed\s+)?(?:char|short|int|long|long long)\z/

  def initialize(ast)
    @ast = ast
    @types = Set.new
  end

  def collect
    walk_ast_scoped(@ast) do |node, scope|
      name = node['name']
      next if name.nil? || name.empty?

      qualified = (scope + [name]).join('::')
      ast_append_int_cast_type!(@types, INTEGER_ALIAS_PATTERN, node, qualified)
    end
    @types
  end
end

# Records method/constructor declarations and effective access for a class AST node.
class AstClassMemberRecorder
  def initialize(class_name, methods_by_class, ctors_by_class, ctor_decls_by_class)
    @class_name = class_name
    @methods_by_class = methods_by_class
    @ctors_by_class = ctors_by_class
    @ctor_decls_by_class = ctor_decls_by_class
  end

  def record(node)
    current_access = node['tagUsed'] == 'struct' ? 'public' : 'private'
    method_decl_count = ctor_decl_count = 0
    Array(node['inner']).each do |inner|
      current_access, method_decl_count, ctor_decl_count = record_inner(
        inner, current_access, method_decl_count, ctor_decl_count
      )
    end
    [method_decl_count, ctor_decl_count]
  end

  private

  def record_inner(inner, current_access, method_decl_count, ctor_decl_count)
    return [inner['access'] || current_access, method_decl_count, ctor_decl_count] if inner['kind'] == 'AccessSpecDecl'
    return [current_access, method_decl_count + 1, ctor_decl_count] if record_method_member?(inner, current_access)
    return [current_access, method_decl_count, ctor_decl_count + 1] if record_constructor_member?(inner, current_access)

    [current_access, method_decl_count, ctor_decl_count]
  end

  def record_method_member?(inner, current_access)
    return false unless inner['kind'] == 'CXXMethodDecl' && inner['name']

    access = inner['access'] || current_access
    @methods_by_class[@class_name][inner['name']] << inner.merge('__effective_access' => access)
    true
  end

  def record_constructor_member?(inner, current_access)
    return false unless inner['kind'] == 'CXXConstructorDecl' && inner['name']

    @ctors_by_class[@class_name] << inner['name']
    @ctor_decls_by_class[@class_name] << inner.merge('__effective_access' => current_access)
    true
  end
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
    raise "clang AST dump failed: #{cmd}" unless Process.last_status.success?

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
  local_scope = scope + [name] if name && !name.empty? && %w[NamespaceDecl CXXRecordDecl].include?(node['kind'])

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
  @ast_int_cast_type_set_cache ||= {}.compare_by_identity
  return @ast_int_cast_type_set_cache[ast] if @ast_int_cast_type_set_cache.key?(ast)

  @ast_int_cast_type_set_cache[ast] = IntCastTypeCollector.new(ast).collect
end

def collect_class_api(ast, class_name)
  index = ast_class_index(ast)
  methods = index[:methods_by_class].fetch(class_name, {}).keys
  ctors = index[:ctors_by_class].fetch(class_name, [])
  { methods: methods, constructors: ctors }
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

def ast_record_base_classes(node, class_name, bases_by_class)
  Array(node['bases']).each do |base|
    type_info = base['type'] || {}
    raw = type_info['desugaredQualType'] || type_info['qualType']
    parsed_base = normalize_cpp_type_name(raw)
    bases_by_class[class_name] << parsed_base if parsed_base && !parsed_base.empty?
  end
end

def ast_record_class_members(node, class_name, methods_by_class, ctors_by_class, ctor_decls_by_class)
  AstClassMemberRecorder.new(
    class_name, methods_by_class, ctors_by_class, ctor_decls_by_class
  ).record(node)
end

def ast_class_index_method_collections
  {
    methods_by_class: Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = [] } },
    bases_by_class: Hash.new { |h, k| h[k] = [] }
  }
end

def ast_class_index_constructor_collections
  {
    ctors_by_class: Hash.new { |h, k| h[k] = [] },
    ctor_decls_by_class: Hash.new { |h, k| h[k] = [] },
    abstract_by_class: Hash.new(false)
  }
end

def ast_class_index_collections
  ast_class_index_method_collections.merge(ast_class_index_constructor_collections)
end

def init_ast_class_index_data
  ast_class_index_collections.merge(method_decl_count: 0, ctor_decl_count: 0)
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
  @ast_class_index_cache ||= {}.compare_by_identity
  return @ast_class_index_cache[ast] if @ast_class_index_cache.key?(ast)

  data = init_ast_class_index_data

  timed('ast_class_index_build') do
    walk_ast(ast) do |node|
      next unless node['kind'] == 'CXXRecordDecl'

      ast_index_track_record_decl(node, data)
    end
  end

  @ast_class_index_cache[ast] = finalize_ast_class_index!(data)
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

  collect_class_bases(ast, class_name).flat_map do |base|
    collect_method_decls_with_bases(ast, base, method_name, visited)
  end
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

def class_has_method?(ast, class_name, method_name)
  collect_class_api(ast, class_name)[:methods].include?(method_name)
end

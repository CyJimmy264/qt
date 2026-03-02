# frozen_string_literal: true

SCALAR_BRIDGED_QT_TYPES = Set.new(%w[QString QVariant QAnyStringView QByteArray QDateTime QDate QTime]).freeze

def constructor_supports_parent_only?(decl)
  return false unless decl['__effective_access'] == 'public'

  parsed = parse_method_signature(decl)
  return false unless parsed

  params = parsed[:params]
  return false if params.empty?

  first_type = normalized_cpp_type_name(params.first[:type])
  return false unless %w[QWidget* QObject*].include?(first_type)

  params.drop(1).all? { |param| param[:has_default] }
end

def parent_constructor_first_type(decl)
  return nil unless decl['__effective_access'] == 'public'

  parsed = parse_method_signature(decl)
  return nil unless parsed

  params = parsed[:params]
  return nil if params.empty?

  first_type = normalized_cpp_type_name(params.first[:type])
  return nil unless %w[QWidget* QObject*].include?(first_type)
  return nil unless params.drop(1).all? { |param| param[:has_default] }

  first_type
end

def constructor_supports_no_args?(decl)
  return false unless decl['__effective_access'] == 'public'

  parsed = parse_method_signature(decl)
  return false unless parsed

  parsed[:required_arg_count].zero?
end

def constructor_supports_string_path?(decl)
  return false unless decl['__effective_access'] == 'public'

  parsed = parse_method_signature(decl)
  return false unless parsed
  return false if parsed[:params].empty?
  return false unless parsed[:required_arg_count] <= 1

  constructor_string_like_type?(parsed[:params].first[:type])
end

def constructor_string_like_arg_cast(raw_type)
  compact = raw_type.to_s.gsub(/\s+/, ' ').strip
  normalized = normalized_cpp_type_name(raw_type)
  return :qstring if normalized == 'QString'
  return :qany_string_view if normalized == 'QAnyStringView'
  return :cstr if compact.match?(/\A(?:const\s+)?char\s*\*\z/)

  nil
end

def constructor_string_like_type?(raw_type)
  !constructor_string_like_arg_cast(raw_type).nil?
end

def template_qt_classes(ast)
  @template_qt_classes_cache ||= {}.compare_by_identity
  return @template_qt_classes_cache[ast] if @template_qt_classes_cache.key?(ast)

  @template_qt_classes_cache[ast] = build_template_qt_classes(ast)
end

def build_template_qt_classes(ast)
  set = Set.new
  timed('discover_template_qt_classes') do
    walk_ast(ast) do |node|
      next unless node['kind'] == 'ClassTemplateDecl'

      name = node['name']
      set << name if name&.start_with?('Q')
    end
  end

  debug_log("template_qt_classes count=#{set.length}")
  set
end

def q_class_names(ast)
  ast_class_index(ast)[:methods_by_class].keys.select { |name| name.start_with?('Q') }.uniq
end

def class_matches_scope?(ast, qt_class, scope)
  case scope
  when 'widgets' then widget_target_qt_class?(ast, qt_class)
  when 'qobject' then qobject_target_qt_class?(ast, qt_class)
  when 'all' then all_scope_target_qt_class?(ast, qt_class)
  else
    raise "Unsupported QT_RUBY_SCOPE=#{scope.inspect}. Supported: #{SUPPORTED_SCOPES.join(', ')}"
  end
end

def all_scope_target_qt_class?(ast, qt_class)
  widget_target_qt_class?(ast, qt_class) || qobject_target_qt_class?(ast, qt_class)
end

def discover_target_for_scope(ast, scope, all_classes, template_classes)
  all_classes.select do |qt_class|
    next false if template_classes.include?(qt_class)
    next false unless class_matches_scope?(ast, qt_class, scope)

    constructor_usable_for_codegen?(ast, qt_class)
  end.sort
end

def discover_related_value_classes(ast, seed_classes, all_classes, template_classes)
  discovered = seed_classes.to_set
  queue = seed_classes.dup

  until queue.empty?
    klass = queue.shift
    related_qt_type_names(ast, klass).each do |candidate|
      next if discovered.include?(candidate)
      next unless related_value_class_candidate?(ast, candidate, all_classes, template_classes)

      discovered << candidate
      queue << candidate
    end
  end

  discovered.to_a
end

def related_value_class_candidate?(ast, qt_class, all_classes, template_classes)
  return false if SCALAR_BRIDGED_QT_TYPES.include?(qt_class)
  return false unless all_classes.include?(qt_class)
  return false if template_classes.include?(qt_class)
  return false if qt_class.end_with?('Private')
  return false if qt_class == 'QApplication'
  return false if abstract_class?(ast, qt_class)
  return false if class_inherits?(ast, qt_class, 'QObject')

  constructor_usable_for_codegen?(ast, qt_class)
end

def related_qt_type_names(ast, qt_class)
  index = ast_class_index(ast)
  decls = index[:methods_by_class].fetch(qt_class, {}).values.flatten
  decls.each_with_object(Set.new) do |decl, out|
    next unless decl['__effective_access'] == 'public'

    parsed = parse_method_signature(decl)
    next unless parsed

    append_related_qt_types_from_decl(out, parsed, decl['name'])
  end
end

def append_related_qt_types_from_decl(out, parsed, method_name)
  candidates = []
  candidates << normalized_cpp_type_name(parsed[:return_type]).to_s if parsed[:return_type]
  parsed[:params].each { |param| candidates << normalized_cpp_type_name(param[:type]).to_s }
  candidates.each do |candidate|
    next if candidate.empty? || !candidate.start_with?('Q')
    next unless related_type_name_matches_method?(candidate, method_name)

    out << candidate
  end
end

def related_type_name_matches_method?(qt_type, method_name)
  token = qt_type.delete_prefix('Q').downcase
  return false if token.empty?

  method_name.to_s.downcase.include?(token)
end

def discover_target_qt_classes(ast, scope)
  all_classes = q_class_names(ast)
  template_classes = template_qt_classes(ast)

  base_targets = timed("discover_target_qt_classes/#{scope}/base") do
    discover_target_for_scope(ast, scope, all_classes, template_classes)
  end

  targets = timed("discover_target_qt_classes/#{scope}/related") do
    discover_related_value_classes(ast, base_targets, all_classes, template_classes).sort
  end
  debug_log(
    "discover_target_qt_classes scope=#{scope} total_q=#{all_classes.length} " \
    "base=#{base_targets.length} targets=#{targets.length}"
  )
  targets
end

def widget_target_qt_class?(ast, qt_class)
  return false if qt_class.end_with?('Private')
  return false if qt_class == 'QApplication'
  return false if abstract_class?(ast, qt_class)

  class_inherits?(ast, qt_class, 'QWidget') ||
    class_inherits?(ast, qt_class, 'QLayout') ||
    qt_class == 'QTableWidgetItem'
end

def qobject_target_qt_class?(ast, qt_class)
  return false if qt_class.end_with?('Private')
  return false if qt_class == 'QApplication'
  return false if abstract_class?(ast, qt_class)
  return false unless class_inherits?(ast, qt_class, 'QObject')

  # qobject scope is additive stage after widgets: exclude widget/layout branch.
  return false if class_inherits?(ast, qt_class, 'QWidget')
  return false if class_inherits?(ast, qt_class, 'QLayout')

  true
end

def constructor_usable_for_codegen?(ast, qt_class)
  ctor_decls = collect_constructor_decls(ast, qt_class)
  ctor_decls.any? do |decl|
    constructor_supports_parent_only?(decl) ||
      constructor_supports_no_args?(decl) ||
      constructor_supports_string_path?(decl)
  end
end

def build_base_spec_for_qt_class(ast, qt_class)
  ctor_decls = collect_constructor_decls(ast, qt_class)
  parent_type = ctor_decls.filter_map { |decl| parent_constructor_first_type(decl) }.first
  string_path_cast = ctor_decls.filter_map do |decl|
    parsed = parse_method_signature(decl)
    next nil unless parsed && parsed[:params].first

    constructor_string_like_arg_cast(parsed[:params].first[:type])
  end.first
  widget_child = qt_class != 'QWidget' && class_inherits?(ast, qt_class, 'QWidget')
  parent_ctor =
    if parent_type
      parent_constructor_for_type(parent_type, widget_child)
    elsif string_path_cast
      string_path_constructor(string_path_cast)
    else
      { parent: false }
    end
  base_spec_hash(qt_class, parent_ctor)
end

def base_spec_hash(qt_class, parent_ctor)
  {
    qt_class: qt_class,
    ruby_class: qt_class,
    include: qt_class,
    prefix: prefix_for_qt_class(qt_class),
    constructor: parent_ctor,
    methods: [],
    auto_methods: :all,
    # Constructor availability is already filtered during discovery.
    # Keep validation lightweight for auto-discovered classes to avoid false negatives
    # on template/specialized constructor names in Clang AST.
    validate: { constructors: [], methods: [] }
  }
end

def parent_constructor_for_type(parent_type, widget_child)
  { parent: true, parent_type: parent_type, register_in_parent: widget_child }
end

def string_path_constructor(arg_cast)
  { parent: false, mode: :string_path, arg_cast: arg_cast }
end

def build_base_specs(ast)
  specs = [build_qapplication_spec(ast)]
  target_qt_classes = discover_target_qt_classes(ast, GENERATOR_SCOPE)
  debug_log("target_classes scope=#{GENERATOR_SCOPE} count=#{target_qt_classes.length}")

  target_qt_classes.each do |qt_class|
    specs << build_base_spec_for_qt_class(ast, qt_class)
  end

  specs
end

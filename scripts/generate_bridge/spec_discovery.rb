# frozen_string_literal: true

AUXILIARY_SCOPE_CLASSES = {
  'widgets' => %w[QIcon],
  'qobject' => [],
  'all' => %w[QIcon]
}.freeze

def auxiliary_scope_classes(scope)
  AUXILIARY_SCOPE_CLASSES.fetch(scope, [])
end

def auxiliary_scope_class?(qt_class, scope)
  auxiliary_scope_classes(scope).include?(qt_class)
end

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
  return true if auxiliary_scope_class?(qt_class, scope)

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

def discover_target_qt_classes(ast, scope)
  all_classes = q_class_names(ast)
  template_classes = template_qt_classes(ast)

  targets = timed("discover_target_qt_classes/#{scope}") do
    discover_target_for_scope(ast, scope, all_classes, template_classes)
  end
  debug_log("discover_target_qt_classes scope=#{scope} total_q=#{all_classes.length} targets=#{targets.length}")
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
  ctor_decls.any? { |decl| constructor_supports_parent_only?(decl) || constructor_supports_no_args?(decl) }
end

def build_base_spec_for_qt_class(ast, qt_class)
  ctor_decls = collect_constructor_decls(ast, qt_class)
  parent_type = ctor_decls.filter_map { |decl| parent_constructor_first_type(decl) }.first
  widget_child = qt_class != 'QWidget' && class_inherits?(ast, qt_class, 'QWidget')
  parent_ctor = parent_type ? parent_constructor_for_type(parent_type, widget_child) : { parent: false }
  parent_ctor = qicon_constructor if qt_class == 'QIcon'
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

def qicon_constructor
  { parent: false, mode: :string_path }
end

def build_base_specs(ast)
  specs = [QAPPLICATION_SPEC.dup]
  target_qt_classes = discover_target_qt_classes(ast, GENERATOR_SCOPE)
  debug_log("target_classes scope=#{GENERATOR_SCOPE} count=#{target_qt_classes.length}")

  target_qt_classes.each do |qt_class|
    specs << build_base_spec_for_qt_class(ast, qt_class)
  end

  specs
end

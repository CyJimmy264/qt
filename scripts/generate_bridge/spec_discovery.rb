# frozen_string_literal: true

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

def build_base_spec_for_qt_class(ast, qt_class)
  ctor_decls = collect_constructor_decls(ast, qt_class)
  supports_parent = ctor_decls.any? { |decl| constructor_supports_parent_only?(decl) }
  widget_child = qt_class != 'QWidget' && class_inherits?(ast, qt_class, 'QWidget')
  parent_ctor = supports_parent ? parent_constructor_for_widget(widget_child) : { parent: false }

  {
    qt_class: qt_class,
    ruby_class: qt_class,
    include: qt_class,
    prefix: prefix_for_qt_class(qt_class),
    constructor: parent_ctor,
    methods: [],
    auto_methods: :all,
    validate: { constructors: [qt_class], methods: [] }
  }
end

def parent_constructor_for_widget(widget_child)
  { parent: true, parent_type: 'QWidget*', register_in_parent: widget_child }
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

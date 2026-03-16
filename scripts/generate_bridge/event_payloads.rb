# frozen_string_literal: true

EVENT_PAYLOAD_CLASS_RULES = [
  { pattern: /\A(?:MouseButtonPress|MouseButtonRelease|MouseButtonDblClick|MouseMove|NonClientAreaMouseButtonPress|NonClientAreaMouseButtonRelease|NonClientAreaMouseButtonDblClick|NonClientAreaMouseMove)\z/, class_name: 'QMouseEvent' },
  { pattern: /\A(?:KeyPress|KeyRelease)\z/, class_name: 'QKeyEvent' },
  { pattern: /\AWheel\z/, class_name: 'QWheelEvent' },
  { pattern: /\AEnter\z/, class_name: 'QEnterEvent' },
  { pattern: /\AResize\z/, class_name: 'QResizeEvent' },
  { pattern: /\A(?:FocusIn|FocusOut|FocusAboutToChange)\z/, class_name: 'QFocusEvent' },
  { pattern: /\AMove\z/, class_name: 'QMoveEvent' },
  { pattern: /\AClose\z/, class_name: 'QCloseEvent' },
  { pattern: /\AShow\z/, class_name: 'QShowEvent' },
  { pattern: /\AHide\z/, class_name: 'QHideEvent' },
  { pattern: /\AContextMenu\z/, class_name: 'QContextMenuEvent' },
  { pattern: /\AHover(?:Enter|Move|Leave)\z/, class_name: 'QHoverEvent' },
  { pattern: /\ADragEnter\z/, class_name: 'QDragEnterEvent' },
  { pattern: /\ADragMove\z/, class_name: 'QDragMoveEvent' },
  { pattern: /\ADragLeave\z/, class_name: 'QDragLeaveEvent' },
  { pattern: /\ADrop\z/, class_name: 'QDropEvent' }
].freeze

EVENT_PAYLOAD_COMPATIBILITY_ALIASES = {
  'QMouseEvent' => { a: :x, b: :y, c: :button, d: :buttons },
  'QKeyEvent' => { a: :key, b: :modifiers, c: :is_auto_repeat, d: :count },
  'QResizeEvent' => { a: :width, b: :height, c: :old_width, d: :old_height },
  'QWheelEvent' => { a: :pixel_delta_y, b: :angle_delta_y, c: :buttons, d: nil }
}.freeze

EVENT_PAYLOAD_EXCLUDED_METHODS = %w[
  accepted clone ignore isAccepted registerEventType setAccepted spontaneous type
].freeze

EVENT_PAYLOAD_SUPPORTED_COMPLEX_TYPES = %w[QPoint QPointF QSize].freeze

def resolve_event_payload_class_name(event_name)
  rule = EVENT_PAYLOAD_CLASS_RULES.find { |entry| event_name.match?(entry[:pattern]) }
  rule && rule[:class_name]
end

def supported_event_payload_return?(return_type, int_cast_types)
  return true if event_payload_scalar_return?(return_type, int_cast_types)
  return true if EVENT_PAYLOAD_SUPPORTED_COMPLEX_TYPES.include?(normalized_cpp_type_name(return_type))

  false
end

def event_payload_scalar_return?(return_type, int_cast_types)
  raw = return_type.to_s.strip
  return true if %w[bool int QString double float].include?(normalized_cpp_type_name(raw))

  compact = raw.sub(/\Aconst\s+/, '').sub(/\s*&\z/, '').strip
  compact.include?('::') && int_cast_types.include?(compact)
end

def event_payload_method_decl(ast, class_name, method_name, int_cast_types)
  collect_method_decls_with_bases(ast, class_name, method_name).find do |decl|
    next false unless decl['__effective_access'] == 'public'
    next false if deprecated_method_decl?(decl)

    parsed = parse_method_signature(decl)
    next false unless parsed && parsed[:params].empty?
    next false if EVENT_PAYLOAD_EXCLUDED_METHODS.include?(method_name)

    supported_event_payload_return?(parsed[:return_type], int_cast_types)
  end
end

def event_payload_method_candidates(ast, class_name, int_cast_types)
  collect_method_names_with_bases(ast, class_name).sort.filter_map do |method_name|
    decl = event_payload_method_decl(ast, class_name, method_name, int_cast_types)
    next unless decl

    parsed = parse_method_signature(decl)
    { method_name: method_name, return_type: parsed[:return_type] }
  end
end

def event_payload_base_name(method_name, return_type)
  normalized = normalized_cpp_type_name(return_type)
  snake = to_snake(method_name)
  return '' if %w[QPoint QPointF].include?(normalized) && %w[position pos local_pos].include?(snake)
  return 'global_' if %w[QPoint QPointF].include?(normalized) && %w[global_position global_pos].include?(snake)
  return '' if normalized == 'QSize' && snake == 'size'
  return 'old_' if normalized == 'QSize' && snake == 'old_size'

  "#{snake}_"
end

def event_payload_fields_for_method(method_name, return_type, int_cast_types)
  normalized = normalized_cpp_type_name(return_type)
  base_name = event_payload_base_name(method_name, return_type)
  getter = "typed_event->#{method_name}()"

  case normalized
  when 'bool'
    [{ name: to_snake(method_name), cpp_expr: getter, json_type: :bool }]
  when 'int'
    [{ name: to_snake(method_name), cpp_expr: getter, json_type: :int }]
  when 'QString'
    [{ name: to_snake(method_name), cpp_expr: getter, json_type: :string }]
  when 'double', 'float'
    [{ name: to_snake(method_name), cpp_expr: getter, json_type: :float }]
  when 'QPoint'
    [
      { name: "#{base_name}x", cpp_expr: "#{getter}.x()", json_type: :int },
      { name: "#{base_name}y", cpp_expr: "#{getter}.y()", json_type: :int }
    ]
  when 'QPointF'
    [
      { name: "#{base_name}x", cpp_expr: "#{getter}.x()", json_type: :float },
      { name: "#{base_name}y", cpp_expr: "#{getter}.y()", json_type: :float }
    ]
  when 'QSize'
    [
      { name: "#{base_name}width", cpp_expr: "#{getter}.width()", json_type: :int },
      { name: "#{base_name}height", cpp_expr: "#{getter}.height()", json_type: :int }
    ]
  else
    compact = return_type.to_s.sub(/\Aconst\s+/, '').sub(/\s*&\z/, '').strip
    return [] unless compact.include?('::') && int_cast_types.include?(compact)

    [{ name: to_snake(method_name), cpp_expr: "static_cast<int>(#{getter})", json_type: :int }]
  end
end

def event_payload_compatibility_fields(class_name, field_names)
  aliases = EVENT_PAYLOAD_COMPATIBILITY_ALIASES[class_name] || {}
  aliases.each_with_object([]) do |(alias_name, target_name), out|
    if target_name.nil?
      out << { name: alias_name.to_s, source: nil, json_type: :int }
      next
    end

    next unless field_names.include?(target_name.to_s)

    out << { name: alias_name.to_s, source: target_name.to_s, json_type: :alias }
  end
end

def collect_event_payload_schema_for(ast, event_name, event_value, int_cast_types, warnings)
  class_name = resolve_event_payload_class_name(event_name)
  return nil if class_name.nil?
  return nil unless ast_class_index(ast)[:methods_by_class].key?(class_name)

  field_specs = event_payload_method_candidates(ast, class_name, int_cast_types).flat_map do |entry|
    event_payload_fields_for_method(entry[:method_name], entry[:return_type], int_cast_types)
  end
  field_specs.uniq! { |field| field[:name] }

  compatibility_fields = event_payload_compatibility_fields(class_name, field_specs.map { |field| field[:name] })
  schema = {
    symbol_name: qevent_symbol_name(event_name),
    event_name: event_name,
    event_value: event_value,
    constant_name: "Event#{event_name}",
    class_name: class_name,
    fields: field_specs,
    compatibility_fields: compatibility_fields
  }

  if field_specs.empty? && compatibility_fields.empty?
    warnings << "Qt::EventPayload: #{event_name} resolved to #{class_name} but no payload fields were derived"
  end

  schema
end

def collect_event_payload_schemas(ast, warnings = [])
  int_cast_types = ast_int_cast_type_set(ast)
  collect_enum_constants_for_scope(ast, ['QEvent'], warnings).sort.filter_map do |event_name, event_value|
    collect_event_payload_schema_for(ast, event_name, event_value, int_cast_types, warnings)
  end
end

def generate_ruby_event_payloads(ast)
  warnings = []
  schemas = collect_event_payload_schemas(ast, warnings)
  emit_generation_warnings(warnings)

  lines = ['# frozen_string_literal: true', '', 'module Qt']
  lines << '  GENERATED_EVENT_PAYLOAD_SCHEMAS = {'
  schemas.each do |schema|
    lines << "    #{schema[:symbol_name].inspect} => {"
    lines << "      event_type: #{schema[:constant_name]},"
    lines << "      event_class: '#{schema[:class_name]}',"
    lines << '      fields: ['
    schema[:fields].each do |field|
      lines << "        { name: #{field[:name].inspect}, type: #{field[:json_type].inspect} },"
    end
    schema[:compatibility_fields].each do |field|
      lines << "        { name: #{field[:name].inspect}, type: #{field[:json_type].inspect} },"
    end
    lines << '      ]'
    lines << '    },'
  end
  lines << '  }.freeze unless const_defined?(:GENERATED_EVENT_PAYLOAD_SCHEMAS, false)'
  lines << 'end'
  "#{lines.join("\n")}\n"
end

def cpp_json_insert_lines(field, source_expr = nil)
  expr = source_expr || field[:cpp_expr]
  case field[:json_type]
  when :bool, :int, :float
    ["payload.insert(\"#{field[:name]}\", #{expr});"]
  when :string
    ["payload.insert(\"#{field[:name]}\", #{expr});"]
  else
    []
  end
end

def generate_cpp_event_payload_extractor(ast)
  warnings = []
  schemas = collect_event_payload_schemas(ast, warnings)
  emit_generation_warnings(warnings)

  includes = schemas.map { |schema| "#include <#{schema[:class_name]}>" }.uniq.sort
  lines = []
  lines.concat(includes)
  lines << '#include <QEvent>'
  lines << '#include <QJsonDocument>'
  lines << '#include <QJsonObject>'
  lines << ''
  lines << 'namespace QtRubyGeneratedEventPayloads {'
  lines << 'inline QByteArray serialize_event_payload(int event_type, QEvent* event) {'
  lines << '  QJsonObject payload;'
  lines << '  payload.insert("type", event_type);'
  lines << '  switch (static_cast<QEvent::Type>(event_type)) {'
  schemas.each do |schema|
    lines << "    case QEvent::#{schema[:event_name]}: {"
    lines << "      auto* typed_event = static_cast<#{schema[:class_name]}*>(event);"
    schema[:fields].each do |field|
      cpp_json_insert_lines(field).each { |line| lines << "      #{line}" }
    end
    schema[:compatibility_fields].each do |field|
      if field[:source]
        lines << "      payload.insert(\"#{field[:name]}\", payload.value(\"#{field[:source]}\"));"
      else
        lines << "      payload.insert(\"#{field[:name]}\", 0);"
      end
    end
    lines << '      break;'
    lines << '    }'
  end
  lines << '    default:'
  lines << '      break;'
  lines << '  }'
  lines << '  return QJsonDocument(payload).toJson(QJsonDocument::Compact);'
  lines << '}'
  lines << '}  // namespace QtRubyGeneratedEventPayloads'
  "#{lines.join("\n")}\n"
end

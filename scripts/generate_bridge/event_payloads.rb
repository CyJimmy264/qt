# frozen_string_literal: true

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

def event_payload_class_names(ast)
  @event_payload_class_names ||= {}.compare_by_identity
  return @event_payload_class_names[ast] if @event_payload_class_names.key?(ast)

  index = ast_class_index(ast)
  @event_payload_class_names[ast] = index[:methods_by_class].keys.select do |class_name|
    class_name.start_with?('Q') && class_name.end_with?('Event') && class_inherits?(ast, class_name, 'QEvent')
  end.sort
end

def event_payload_ctor_type_param?(ctor_decl)
  Array(ctor_decl['inner']).any? do |node|
    next false unless node['kind'] == 'ParmVarDecl'

    raw_type = node.dig('type', 'desugaredQualType') || node.dig('type', 'qualType')
    name = node['name']
    %w[type t].include?(name) && %w[Type QEvent::Type].include?(raw_type)
  end
end

def event_payload_type_family_class_names(ast)
  @event_payload_type_family_class_names ||= {}.compare_by_identity
  return @event_payload_type_family_class_names[ast] if @event_payload_type_family_class_names.key?(ast)

  @event_payload_type_family_class_names[ast] = event_payload_class_names(ast).select do |class_name|
    collect_constructor_decls(ast, class_name).any? { |decl| event_payload_ctor_type_param?(decl) }
  end
end

def event_payload_class_stem(class_name)
  class_name.sub(/\AQ/, '').sub(/Event\z/, '')
end

def event_payload_camel_tokens(name)
  name.to_s.scan(/[A-Z]+(?=[A-Z][a-z]|\z)|[A-Z]?[a-z]+|\d+/)
end

def event_payload_token_sequence_present?(haystack, needle)
  return false if haystack.empty? || needle.empty? || needle.length > haystack.length

  0.upto(haystack.length - needle.length).any? do |start_idx|
    haystack[start_idx, needle.length] == needle
  end
end

def event_payload_family_match?(event_name, class_name, mode)
  event_tokens = event_payload_camel_tokens(event_name)
  class_tokens = event_payload_camel_tokens(event_payload_class_stem(class_name))
  return false if event_tokens.empty? || class_tokens.empty?

  event_downcase = event_tokens.map(&:downcase)
  class_downcase = class_tokens.map(&:downcase)
  event_compact = event_downcase.join
  class_compact = class_downcase.join

  case mode
  when :prefix
    event_downcase.first(class_downcase.length) == class_downcase
  when :suffix
    event_downcase.last(class_downcase.length) == class_downcase
  when :contiguous_tokens
    event_payload_token_sequence_present?(event_downcase, class_downcase)
  when :compact_substring
    event_compact.include?(class_compact)
  else
    false
  end
end

def event_payload_most_specific_class_names(ast, class_names)
  class_names.reject do |class_name|
    class_names.any? do |other|
      next false if other == class_name

      class_inherits?(ast, other, class_name)
    end
  end
end

def event_payload_longest_stem_class_names(class_names)
  stems = class_names.to_h do |class_name|
    [class_name, event_payload_camel_tokens(event_payload_class_stem(class_name)).length]
  end
  longest = stems.values.max
  class_names.select { |class_name| stems[class_name] == longest }
end

def resolve_event_payload_family_class_name(ast, event_name, warnings)
  %i[prefix suffix contiguous_tokens compact_substring].each do |mode|
    matches = event_payload_type_family_class_names(ast).select do |class_name|
      event_payload_family_match?(event_name, class_name, mode)
    end
    next if matches.empty?

    matches = event_payload_most_specific_class_names(ast, matches)
    matches = event_payload_longest_stem_class_names(matches)
    return matches.first if matches.length == 1

    warnings << "Qt::EventPayload: ambiguous #{mode} family match for #{event_name}: #{matches.sort.join(', ')}"
    return nil
  end

  nil
end

def resolve_event_payload_class_name(ast, event_name, warnings = [])
  exact_class_name = "Q#{event_name}Event"
  return exact_class_name if event_payload_class_names(ast).include?(exact_class_name)

  resolve_event_payload_family_class_name(ast, event_name, warnings)
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
  class_name = resolve_event_payload_class_name(ast, event_name, warnings)
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

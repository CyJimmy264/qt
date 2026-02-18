# frozen_string_literal: true

# Resolves auto-generated methods for a class spec while tracking counters.
class AutoMethodSpecResolver
  def initialize(spec:, auto_mode:, existing_names:, resolve_method:)
    @spec = spec
    @auto_mode = auto_mode
    @existing_names = existing_names
    @resolve_method = resolve_method
  end

  def resolve(entry, skipped:, resolved:)
    qt_name = entry_name(entry)
    return [nil, skipped + 1, resolved] if existing_names.include?(qt_name)

    method, skipped_entry = resolve_entry(entry)
    return [nil, skipped + 1, resolved] if skipped_entry

    [method, skipped, resolved + 1]
  end

  private

  attr_reader :spec, :auto_mode, :existing_names, :resolve_method

  def entry_name(entry)
    entry.is_a?(String) ? entry : entry[:qt_name]
  end

  def resolve_entry(entry)
    method = resolve_method.call(entry)
    return [method, false] unless method.nil?
    return [nil, true] if auto_mode == :all

    raise "Failed to auto-resolve #{spec[:qt_class]}##{entry_name(entry)}"
  end
end

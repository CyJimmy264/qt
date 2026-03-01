# frozen_string_literal: true

module Qt
  module GeneratedConstantsRuntime
    module_function

    def apply_generated_scoped_constants!(qt_module)
      return unless qt_module.const_defined?(:GENERATED_SCOPED_CONSTANTS, false)

      qt_module.const_get(:GENERATED_SCOPED_CONSTANTS, false).each do |owner_name, owner_constants|
        next unless qt_module.const_defined?(owner_name, false)

        owner = qt_module.const_get(owner_name, false)
        owner_constants.each do |const_name, const_value|
          next if owner.const_defined?(const_name, false)

          owner.const_set(const_name, const_value)
        end
      end
    end

    def apply_key_aliases!(qt_module)
      qt_module.constants(false).grep(/\AKey_[A-Za-z0-9_]+\z/).each do |source_name|
        suffix = source_name.to_s.sub(/\AKey_/, '')
        alias_name = "Key#{suffix.split('_').map(&:capitalize).join}"
        next unless alias_name.match?(/\A[A-Z][A-Za-z0-9_]*\z/)
        next if qt_module.const_defined?(alias_name, false)

        qt_module.const_set(alias_name, qt_module.const_get(source_name, false))
      end
    end
  end
end

# frozen_string_literal: true

module Qt
  module GeneratedSetterAliasesRuntime
    module_function

    def apply!(qt_module)
      qt_module.constants(false).each do |const_name|
        klass = qt_module.const_get(const_name, false)
        next unless klass.is_a?(Class)

        apply_instance_aliases!(klass)
        apply_singleton_aliases!(klass)
      end
    end

    def apply_instance_aliases!(klass)
      apply_aliases_to_target!(klass, klass, :QT_API_SETTER_ALIASES)
    end

    def apply_singleton_aliases!(klass)
      apply_aliases_to_target!(klass.singleton_class, klass, :QT_API_SINGLETON_SETTER_ALIASES)
    end

    def apply_aliases_to_target!(target, owner, constant_name)
      return unless owner.const_defined?(constant_name, false)

      owner.const_get(constant_name, false).each do |alias_name, setter_name|
        next if target.method_defined?(alias_name) || target.private_method_defined?(alias_name)

        target.send(:define_method, alias_name) do |value|
          public_send(setter_name, value)
        end
      end
    end
  end
end

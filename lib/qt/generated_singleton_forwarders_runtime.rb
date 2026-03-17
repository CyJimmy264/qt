# frozen_string_literal: true

module Qt
  module GeneratedSingletonForwardersRuntime
    module_function

    def apply!(qt_module)
      qt_module.constants(false).each do |const_name|
        klass = qt_module.const_get(const_name, false)
        next unless klass.is_a?(Class)
        next unless klass.const_defined?(:QT_API_SINGLETON_FORWARDERS, false)

        klass.const_get(:QT_API_SINGLETON_FORWARDERS, false).each do |method_name|
          next if klass.instance_methods(false).include?(method_name.to_sym)
          next if klass.private_instance_methods(false).include?(method_name.to_sym)

          klass.send(:define_method, method_name) do |*args, &block|
            self.class.public_send(method_name, *args, &block)
          end
        end
      end
    end
  end
end

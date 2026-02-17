# frozen_string_literal: true

module Qt
  module Native
    ROOT = File.expand_path('../..', __dir__)
    GENERATED_API = File.join(ROOT, 'build', 'generated', 'bridge_api.rb')

    require GENERATED_API if File.exist?(GENERATED_API)

    COERCERS = {
      string: ->(value) { value.to_s },
      int: ->(value) { Integer(value) },
      pointer: lambda { |value|
        return nil if value.nil?

        value.respond_to?(:handle) ? value.handle : value
      }
    }.freeze

    module_function

    def available?
      return @available unless @available.nil?

      @available = Bridge.load! && Bridge.loaded?
    end

    def ensure_loaded!
      return if available?

      detail = Bridge.load_error ? " (#{Bridge.load_error.message})" : ''
      raise NativeExtensionError,
            "Qt bridge is not available. Build it with: bundle exec rake compile#{detail}"
    end

    def define_bridge_wrappers!
      return if @bridge_wrappers_defined
      return unless defined?(Qt::BridgeAPI::FUNCTIONS)

      Qt::BridgeAPI::FUNCTIONS.each do |fn|
        native_name = fn[:name].to_s.sub(/\Aqt_ruby_/, '')
        signature = fn[:args]
        bridge_name = fn[:name]

        define_singleton_method(native_name) do |*args|
          ensure_loaded!

          if args.length < signature.length
            missing = signature[args.length..]
            unless missing.all? { |type| type == :pointer }
              raise ArgumentError, "wrong number of arguments (given #{args.length}, expected #{signature.length})"
            end

            args = args + [nil] * (signature.length - args.length)
          elsif args.length > signature.length
            raise ArgumentError, "wrong number of arguments (given #{args.length}, expected #{signature.length})"
          end

          converted = args.zip(signature).map do |value, type|
            coercer = COERCERS[type]
            coercer ? coercer.call(value) : value
          end

          Bridge.public_send(bridge_name, *converted)
        end
      end

      @bridge_wrappers_defined = true
    end

    define_bridge_wrappers!
  end
end

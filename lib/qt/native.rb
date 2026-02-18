# frozen_string_literal: true

module Qt
  module Native
    require 'ffi'

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
        define_bridge_wrapper(fn)
      end

      @bridge_wrappers_defined = true
    end

    def define_bridge_wrapper(function_spec)
      native_name = function_spec[:name].to_s.sub(/\Aqt_ruby_/, '')
      signature = function_spec[:args]
      bridge_name = function_spec[:name]

      define_singleton_method(native_name) do |*args|
        ensure_loaded!
        normalized = normalize_bridge_args(args, signature)
        converted = coerce_bridge_args(normalized, signature)
        Bridge.public_send(bridge_name, *converted)
      end
    end

    def normalize_bridge_args(args, signature)
      if args.length < signature.length
        missing = signature[args.length..]
        unless missing.all? { |type| type == :pointer }
          raise ArgumentError, "wrong number of arguments (given #{args.length}, expected #{signature.length})"
        end

        return args + ([nil] * (signature.length - args.length))
      end
      if args.length > signature.length
        raise ArgumentError, "wrong number of arguments (given #{args.length}, expected #{signature.length})"
      end

      args
    end

    def coerce_bridge_args(args, signature)
      args.zip(signature).map do |value, type|
        coercer = COERCERS[type]
        coercer ? coercer.call(value) : value
      end
    end

    define_bridge_wrappers!
  end
end

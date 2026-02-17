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

    def on_event(widget, event_name, &block)
      raise ArgumentError, 'pass block to on_event' unless block

      ensure_loaded!
      define_bridge_wrappers!
      ensure_event_callback!

      event_type = event_type_for(event_name)
      handle = widget_handle(widget)
      raise ArgumentError, 'widget handle is required' unless handle

      @event_handlers ||= {}
      per_widget = (@event_handlers[handle.address] ||= {})
      handlers = (per_widget[event_type] ||= [])
      handlers << block

      watch_qobject_event(handle, event_type)
      true
    end

    def on_signal(widget, signal_name, &block)
      raise ArgumentError, 'pass block to on_signal' unless block

      ensure_loaded!
      define_bridge_wrappers!
      ensure_signal_callback!

      handle = widget_handle(widget)
      raise ArgumentError, 'widget handle is required' unless handle

      signal_key = signal_name.to_s
      raise ArgumentError, 'signal name is required' if signal_key.empty?

      @signal_handlers ||= {}
      per_widget = (@signal_handlers[handle.address] ||= {})
      per_signal = (per_widget[signal_key] ||= { index: nil, blocks: [] })

      if per_signal[:index].nil?
        index = qobject_connect_signal(handle, signal_key)
        raise ArgumentError, "failed to connect signal #{signal_key.inspect} (code=#{index})" if index.negative?

        per_signal[:index] = index
      end

      per_signal[:blocks] << block
      true
    end

    def off_signal(widget, signal_name = nil)
      ensure_loaded!
      define_bridge_wrappers!

      handle = widget_handle(widget)
      return false unless handle && @signal_handlers

      per_widget = @signal_handlers[handle.address]
      return false unless per_widget

      if signal_name
        signal_key = signal_name.to_s
        per_widget.delete(signal_key)
        qobject_disconnect_signal(handle, signal_key)
      else
        per_widget.clear
        qobject_disconnect_signal(handle, nil)
      end

      true
    end

    def off_event(widget, event_name = nil)
      ensure_loaded!
      define_bridge_wrappers!

      handle = widget_handle(widget)
      return false unless handle && @event_handlers

      per_widget = @event_handlers[handle.address]
      return false unless per_widget

      if event_name
        event_type = event_type_for(event_name)
        per_widget.delete(event_type)
        unwatch_qobject_event(handle, event_type)
      else
        per_widget.keys.each { |et| unwatch_qobject_event(handle, et) }
        @event_handlers.delete(handle.address)
      end

      true
    end

    def event_type_for(event_name)
      key = event_name.to_sym
      map = {
        mouse_button_press: Qt::EventMouseButtonPress,
        mouse_button_release: Qt::EventMouseButtonRelease,
        mouse_move: Qt::EventMouseMove,
        key_press: Qt::EventKeyPress,
        key_release: Qt::EventKeyRelease,
        focus_in: Qt::EventFocusIn,
        focus_out: Qt::EventFocusOut,
        enter: Qt::EventEnter,
        leave: Qt::EventLeave,
        resize: Qt::EventResize
      }
      event_type = map[key]
      raise ArgumentError, "unknown event: #{event_name.inspect}" unless event_type

      event_type
    end

    def ensure_event_callback!
      return if @event_callback

      @event_callback = FFI::Function.new(:void, %i[pointer int int int int int]) do |object_handle, event_type, a, b, c, d|
        next unless object_handle && @event_handlers

        per_widget = @event_handlers[object_handle.address]
        next unless per_widget

        handlers = per_widget[event_type]
        next unless handlers && !handlers.empty?

        payload = { type: event_type, a: a, b: b, c: c, d: d }
        handlers.each { |h| h.call(payload) }
      end

      set_event_callback(@event_callback)
    end

    def ensure_signal_callback!
      return if @signal_callback

      @signal_callback = FFI::Function.new(:void, %i[pointer int string]) do |object_handle, signal_index, payload|
        next unless object_handle && @signal_handlers

        per_widget = @signal_handlers[object_handle.address]
        next unless per_widget

        per_widget.each_value do |entry|
          next unless entry[:index] == signal_index

          entry[:blocks].each { |h| h.call(payload) }
        end
      end

      set_signal_callback(@signal_callback)
    end

    def widget_handle(widget)
      return nil if widget.nil?

      widget.respond_to?(:handle) ? widget.handle : widget
    end

    define_bridge_wrappers!
  end
end

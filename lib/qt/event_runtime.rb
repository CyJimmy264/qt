# frozen_string_literal: true

module Qt
  module EventRuntime
    module WidgetMethods
      def on(event_name, &block)
        raise ArgumentError, 'pass block to on' unless block

        EventRuntime.on_event(self, event_name, &block)
        self
      end
      alias_method :on_event, :on

      def connect(signal_name, &block)
        raise ArgumentError, 'pass block to connect' unless block

        EventRuntime.on_signal(self, signal_name, &block)
        self
      end
      alias_method :on_signal, :connect
      alias_method :slot, :connect

      def off(event_name = nil)
        EventRuntime.off_event(self, event_name)
        self
      end
      alias_method :off_event, :off

      def disconnect(signal_name = nil)
        EventRuntime.off_signal(self, signal_name)
        self
      end
      alias_method :off_signal, :disconnect
    end

    module_function

    def on_event(widget, event_name, &block)
      raise ArgumentError, 'pass block to on_event' unless block

      Qt::Native.ensure_loaded!
      Qt::Native.define_bridge_wrappers!
      ensure_event_callback!

      event_type = event_type_for(event_name)
      handle = widget_handle(widget)
      raise ArgumentError, 'widget handle is required' unless handle

      @event_handlers ||= {}
      per_widget = (@event_handlers[handle.address] ||= {})
      handlers = (per_widget[event_type] ||= [])
      handlers << block

      Qt::Native.watch_qobject_event(handle, event_type)
      true
    end

    def on_signal(widget, signal_name, &block)
      raise ArgumentError, 'pass block to on_signal' unless block

      Qt::Native.ensure_loaded!
      Qt::Native.define_bridge_wrappers!
      ensure_signal_callback!

      handle = widget_handle(widget)
      raise ArgumentError, 'widget handle is required' unless handle

      signal_key = signal_name.to_s
      raise ArgumentError, 'signal name is required' if signal_key.empty?

      @signal_handlers ||= {}
      per_widget = (@signal_handlers[handle.address] ||= {})
      per_signal = (per_widget[signal_key] ||= { index: nil, blocks: [] })

      if per_signal[:index].nil?
        index = Qt::Native.qobject_connect_signal(handle, signal_key)
        raise ArgumentError, "failed to connect signal #{signal_key.inspect} (code=#{index})" if index.negative?

        per_signal[:index] = index
      end

      per_signal[:blocks] << block
      true
    end

    def off_signal(widget, signal_name = nil)
      Qt::Native.ensure_loaded!
      Qt::Native.define_bridge_wrappers!

      handle = widget_handle(widget)
      return false unless handle && @signal_handlers

      per_widget = @signal_handlers[handle.address]
      return false unless per_widget

      if signal_name
        signal_key = signal_name.to_s
        per_widget.delete(signal_key)
        Qt::Native.qobject_disconnect_signal(handle, signal_key)
      else
        per_widget.clear
        Qt::Native.qobject_disconnect_signal(handle, nil)
      end

      true
    end

    def off_event(widget, event_name = nil)
      Qt::Native.ensure_loaded!
      Qt::Native.define_bridge_wrappers!

      handle = widget_handle(widget)
      return false unless handle && @event_handlers

      per_widget = @event_handlers[handle.address]
      return false unless per_widget

      if event_name
        event_type = event_type_for(event_name)
        per_widget.delete(event_type)
        Qt::Native.unwatch_qobject_event(handle, event_type)
      else
        per_widget.keys.each { |et| Qt::Native.unwatch_qobject_event(handle, et) }
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
        handlers.each { |handler| handler.call(payload) }
      end

      Qt::Native.set_event_callback(@event_callback)
    end

    def ensure_signal_callback!
      return if @signal_callback

      @signal_callback = FFI::Function.new(:void, %i[pointer int string]) do |object_handle, signal_index, payload|
        next unless object_handle && @signal_handlers

        per_widget = @signal_handlers[object_handle.address]
        next unless per_widget

        per_widget.each_value do |entry|
          next unless entry[:index] == signal_index

          entry[:blocks].each { |handler| handler.call(payload) }
        end
      end

      Qt::Native.set_signal_callback(@signal_callback)
    end

    def widget_handle(widget)
      return nil if widget.nil?

      widget.respond_to?(:handle) ? widget.handle : widget
    end
  end
end

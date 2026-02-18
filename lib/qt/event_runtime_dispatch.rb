# frozen_string_literal: true

# Dispatch helpers for event/signal callbacks from the native bridge.
module Qt
  # Dispatch helpers for event/signal callbacks from the native bridge.
  module EventRuntimeDispatch
    module_function

    def dispatch_event(event_handlers, object_handle, event_type, payload)
      return unless object_handle && event_handlers

      per_widget = event_handlers[object_handle.address]
      return unless per_widget

      handlers = per_widget[event_type]
      return unless handlers && !handlers.empty?

      handlers.each { |handler| handler.call(payload) }
    end

    def dispatch_signal(signal_handlers, object_handle, signal_index, payload)
      return unless object_handle && signal_handlers

      per_widget = signal_handlers[object_handle.address]
      return unless per_widget

      per_widget.each_value do |entry|
        next unless entry[:index] == signal_index

        entry[:blocks].each { |handler| handler.call(payload) }
      end
    end
  end
end

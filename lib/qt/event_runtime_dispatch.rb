# frozen_string_literal: true

# Dispatch helpers for event/signal callbacks from the native bridge.
module Qt
  # Dispatch helpers for event/signal callbacks from the native bridge.
  module EventRuntimeDispatch
    module_function

    def dispatch_event(event_handlers, object_handle, event_type, payload)
      return 1 unless object_handle && event_handlers

      per_widget = event_handlers[object_handle.address]
      return 1 unless per_widget

      handlers = per_widget[event_type]
      return 1 unless handlers && !handlers.empty?

      results = handlers.map { |handler| handler.call(payload) }
      results.any? { |result| result == false || result == :ignore } ? 0 : 1
    end

    def dispatch_signal(signal_handlers, object_handle, signal_index, payload)
      return unless object_handle && signal_handlers

      per_widget = signal_handlers[object_handle.address]
      return unless per_widget

      per_widget.each do |signal_name, entry|
        next unless entry[:index] == signal_index

        typed_payload = Qt::DateTimeCodec.decode_for_signal(signal_name, payload)
        entry[:blocks].each { |handler| handler.call(typed_payload) }
      end
    end
  end
end

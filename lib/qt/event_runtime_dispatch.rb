# frozen_string_literal: true

# Dispatch helpers for event/signal callbacks from the native bridge.
module Qt
  # Dispatch helpers for event/signal callbacks from the native bridge.
  module EventRuntimeDispatch
    EVENT_RESULT_IGNORE = 0
    EVENT_RESULT_CONTINUE = 1
    EVENT_RESULT_CONSUME = 2

    module_function

    def dispatch_event(event_handlers, object_handle, event_type, payload)
      return EVENT_RESULT_CONTINUE unless object_handle && event_handlers

      per_widget = event_handlers[object_handle.address]
      return EVENT_RESULT_CONTINUE unless per_widget

      handlers = per_widget[event_type]
      return EVENT_RESULT_CONTINUE unless handlers && !handlers.empty?

      results = handlers.map { |handler| handler.call(payload) }
      return EVENT_RESULT_CONSUME if results.any? { |result| result == true || result == :consume }
      return EVENT_RESULT_IGNORE if results.any? { |result| result == false || result == :ignore }

      EVENT_RESULT_CONTINUE
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

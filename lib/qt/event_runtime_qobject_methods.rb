# frozen_string_literal: true

# QObject-level event/signal helper methods mixed into generated classes.
module Qt
  module EventRuntime
    # QObject-level event/signal helper methods mixed into generated classes.
    module QObjectMethods
      def on(event_name, &block)
        raise ArgumentError, 'pass block to on' unless block

        EventRuntime.on_event(self, event_name, &block)
        self
      end
      alias on_event on

      def connect(signal_name, &block)
        raise ArgumentError, 'pass block to connect' unless block

        EventRuntime.on_signal(self, signal_name, &block)
        self
      end
      alias on_signal connect
      alias slot connect

      def off(event_name = nil)
        EventRuntime.off_event(self, event_name)
        self
      end
      alias off_event off

      def disconnect(signal_name = nil)
        EventRuntime.off_signal(self, signal_name)
        self
      end
      alias off_signal disconnect
    end

    # Backward-compatible alias for already-generated code.
    WidgetMethods = QObjectMethods
  end
end

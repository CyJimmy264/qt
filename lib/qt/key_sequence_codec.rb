# frozen_string_literal: true

module Qt
  # Conversion helpers for QKeySequence bridge arguments.
  module KeySequenceCodec
    module_function

    def encode(value)
      return '' if value.nil?
      return Qt::StringCodec.to_qt_text(value) if value.is_a?(String)

      if value.respond_to?(:to_string)
        return Qt::StringCodec.to_qt_text(value.to_string)
      end
      if value.respond_to?(:toString)
        return Qt::StringCodec.to_qt_text(value.toString)
      end

      Qt::StringCodec.to_qt_text(value.to_s)
    end
  end
end

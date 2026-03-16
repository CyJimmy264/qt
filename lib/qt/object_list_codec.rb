# frozen_string_literal: true

require 'json'

module Qt
  # Decodes QObjectList bridge payloads into canonical Ruby wrappers.
  module ObjectListCodec
    module_function

    def decode(payload, expected_qt_class = 'QObject')
      raw = Qt::StringCodec.from_qt_text(payload.to_s)
      return [] if raw.empty?

      JSON.parse(raw).filter_map do |address|
        next if address.nil? || address.to_s.empty?

        Qt::ObjectWrapper.wrap(FFI::Pointer.new(Integer(address, 10)), expected_qt_class)
      end
    rescue JSON::ParserError, ArgumentError
      []
    end
  end
end

# frozen_string_literal: true

require 'json'

module Qt
  # Encodes/decodes Ruby values for QVariant bridge transport.
  module VariantCodec
    module_function

    PREFIX = 'qtv:'

    def encode(value)
      return "#{PREFIX}nil" if value.nil?
      return encode_boolean(value) if [true, false].include?(value)
      return "#{PREFIX}int:#{value}" if value.is_a?(Integer)
      return "#{PREFIX}float:#{value}" if value.is_a?(Float)
      return "#{PREFIX}str:#{base64_encode(value)}" if value.is_a?(String)
      return "#{PREFIX}json:#{base64_encode(JSON.generate(value))}" if value.is_a?(Array) || value.is_a?(Hash)

      "#{PREFIX}str:#{base64_encode(value.to_s)}"
    end

    def decode(value)
      raw = value.to_s
      return raw unless raw.start_with?(PREFIX)
      return nil if raw == "#{PREFIX}nil"

      tag, payload = raw.delete_prefix(PREFIX).split(':', 2)
      return raw if tag.nil? || payload.nil?

      decode_typed_payload(tag, payload, raw)
    rescue ArgumentError, JSON::ParserError
      raw
    end

    def encode_boolean(value)
      "#{PREFIX}bool:#{value ? 1 : 0}"
    end

    def decode_typed_payload(tag, payload, raw)
      case tag
      when 'bool' then payload == '1'
      when 'int' then Integer(payload, 10)
      when 'float' then Float(payload)
      when 'str' then base64_decode(payload)
      when 'json' then JSON.parse(base64_decode(payload))
      else raw
      end
    end

    def base64_encode(value)
      [value].pack('m0')
    end

    def base64_decode(value)
      value.unpack1('m0')
    end
  end
end

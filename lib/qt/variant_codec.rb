# frozen_string_literal: true

require 'json'

module Qt
  # Encodes/decodes Ruby values for QVariant bridge transport.
  module VariantCodec
    module_function

    PREFIX = 'qtv:'
    DIRECT_ENCODERS = {
      Integer => ->(v) { ['int', v.to_s] },
      Float => ->(v) { ['float', v.to_s] },
      String => lambda { |v|
        if StringCodec.binary_bytes?(v)
          ['ba', base64_encode(v)]
        else
          ['str', base64_encode(StringCodec.to_qt_text(v))]
        end
      }
    }.freeze
    JSON_ENCODABLE_CLASSES = [Array, Hash].freeze

    def encode(value)
      return "#{PREFIX}nil" if value.nil?
      return encode_boolean(value) if [true, false].include?(value)

      tag, payload = encoded_tag_and_payload(value)
      "#{PREFIX}#{tag}:#{payload}"
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
      when 'str' then StringCodec.from_qt_text(base64_decode(payload))
      when 'ba' then base64_decode(payload).b
      when 'json' then JSON.parse(StringCodec.from_qt_text(base64_decode(payload)))
      else raw
      end
    end

    def base64_encode(value)
      [value].pack('m0')
    end

    def base64_decode(value)
      value.unpack1('m0')
    end

    def encoded_tag_and_payload(value)
      direct = DIRECT_ENCODERS[value.class]
      return direct.call(value) if direct

      return ['json', base64_encode(JSON.generate(value))] if JSON_ENCODABLE_CLASSES.any? { |k| value.is_a?(k) }

      ['str', base64_encode(value.to_s)]
    end
  end
end

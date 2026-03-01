# frozen_string_literal: true

module Qt
  # Normalizes Ruby strings for bridge text paths.
  module StringCodec
    module_function

    REPLACEMENT_CHAR = "\uFFFD"

    def to_qt_text(value)
      text = value.to_s
      return normalize_binary_as_utf8(text) if text.encoding == Encoding::ASCII_8BIT

      normalize_encoded_text(text)
    end

    def from_qt_text(value)
      normalize_binary_as_utf8(value.to_s)
    end

    def binary_bytes?(value)
      return false unless value.is_a?(String)
      return false unless value.encoding == Encoding::ASCII_8BIT

      !value.dup.force_encoding(Encoding::UTF_8).valid_encoding?
    end

    def normalize_encoded_text(text)
      text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: REPLACEMENT_CHAR)
    rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
      normalize_binary_as_utf8(text.b)
    end

    def normalize_binary_as_utf8(text)
      utf8 = text.dup.force_encoding(Encoding::UTF_8)
      utf8.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: REPLACEMENT_CHAR)
    rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
      text.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: REPLACEMENT_CHAR)
    end

    module_function :normalize_encoded_text, :normalize_binary_as_utf8
    private_class_method :normalize_encoded_text, :normalize_binary_as_utf8
  end
end

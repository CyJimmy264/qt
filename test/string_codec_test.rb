# frozen_string_literal: true

require_relative 'test_helper'

class QtStringCodecTest < Minitest::Test
  def test_variant_codec_decodes_text_as_utf8
    encoded = Qt::VariantCodec.encode('Привет')
    decoded = Qt::VariantCodec.decode(encoded)

    assert_equal Encoding::UTF_8, decoded.encoding
    assert_equal 'Привет', decoded
  end

  def test_variant_codec_binary_payload_stays_binary
    raw = "\xFF\x00a".b
    encoded = Qt::VariantCodec.encode(raw)
    decoded = Qt::VariantCodec.decode(encoded)

    assert encoded.start_with?('qtv:ba:')
    assert_equal Encoding::ASCII_8BIT, decoded.encoding
    assert_equal raw, decoded
  end
end

# frozen_string_literal: true

require_relative 'test_helper'
require 'date'

class QtDateTimeCodecTest < Minitest::Test
  def test_qdatetime_roundtrip_keeps_seconds_and_offset
    source = Time.new(2026, 3, 2, 12, 34, 56, '+05:30')
    encoded = Qt::DateTimeCodec.encode_qdatetime(source)
    decoded = Qt::DateTimeCodec.decode_qdatetime(encoded)

    assert_equal source.to_i, decoded.to_i
    assert_equal source.utc_offset, decoded.utc_offset
    assert_equal source.sec, decoded.sec
  end

  def test_qdate_roundtrip
    source = Date.new(2026, 3, 2)
    encoded = Qt::DateTimeCodec.encode_qdate(source)
    decoded = Qt::DateTimeCodec.decode_qdate(encoded)

    assert_equal source, decoded
  end

  def test_qtime_accepts_hh_mm_or_hh_mm_ss
    assert_equal '09:10:00', Qt::DateTimeCodec.decode_qtime(Qt::DateTimeCodec.encode_qtime('09:10'))
    assert_equal '09:10:11', Qt::DateTimeCodec.decode_qtime(Qt::DateTimeCodec.encode_qtime('09:10:11'))
  end
end

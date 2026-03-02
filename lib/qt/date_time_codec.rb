# frozen_string_literal: true

require 'date'
require 'time'

module Qt
  # Codec for typed QDateTime/QDate/QTime bridge payloads.
  module DateTimeCodec
    module_function

    DATETIME_PREFIX = 'qtdt:'
    DATE_PREFIX = 'qtdate:'
    TIME_PREFIX = 'qttime:'

    def encode_qdatetime(value)
      time = coerce_to_time(value)
      "#{DATETIME_PREFIX}#{time.iso8601(6)}"
    end

    def decode_qdatetime(value)
      raw = StringCodec.from_qt_text(value.to_s)
      payload = raw.start_with?(DATETIME_PREFIX) ? raw.delete_prefix(DATETIME_PREFIX) : raw
      Time.iso8601(payload)
    rescue ArgumentError
      Time.at(0).utc
    end

    def encode_qdate(value)
      date = coerce_to_date(value)
      "#{DATE_PREFIX}#{date.strftime('%Y-%m-%d')}"
    end

    def decode_qdate(value)
      raw = StringCodec.from_qt_text(value.to_s)
      payload = raw.start_with?(DATE_PREFIX) ? raw.delete_prefix(DATE_PREFIX) : raw
      Date.iso8601(payload)
    rescue ArgumentError
      Date.new(1970, 1, 1)
    end

    def encode_qtime(value)
      time_string =
        case value
        when Time then value.strftime('%H:%M:%S')
        else normalize_time_string(value.to_s)
        end
      "#{TIME_PREFIX}#{time_string}"
    end

    def decode_qtime(value)
      raw = StringCodec.from_qt_text(value.to_s)
      payload = raw.start_with?(TIME_PREFIX) ? raw.delete_prefix(TIME_PREFIX) : raw
      normalize_time_string(payload)
    rescue ArgumentError
      '00:00:00'
    end

    def decode_for_signal(signal_name, payload)
      return nil if payload.nil?

      signature = signal_name.to_s
      if signature.start_with?('dateTimeChanged(')
        return decode_qdatetime(payload)
      end
      if signature.start_with?('dateChanged(')
        return decode_qdate(payload)
      end
      if signature.start_with?('timeChanged(')
        return decode_qtime(payload)
      end

      StringCodec.from_qt_text(payload)
    end

    def coerce_to_time(value)
      return value if value.is_a?(Time)
      return value.to_time if value.respond_to?(:to_time)

      Time.iso8601(value.to_s)
    rescue ArgumentError
      Time.at(0).utc
    end

    def coerce_to_date(value)
      return value if value.is_a?(Date)
      return value.to_date if value.respond_to?(:to_date)

      Date.iso8601(value.to_s)
    rescue ArgumentError
      Date.new(1970, 1, 1)
    end

    def normalize_time_string(value)
      raw = value.to_s.strip
      raise ArgumentError, 'time is empty' if raw.empty?

      return "#{raw}:00" if raw.match?(/\A\d{2}:\d{2}\z/)
      return raw if raw.match?(/\A\d{2}:\d{2}:\d{2}\z/)

      parsed = Time.parse(raw)
      parsed.strftime('%H:%M:%S')
    end
  end
end

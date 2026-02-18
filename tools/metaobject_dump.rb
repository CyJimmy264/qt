#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'qt'

DEFAULT_SIGNAL_PROBES = %w[
  clicked
  pressed
  released
  toggled
  textChanged
  textEdited
  editingFinished
  returnPressed
  destroyed
  objectNameChanged
  windowTitleChanged
].freeze

def usage!
  warn <<~TXT
    Usage:
      ruby tools/metaobject_dump.rb CLASS [signal1,signal2,...]

    Example:
      ruby tools/metaobject_dump.rb QPushButton clicked,pressed,released
  TXT
  exit 1
end

klass_name = ARGV[0]
usage! if klass_name.nil? || klass_name.strip.empty?

probe_names =
  if ARGV[1].to_s.strip.empty?
    DEFAULT_SIGNAL_PROBES
  else
    ARGV[1].split(',').map(&:strip).reject(&:empty?)
  end

klass = Object.const_get(klass_name)
unless klass.respond_to?(:new)
  warn "Class #{klass_name.inspect} is not constructible."
  exit 2
end

app = QApplication.new(0, [])
object =
  begin
    klass.new
  rescue ArgumentError
    # Some classes might require a parent in future bindings.
    klass.new(nil)
  end

puts "Class: #{klass}"
puts "Handle: 0x#{object.handle.address.to_s(16)}"
puts 'Signal probe results:'

probe_names.each do |signal_name|
  code = Qt::Native.qobject_connect_signal(object.handle, signal_name)
  status =
    case code
    when -1 then 'invalid-args'
    when -2 then 'not-found-or-ambiguous'
    when -3 then 'unsupported-runtime-path'
    when -4 then 'qt-connect-failed'
    when -5 then 'mapper-connect-failed'
    else
      "ok(index=#{code})"
    end

  puts "  #{signal_name}: #{status}"
  Qt::Native.qobject_disconnect_signal(object.handle, signal_name) if code >= 0
end

app.dispose

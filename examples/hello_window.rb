# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'qt'

app = Qt::Application.new(title: 'Qt Ruby Demo', width: 640, height: 360)
puts "Qt version: #{Qt::Application.qt_version}"
exit(app.run)

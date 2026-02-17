# frozen_string_literal: true

require 'rbconfig'

ROOT = File.expand_path('..', __dir__)
GENERATOR = File.join(ROOT, 'scripts', 'generate_bridge.rb')
GENERATED_DIR = File.join(ROOT, 'build', 'generated')
GENERATED_WIDGETS = File.join(GENERATED_DIR, 'widgets.rb')
GENERATED_API = File.join(GENERATED_DIR, 'bridge_api.rb')

unless File.exist?(GENERATED_WIDGETS) && File.exist?(GENERATED_API)
  ok = system(RbConfig.ruby, GENERATOR)
  raise 'Failed to generate Qt Ruby bindings. Run: bundle exec rake compile' unless ok
end

require_relative 'qt/version'
require_relative 'qt/errors'
require_relative 'qt/constants'
require_relative 'qt/bridge'
require_relative 'qt/native'
require GENERATED_WIDGETS

module Qt
end

::QApplication = Qt::QApplication unless defined?(::QApplication)
::QWidget = Qt::QWidget unless defined?(::QWidget)
::QLabel = Qt::QLabel unless defined?(::QLabel)

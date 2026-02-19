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
require_relative 'qt/inspectable'
require_relative 'qt/children_tracking'
require_relative 'qt/application_lifecycle'
require_relative 'qt/bridge'
require_relative 'qt/native'
require_relative 'qt/event_runtime_dispatch'
require_relative 'qt/event_runtime_widget_methods'
require_relative 'qt/event_runtime'
require GENERATED_WIDGETS

# Root namespace for all Qt Ruby bindings.
module Qt
end

{
  QApplication: :QApplication,
  QWidget: :QWidget,
  QLabel: :QLabel,
  QPushButton: :QPushButton,
  QLineEdit: :QLineEdit,
  QVBoxLayout: :QVBoxLayout,
  QTableWidget: :QTableWidget,
  QTableWidgetItem: :QTableWidgetItem,
  QScrollArea: :QScrollArea,
  QTimer: :QTimer
}.each do |top_level, qt_const|
  next unless Qt.const_defined?(qt_const, false)
  next if Object.const_defined?(top_level, false)

  Object.const_set(top_level, Qt.const_get(qt_const))
end

# frozen_string_literal: true

require 'rbconfig'

ROOT = File.expand_path('..', __dir__)
GENERATOR = File.join(ROOT, 'scripts', 'generate_bridge.rb')
GENERATED_DIR = File.join(ROOT, 'build', 'generated')
GENERATED_WIDGETS = File.join(GENERATED_DIR, 'widgets.rb')
GENERATED_API = File.join(GENERATED_DIR, 'bridge_api.rb')
GENERATED_CONSTANTS = File.join(GENERATED_DIR, 'constants.rb')

unless File.exist?(GENERATED_WIDGETS) && File.exist?(GENERATED_API) && File.exist?(GENERATED_CONSTANTS)
  ok = system(RbConfig.ruby, GENERATOR)
  raise 'Failed to generate Qt Ruby bindings. Run: bundle exec rake compile' unless ok
end

require_relative 'qt/version'
require_relative 'qt/errors'
require_relative 'qt/constants'
require_relative 'qt/variant_codec'
require_relative 'qt/inspectable'
require_relative 'qt/children_tracking'
require_relative 'qt/application_lifecycle'
require_relative 'qt/bridge'
require_relative 'qt/native'
require_relative 'qt/event_runtime_dispatch'
require_relative 'qt/event_runtime_qobject_methods'
require_relative 'qt/event_runtime'
require GENERATED_WIDGETS

# Root namespace for all Qt Ruby bindings.
module Qt
end

Qt.constants(false)
  .grep(/\AQ[A-Z]\w*\z/)
  .sort
  .each do |qt_const|
    next if Object.const_defined?(qt_const, false)

    Object.const_set(qt_const, Qt.const_get(qt_const))
  end

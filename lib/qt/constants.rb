# frozen_string_literal: true

require_relative 'generated_constants_runtime'

module Qt
  GENERATED_CONSTANTS = File.expand_path('../../build/generated/constants.rb', __dir__)
  require GENERATED_CONSTANTS if File.exist?(GENERATED_CONSTANTS)

  GeneratedConstantsRuntime.apply_key_aliases!(self)
end

# frozen_string_literal: true

module Qt
  GENERATED_CONSTANTS = File.expand_path('../../build/generated/constants.rb', __dir__)
  require GENERATED_CONSTANTS if File.exist?(GENERATED_CONSTANTS)

  constants(false).grep(/\AKey_[A-Za-z0-9_]+\z/).each do |source_name|
    suffix = source_name.to_s.sub(/\AKey_/, '')
    alias_name = "Key#{suffix.split('_').map(&:capitalize).join}"
    next unless alias_name.match?(/\A[A-Z][A-Za-z0-9_]*\z/)
    next if const_defined?(alias_name, false)

    const_set(alias_name, const_get(source_name))
  end
end

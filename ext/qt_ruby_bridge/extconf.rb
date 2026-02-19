# frozen_string_literal: true

require 'mkmf'
require 'fileutils'

PKG_CONFIG = RbConfig::CONFIG['PKG_CONFIG'] || 'pkg-config'
QT_PACKAGES = %w[Qt6Core Qt6Gui Qt6Widgets].freeze
MINIMUM_QT_VERSION = Gem::Version.new('6.10.0')

def pkg_config(*)
  system(PKG_CONFIG, *, out: File::NULL, err: File::NULL)
end

def pkg_config_capture(*args)
  `#{[PKG_CONFIG, *args].join(' ')}`.strip
end

abort 'pkg-config is required to build qt-ruby bridge.' unless find_executable(PKG_CONFIG)

generator = File.expand_path('../../scripts/generate_bridge.rb', __dir__)
abort "Generator script not found: #{generator}" unless File.exist?(generator)

generator_env = {}
scope = ENV.fetch('QT_RUBY_SCOPE', nil)
generator_env['QT_RUBY_SCOPE'] = scope if scope && !scope.empty?
abort 'Failed to generate Qt bridge files.' unless system(generator_env, RbConfig.ruby, generator)

missing = QT_PACKAGES.reject { |pkg| pkg_config('--exists', pkg) }
abort "Missing Qt packages: #{missing.join(', ')}" unless missing.empty?

qt_version_str = pkg_config_capture('--modversion', 'Qt6Core')
qt_version = Gem::Version.new(qt_version_str)
abort "Qt version #{qt_version} is too old. Require >= #{MINIMUM_QT_VERSION}." if qt_version < MINIMUM_QT_VERSION

cflags = pkg_config_capture('--cflags', *QT_PACKAGES)
libs = pkg_config_capture('--libs', *QT_PACKAGES)
generated_cpp = if File.exist?('qt_ruby_bridge.cpp')
                  File.expand_path('qt_ruby_bridge.cpp')
                else
                  File.expand_path('../../build/generated/qt_ruby_bridge.cpp', __dir__)
                end
runtime_hpp = File.expand_path('../../ext/qt_ruby_bridge/qt_ruby_runtime.hpp', __dir__)
runtime_cpp_files = %w[
  runtime_events.cpp
  runtime_signals.cpp
].map { |name| File.expand_path("../../ext/qt_ruby_bridge/#{name}", __dir__) }

unless File.exist?(generated_cpp)
  abort "Generated source not found: #{generated_cpp}. Run: ruby scripts/generate_bridge.rb"
end
abort "Runtime header not found: #{runtime_hpp}" unless File.exist?(runtime_hpp)
missing_runtime = runtime_cpp_files.reject { |path| File.exist?(path) }
abort "Runtime source not found: #{missing_runtime.join(', ')}" unless missing_runtime.empty?

local_cpp = File.expand_path('qt_ruby_bridge.cpp')
FileUtils.cp(generated_cpp, local_cpp) unless File.exist?(local_cpp) && File.identical?(generated_cpp, local_cpp)
runtime_cpp_files.each do |runtime_cpp|
  local_runtime_cpp = File.expand_path(File.basename(runtime_cpp))
  unless File.exist?(local_runtime_cpp) && File.identical?(runtime_cpp, local_runtime_cpp)
    FileUtils.cp(runtime_cpp, local_runtime_cpp)
  end
end
local_runtime_hpp = File.expand_path('qt_ruby_runtime.hpp')
unless File.exist?(local_runtime_hpp) && File.identical?(runtime_hpp, local_runtime_hpp)
  FileUtils.cp(runtime_hpp, local_runtime_hpp)
end

# mkmf uses these global variables for compiler/linker/source configuration.
# rubocop:disable Style/GlobalVars
$CXXFLAGS = "#{$CXXFLAGS} #{cflags} -std=c++17"
$LDFLAGS = "#{$LDFLAGS} #{libs}"
$srcs = ['qt_ruby_bridge.cpp', *runtime_cpp_files.map { |f| File.basename(f) }]
# rubocop:enable Style/GlobalVars

create_makefile('qt/qt_ruby_bridge')

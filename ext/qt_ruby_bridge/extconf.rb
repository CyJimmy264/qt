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

unless find_executable(PKG_CONFIG)
  abort 'pkg-config is required to build qt-ruby bridge.'
end

generator = File.expand_path('../../scripts/generate_bridge.rb', __dir__)
unless File.exist?(generator)
  abort "Generator script not found: #{generator}"
end

unless system(RbConfig.ruby, generator)
  abort 'Failed to generate Qt bridge files.'
end

missing = QT_PACKAGES.reject { |pkg| pkg_config('--exists', pkg) }
unless missing.empty?
  abort "Missing Qt packages: #{missing.join(', ')}"
end

qt_version_str = pkg_config_capture('--modversion', 'Qt6Core')
qt_version = Gem::Version.new(qt_version_str)
if qt_version < MINIMUM_QT_VERSION
  abort "Qt version #{qt_version} is too old. Require >= #{MINIMUM_QT_VERSION}."
end

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
unless File.exist?(runtime_hpp)
  abort "Runtime header not found: #{runtime_hpp}"
end
missing_runtime = runtime_cpp_files.reject { |path| File.exist?(path) }
unless missing_runtime.empty?
  abort "Runtime source not found: #{missing_runtime.join(', ')}"
end

local_cpp = File.expand_path('qt_ruby_bridge.cpp')
unless File.exist?(local_cpp) && File.identical?(generated_cpp, local_cpp)
  FileUtils.cp(generated_cpp, local_cpp)
end
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

$CXXFLAGS = "#{$CXXFLAGS} #{cflags} -std=c++17"
$LDFLAGS = "#{$LDFLAGS} #{libs}"
$srcs = ['qt_ruby_bridge.cpp', *runtime_cpp_files.map { |f| File.basename(f) }]

create_makefile('qt/qt_ruby_bridge')

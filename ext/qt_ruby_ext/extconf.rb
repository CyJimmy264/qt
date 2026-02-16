# frozen_string_literal: true

require 'mkmf'

PKG_CONFIG = RbConfig::CONFIG['PKG_CONFIG'] || 'pkg-config'
QT_PACKAGES = %w[Qt6Core Qt6Gui Qt6Widgets].freeze
MINIMUM_QT_VERSION = Gem::Version.new('6.10.0')

def pkg_config(*args)
  system(PKG_CONFIG, *args, out: File::NULL, err: File::NULL)
end

def pkg_config_capture(*args)
  `#{[PKG_CONFIG, *args].join(' ')}`.strip
end

unless find_executable(PKG_CONFIG)
  abort 'pkg-config is required to build qt-ruby extension.'
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

$CXXFLAGS = "#{$CXXFLAGS} #{cflags} -std=c++17"
$LDFLAGS = "#{$LDFLAGS} #{libs}"
$srcs = ['qt_ruby_ext.cpp']

create_makefile('qt/qt_ruby_ext')

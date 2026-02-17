# frozen_string_literal: true

require 'rake/clean'
require 'rake/testtask'

CLEAN.include(
  '**/*.o',
  '**/*.so',
  '**/*.bundle',
  '**/*.dll',
  '**/*.dylib',
  'ext/**/Makefile',
  'ext/**/mkmf.log',
  'ext/**/.sitearchdir.time',
  'ext/**/.sitelibdir.time',
  'tmp',
  'build'
)

EXT_DIR = File.expand_path('ext/qt_ruby_bridge', __dir__)
NATIVE_BUILD_DIR = File.expand_path('build/native', __dir__)
GENERATOR = File.expand_path('scripts/generate_bridge.rb', __dir__)

desc 'Generate native bridge sources from system Qt headers'
task :generate_bindings do
  sh "ruby #{GENERATOR}"
end

desc 'Compile native Qt bridge'
task compile: :generate_bindings do
  sh "mkdir -p #{NATIVE_BUILD_DIR}"
  sh "cp #{File.expand_path('build/generated/qt_ruby_bridge.cpp', __dir__)} #{File.join(NATIVE_BUILD_DIR, 'qt_ruby_bridge.cpp')}"
  sh "ruby #{File.join(EXT_DIR, 'extconf.rb')}", chdir: NATIVE_BUILD_DIR
  sh 'make', chdir: NATIVE_BUILD_DIR
  sh 'mkdir -p ../qt', chdir: NATIVE_BUILD_DIR
  sh 'cp qt_ruby_bridge.so ../qt/qt_ruby_bridge.so', chdir: NATIVE_BUILD_DIR
end

Rake::TestTask.new do |t|
  t.libs << 'test'
  t.pattern = 'test/**/*_test.rb'
end

task default: :test

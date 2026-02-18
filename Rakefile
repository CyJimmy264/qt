# frozen_string_literal: true

require 'rake/clean'
require 'rake/testtask'
require 'rubygems'
require 'rubocop/rake_task'

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
GEMSPEC_PATH = File.expand_path('qt.gemspec', __dir__)
GEM_SPEC = Gem::Specification.load(GEMSPEC_PATH)
GEM_FILE = "#{GEM_SPEC.name}-#{GEM_SPEC.version}.gem"
PKG_DIR = File.expand_path('build/pkg', __dir__)
PKG_FILE = File.join(PKG_DIR, GEM_FILE)
GENERATED_CPP_PATH = File.expand_path('build/generated/qt_ruby_bridge.cpp', __dir__)
NATIVE_CPP_PATH = File.join(NATIVE_BUILD_DIR, 'qt_ruby_bridge.cpp')

desc 'Generate native bridge sources from system Qt headers'
task :generate_bindings do
  sh "ruby #{GENERATOR}"
end

desc 'Compile native Qt bridge'
task compile: :generate_bindings do
  sh "mkdir -p #{NATIVE_BUILD_DIR}"
  sh "cp #{GENERATED_CPP_PATH} #{NATIVE_CPP_PATH}"
  sh "ruby #{File.join(EXT_DIR, 'extconf.rb')}", chdir: NATIVE_BUILD_DIR
  sh 'make', chdir: NATIVE_BUILD_DIR
  sh 'mkdir -p ../qt', chdir: NATIVE_BUILD_DIR
  sh 'cp qt_ruby_bridge.so ../qt/qt_ruby_bridge.so', chdir: NATIVE_BUILD_DIR
end

Rake::TestTask.new do |t|
  t.libs << 'test'
  t.pattern = 'test/**/*_test.rb'
end

desc 'Build gem package'
task build_gem: :compile do
  sh "mkdir -p #{PKG_DIR}"
  sh "gem build #{GEMSPEC_PATH} --output #{PKG_FILE}"
end

desc 'Install gem locally (build + gem install --local)'
task install: :build_gem do
  sh "gem install --local --force #{PKG_FILE}"
end

RuboCop::RakeTask.new(:rubocop)

task default: :test

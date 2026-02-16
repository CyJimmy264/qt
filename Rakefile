# frozen_string_literal: true

require 'rake/clean'
require 'rake/testtask'
require 'rake/extensiontask'

CLEAN.include('**/*.o', '**/*.so', '**/*.bundle', '**/*.dll', '**/*.dylib', 'ext/**/Makefile')

Rake::ExtensionTask.new('qt_ruby_ext') do |ext|
  ext.lib_dir = 'lib/qt'
  ext.ext_dir = 'ext/qt_ruby_ext'
end

Rake::TestTask.new do |t|
  t.libs << 'test'
  t.pattern = 'test/**/*_test.rb'
end

task default: :test

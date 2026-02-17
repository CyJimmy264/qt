# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'qt'
  spec.version       = '0.1.0'
  spec.authors       = ['qt-ruby contributors']
  spec.email         = ['devnull@example.com']

  spec.summary       = 'Ruby bindings for Qt 6.10+'
  spec.description   = 'Qt GUI bindings for Ruby with generated bridge code from system Qt headers.'
  spec.homepage      = 'https://example.com/qt'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.1'

  spec.files = Dir[
    'lib/**/*.rb',
    'ext/**/*.{c,cc,cpp,cxx,h,hpp,rb}',
    'scripts/**/*.rb',
    'examples/**/*.rb',
    'README.md',
    'LICENSE',
    'Rakefile'
  ]

  spec.extensions = ['ext/qt_ruby_bridge/extconf.rb']
  spec.require_paths = ['lib']

  spec.add_dependency 'ffi', '~> 1.17'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'minitest', '~> 5.20'
  spec.add_development_dependency 'rubocop', '~> 1.76'
end

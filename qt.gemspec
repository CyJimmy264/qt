# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'qt-ruby'
  spec.version       = '0.1.0'
  spec.authors       = ['qt-ruby contributors']
  spec.email         = ['devnull@example.com']

  spec.summary       = 'Ruby GUI library powered by Qt 6.10+'
  spec.description   = 'Thin Ruby wrapper over a native Qt 6.10+ bridge for building GUI apps.'
  spec.homepage      = 'https://example.com/qt-ruby'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.1'

  spec.files = Dir[
    'lib/**/*.rb',
    'ext/**/*.{c,cc,cpp,cxx,h,hpp,rb}',
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
end

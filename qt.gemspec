# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'qt'
  spec.version       = '0.1.3'
  spec.authors       = ['Maksim Veynberg']
  spec.email         = ['mv@cj264.ru']

  spec.summary       = 'Ruby bindings for Qt 6.4.2+'
  spec.description   = 'Qt GUI bindings for Ruby with generated bridge code from system Qt headers.'
  spec.homepage      = 'https://github.com/CyJimmy264/qt'
  spec.license       = 'BSD-2-Clause'
  spec.required_ruby_version = '>= 3.2'

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
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/releases"
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"
  spec.metadata['rubygems_mfa_required'] = 'true'
end

# frozen_string_literal: true

require 'ffi'
require 'rbconfig'

module Qt
  module Bridge
    extend FFI::Library
    module_function

    def load!
      return true if @loaded

      ffi_lib(library_candidates)
      attach_api
      @loaded = true
    rescue LoadError, FFI::NotFoundError => e
      @loaded = false
      @load_error = e
      false
    end

    def loaded?
      !!@loaded
    end

    def load_error
      @load_error
    end

    def library_candidates
      @library_candidates ||= begin
        ext = RbConfig::CONFIG['DLEXT']
        root = File.expand_path('../..', __dir__)

        [
          File.join(root, 'build', 'qt', "qt_ruby_bridge.#{ext}"),
          File.join(root, 'lib', 'qt', "qt_ruby_bridge.#{ext}"),
          'qt_ruby_bridge'
        ]
      end
    end

    def attach_api
      return if @api_attached

      ensure_generated_api!
      Qt::BridgeAPI::FUNCTIONS.each do |fn|
        attach_function fn[:name], fn[:args], fn[:return]
      end

      @api_attached = true
    end
    private_class_method :attach_api

    def ensure_generated_api!
      return if defined?(Qt::BridgeAPI::FUNCTIONS)

      root = File.expand_path('../..', __dir__)
      generated_api = File.join(root, 'build', 'generated', 'bridge_api.rb')
      generator = File.join(root, 'scripts', 'generate_bridge.rb')
      system(RbConfig.ruby, generator) unless File.exist?(generated_api)
      require generated_api
    end
    private_class_method :ensure_generated_api!
  end
end

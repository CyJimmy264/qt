# frozen_string_literal: true

module Qt
  module Native
    module_function

    def available?
      return @available unless @available.nil?

      require_relative 'qt_ruby_ext'
      @available = !!defined?(Qt::NativeBridge)
    rescue LoadError
      @available = false
    end

    def ensure_loaded!
      return if available?

      raise NativeExtensionError,
            'Qt native extension is not available. Build it with: bundle exec rake compile'
    end

    def qt_version
      ensure_loaded!
      Qt::NativeBridge.qt_version
    end

    def show_window(title:, width:, height:)
      ensure_loaded!
      Qt::NativeBridge.show_window(title.to_s, Integer(width), Integer(height))
    end
  end
end

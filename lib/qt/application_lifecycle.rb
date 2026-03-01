# frozen_string_literal: true

module Qt
  # Tracks QApplication creation/disposal lifecycle from Ruby side.
  module ApplicationLifecycle
    def initialize(_argc = 0, _argv = [])
      @windows = []
      argv0 = if _argv.respond_to?(:[]) && !_argv.empty?
                _argv[0]
              else
                $PROGRAM_NAME
              end
      argv0 = 'ruby' if argv0.nil? || argv0.to_s.empty?
      @handle = Native.qapplication_new(Qt::StringCodec.to_qt_text(argv0))
      self.class.current = self
    end

    def register_window(window)
      @windows << window unless @windows.include?(window)
    end

    def exec
      @windows.each(&:show)
      Native.qapplication_exec(@handle)
    ensure
      dispose
    end

    def dispose
      return if @handle.nil? || (@handle.respond_to?(:null?) && @handle.null?)

      Native.qapplication_delete(@handle)
      @handle = nil
    end
  end
end

# frozen_string_literal: true

module Qt
  # Tracks QApplication creation/disposal lifecycle from Ruby side.
  module ApplicationLifecycle
    def initialize(_argc = 0, _argv = [])
      @windows = []
      # Propagate real argv0 into native QApplication creation so desktop
      # environments can derive app identity/window class from process intent.
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

      # Native returns false when teardown is rejected by safety guards
      # (e.g. non-GUI thread dispose attempt). Keep handle intact in that case.
      deleted = Native.qapplication_delete(@handle)
      return false unless deleted

      @handle = nil
      self.class.current = nil if self.class.current.equal?(self)
      true
    end
  end
end

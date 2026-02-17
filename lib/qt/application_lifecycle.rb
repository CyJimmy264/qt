# frozen_string_literal: true

module Qt
  module ApplicationLifecycle
    def initialize(_argc = 0, _argv = [])
      @windows = []
      @handle = Native.qapplication_new
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

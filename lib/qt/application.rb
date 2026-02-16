# frozen_string_literal: true

module Qt
  class Application
    attr_reader :title, :width, :height

    def initialize(title: 'Qt Ruby App', width: 800, height: 600)
      @title = title
      @width = width
      @height = height
    end

    def self.qt_version
      Native.qt_version
    end

    def run
      Native.show_window(title: title, width: width, height: height)
    end
  end
end

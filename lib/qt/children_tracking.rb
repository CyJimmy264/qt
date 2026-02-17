# frozen_string_literal: true

module Qt
  module ChildrenTracking
    def init_children_tracking!
      @children = []
    end

    def add_child(child)
      @children ||= []
      @children << child
    end
  end
end

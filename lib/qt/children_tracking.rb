# frozen_string_literal: true

module Qt
  # Child object tracking to mirror Qt parent/child ownership in Ruby.
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

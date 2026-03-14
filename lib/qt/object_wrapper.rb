# frozen_string_literal: true

module Qt
  # Wrap native QObject-derived pointers into generated Ruby wrapper instances.
  module ObjectWrapper
    module_function

    def wrap(pointer, expected_qt_class = nil)
      return nil if null_pointer?(pointer)
      return pointer if pointer.respond_to?(:handle)

      klass = resolve_wrapper_class(pointer, expected_qt_class) || fallback_wrapper_class(expected_qt_class)
      return pointer unless klass

      instantiate_wrapper(klass, pointer)
    end

    def null_pointer?(pointer)
      pointer.nil? || (pointer.respond_to?(:null?) && pointer.null?)
    end

    def resolve_wrapper_class(pointer, expected_qt_class)
      candidate_wrapper_classes(expected_qt_class).find do |klass|
        Native.qobject_inherits(pointer, klass::QT_CLASS)
      end
    end

    def candidate_wrapper_classes(expected_qt_class)
      @candidate_wrapper_classes ||= {}
      @candidate_wrapper_classes[expected_qt_class] ||= begin
        base = fallback_wrapper_class(expected_qt_class)
        wrappers = qobject_wrapper_classes
        wrappers = wrappers.select { |klass| klass <= base } if base
        wrappers.sort_by { |klass| -inheritance_depth(klass) }
      end
    end

    def qobject_wrapper_classes
      Qt.constants(false).filter_map do |const_name|
        klass = Qt.const_get(const_name, false)
        next unless klass.is_a?(Class)
        next unless klass.const_defined?(:QT_CLASS, false)
        next unless klass <= Qt::QObject

        klass
      end
    end

    def fallback_wrapper_class(expected_qt_class)
      return nil if expected_qt_class.nil? || !Qt.const_defined?(expected_qt_class, false)

      klass = Qt.const_get(expected_qt_class, false)
      return nil unless klass.is_a?(Class)
      return nil unless klass.const_defined?(:QT_CLASS, false)
      return nil unless klass <= Qt::QObject

      klass
    end

    def instantiate_wrapper(klass, pointer)
      wrapped = klass.allocate
      wrapped.instance_variable_set(:@handle, pointer)
      wrapped.init_children_tracking! if wrapped.respond_to?(:init_children_tracking!, true)
      wrapped
    end

    def inheritance_depth(klass)
      depth = 0
      current = klass
      while current.is_a?(Class)
        depth += 1
        current = current.superclass
      end
      depth
    end
  end
end

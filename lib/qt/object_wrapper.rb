# frozen_string_literal: true

module Qt
  # Wrap native QObject-derived pointers into generated Ruby wrapper instances.
  module ObjectWrapper
    module_function

    module ConstructorCacheHook
      def initialize(*args, &block)
        super
        Qt::ObjectWrapper.register_wrapper(self)
      end
    end

    def wrap(pointer, expected_qt_class = nil)
      return nil if null_pointer?(pointer)
      return pointer if pointer.respond_to?(:handle)

      cached = cached_wrapper_for(pointer)
      return cached if cached

      klass = resolve_wrapper_class(pointer, expected_qt_class) || fallback_wrapper_class(expected_qt_class)
      return pointer unless klass

      register_wrapper(instantiate_wrapper(klass, pointer))
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
      wrapped
    end

    def cached_wrapper_for(pointer)
      wrapper_cache[pointer.address]
    end

    def register_wrapper(wrapper)
      return wrapper unless wrapper.respond_to?(:handle)

      pointer = wrapper.handle
      return wrapper if null_pointer?(pointer)

      cached = cached_wrapper_for(pointer)
      return cached if cached

      cache_wrapper(wrapper)
    end

    def cache_wrapper(wrapper)
      pointer = wrapper.handle
      wrapper_cache[pointer.address] = wrapper
      ensure_destroy_hook(wrapper, pointer)
      wrapper
    end

    def invalidate_cached_wrapper(pointer_or_address, expected_wrapper = nil)
      address = pointer_or_address.is_a?(Integer) ? pointer_or_address : pointer_or_address.address
      cached = wrapper_cache[address]
      return unless cached
      return if expected_wrapper && !cached.equal?(expected_wrapper)

      wrapper_cache.delete(address)
    end

    def reset_cache!
      @wrapper_cache = {}
      @destroy_hook_addresses = {}
    end

    def install_constructor_cache_hooks!
      qobject_wrapper_classes.each do |klass|
        next if klass.instance_variable_defined?(:@__qt_object_wrapper_constructor_hook_installed)

        klass.prepend(ConstructorCacheHook)
        klass.instance_variable_set(:@__qt_object_wrapper_constructor_hook_installed, true)
      end
    end

    def wrapper_cache
      @wrapper_cache ||= {}
    end

    def destroy_hook_addresses
      @destroy_hook_addresses ||= {}
    end

    def ensure_destroy_hook(wrapper, pointer)
      address = pointer.address
      return if destroy_hook_addresses[address]

      destroy_hook_addresses[address] = true
      Qt::EventRuntime.on_internal_signal(pointer, 'destroyed()') do |_payload|
        destroy_hook_addresses.delete(address)
        Qt::EventRuntime.clear_signal_registrations_for_address(address)
        invalidate_cached_wrapper(address, wrapper)
      end
    rescue StandardError
      destroy_hook_addresses.delete(address)
      raise
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

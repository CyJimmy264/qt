# frozen_string_literal: true

module Qt
  # Owns copied Qt value objects returned through opaque FFI handles.
  module ValueWrapper
    module_function

    def wrap(handle, qt_class, delete_method)
      return nil if handle.nil? || handle.null?

      wrapper = Qt.const_get(qt_class).allocate
      wrapper.instance_variable_set(:@handle, handle)
      ObjectSpace.define_finalizer(wrapper, finalizer(delete_method, handle))
      wrapper
    end

    def finalizer(delete_method, handle)
      proc do
        Qt::Native.public_send(delete_method, handle) if Qt::Native.available?
      rescue StandardError
        nil
      end
    end
    private_class_method :finalizer
  end
end

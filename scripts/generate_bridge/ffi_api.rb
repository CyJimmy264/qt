# frozen_string_literal: true

def free_functions
  [
    { name: 'qt_ruby_qt_version', ffi_return: :string, args: [] },
    { name: 'qt_ruby_qapplication_process_events', ffi_return: :void, args: [] },
    { name: 'qt_ruby_qapplication_top_level_widgets_count', ffi_return: :int, args: [] },
    { name: 'qt_ruby_set_event_callback', ffi_return: :void, args: [:pointer] },
    { name: 'qt_ruby_watch_qobject_event', ffi_return: :void, args: %i[pointer int] },
    { name: 'qt_ruby_unwatch_qobject_event', ffi_return: :void, args: %i[pointer int] },
    { name: 'qt_ruby_set_signal_callback', ffi_return: :void, args: [:pointer] },
    { name: 'qt_ruby_qobject_connect_signal', ffi_return: :int, args: %i[pointer string] },
    { name: 'qt_ruby_qobject_disconnect_signal', ffi_return: :int, args: %i[pointer string] }
  ]
end

def all_ffi_functions(specs)
  fns = free_functions.dup

  specs.each do |spec|
    append_constructor_ffi_function(fns, spec)
    append_qapplication_delete_ffi_function(fns, spec)
    append_method_ffi_functions(fns, spec)
  end

  fns
end

def append_constructor_ffi_function(fns, spec)
  ctor_args = spec[:constructor][:parent] ? [:pointer] : []
  fns << { name: ctor_function_name(spec), ffi_return: :pointer, args: ctor_args }
end

def append_qapplication_delete_ffi_function(fns, spec)
  return unless spec[:prefix] == 'qapplication'

  fns << { name: 'qt_ruby_qapplication_delete', ffi_return: :void, args: [:pointer] }
end

def append_method_ffi_functions(fns, spec)
  spec[:methods].each do |method|
    args = [:pointer] + method[:args].map { |arg| arg[:ffi] }
    fns << { name: method_function_name(spec, method), ffi_return: method[:ffi_return], args: args }
  end
end

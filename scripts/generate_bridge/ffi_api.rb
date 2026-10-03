# frozen_string_literal: true

def free_functions(free_function_specs)
  free_function_specs.map do |spec|
    { name: spec[:name], ffi_return: spec[:ffi_return], args: spec[:args] }
  end
end

def all_ffi_functions(specs, free_function_specs:)
  fns = free_functions(free_function_specs).dup

  specs.each do |spec|
    append_constructor_ffi_function(fns, spec)
    append_qapplication_delete_ffi_function(fns, spec)
    append_method_ffi_functions(fns, spec)
  end

  value_wrapper_classes(specs, free_function_specs: free_function_specs).each do |qt_class|
    fns << { name: qt_value_delete_function_name(qt_class), ffi_return: :void, args: [:pointer] }
  end

  fns
end

def value_wrapper_classes(specs, free_function_specs: [])
  spec_classes = specs.flat_map do |spec|
    spec[:methods].filter_map { |method| method[:value_class] if method[:return_cast] == :qt_value_copy }
  end
  free_classes = free_function_specs.filter_map { |spec| spec[:value_class] }
  (spec_classes + free_classes).uniq.sort
end

def qt_value_delete_function_name(qt_class)
  "qt_ruby_#{to_snake(qt_class)}_value_delete"
end

def append_constructor_ffi_function(fns, spec)
  return if spec[:constructor][:mode] == :wrap_only

  ctor_args = constructor_ffi_args(spec)
  fns << { name: ctor_function_name(spec), ffi_return: :pointer, args: ctor_args }
end

def constructor_ffi_args(spec)
  return %i[string pointer] if spec[:constructor][:mode] == :keysequence_parent
  return [:pointer] if spec[:constructor][:parent]
  return [:string] if spec[:constructor][:mode] == :string_path
  return [:string] if spec[:constructor][:mode] == :qapplication

  []
end

def append_qapplication_delete_ffi_function(fns, spec)
  return unless spec[:prefix] == 'qapplication'

  fns << { name: 'qt_ruby_qapplication_delete', ffi_return: :bool, args: [:pointer] }
end

def append_method_ffi_functions(fns, spec)
  spec[:methods].each do |method|
    args = [:pointer] + method[:args].map { |arg| arg[:ffi] }
    fns << { name: method_function_name(spec, method), ffi_return: method[:ffi_return], args: args }
  end
end

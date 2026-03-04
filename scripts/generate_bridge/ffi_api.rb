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

  fns
end

def append_constructor_ffi_function(fns, spec)
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

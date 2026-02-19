# frozen_string_literal: true

def debug_enabled?
  ENV['QT_RUBY_GENERATOR_DEBUG'] == '1'
end

def monotonic_now
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

def debug_log(message)
  puts "[gen] #{message}" if debug_enabled?
end

def timed(label)
  start = monotonic_now
  value = yield
  elapsed = monotonic_now - start
  debug_log("#{label}=#{format('%.3fs', elapsed)}")
  value
end

def required_includes(scope)
  case scope
  when 'widgets'
    %w[QApplication QtWidgets]
  when 'qobject', 'all'
    %w[QApplication QtCore QtGui QtWidgets]
  else
    raise "Unsupported QT_RUBY_SCOPE=#{scope.inspect}. Supported: #{SUPPORTED_SCOPES.join(', ')}"
  end
end

def ffi_to_cpp_type(ffi)
  case ffi
  when :pointer then 'void*'
  when :string then 'const char*'
  when :int then 'int'
  else
    raise "Unsupported ffi type: #{ffi.inspect}"
  end
end

def ffi_return_to_cpp(ffi)
  case ffi
  when :void then 'void'
  when :pointer then 'void*'
  when :int then 'int'
  when :string then 'const char*'
  else
    raise "Unsupported ffi return: #{ffi.inspect}"
  end
end

def to_snake(name)
  name.gsub(/([a-z\d])([A-Z])/, '\\1_\\2').downcase
end

def prefix_for_qt_class(qt_class)
  core = qt_class.delete_prefix('Q')
  "q#{to_snake(core)}"
end

def ruby_safe_method_name(name)
  RUBY_RESERVED_WORDS.include?(name) ? "#{name}_" : name
end

def ruby_public_method_name(qt_name, explicit_name = nil)
  base = explicit_name || qt_name
  safe = ruby_safe_method_name(base)
  return safe unless RUNTIME_RESERVED_RUBY_METHODS.include?(safe)

  RUNTIME_METHOD_RENAMES.fetch(safe, "#{safe}_qt")
end

def ruby_safe_arg_name(name, index, used)
  base = name.to_s
  base = "arg#{index + 1}" unless base.match?(/\A[A-Za-z_]\w*\z/)
  base = "#{base}_arg" if RUBY_RESERVED_WORDS.include?(base)

  candidate = base
  counter = 1
  candidate = "#{base}_#{counter += 1}" while used.include?(candidate)
  used << candidate
  candidate
end

def ruby_arg_name_map(args)
  used = Set.new
  args.each_with_index.to_h { |arg, idx| [arg[:name], ruby_safe_arg_name(arg[:name], idx, used)] }
end

def lower_camel(name)
  return name if name.empty?

  name[0].downcase + name[1..]
end

def property_name_from_setter(qt_name)
  return nil unless qt_name.start_with?('set')
  return nil if qt_name.length <= 3

  lower_camel(qt_name.delete_prefix('set'))
end

def ctor_function_name(spec)
  "qt_ruby_#{spec[:prefix]}_new"
end

def method_function_name(spec, method)
  "qt_ruby_#{spec[:prefix]}_#{to_snake(method[:qt_name])}"
end

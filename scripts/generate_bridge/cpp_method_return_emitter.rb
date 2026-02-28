# frozen_string_literal: true

# Emits C++ return statements for generated bridge methods.
class CppMethodReturnEmitter
  def initialize(lines:, method:, invocation:)
    @lines = lines
    @method = method
    @invocation = invocation
  end

  def emit
    return emit_void if method[:ffi_return] == :void
    return emit_qstring if qstring_return?
    return emit_qvariant if qvariant_return?
    return emit_pointer if method[:ffi_return] == :pointer

    emit_value
  end

  private

  attr_reader :lines, :method, :invocation

  def qstring_return?
    method[:ffi_return] == :string && method[:return_cast] == :qstring_to_utf8
  end

  def qvariant_return?
    method[:ffi_return] == :string && method[:return_cast] == :qvariant_to_utf8
  end

  def emit_void
    lines << "  #{invocation};"
  end

  def emit_qstring
    lines << "  const QString value = #{invocation};"
    lines << '  thread_local QByteArray utf8;'
    lines << '  utf8 = value.toUtf8();'
    lines << '  return utf8.constData();'
  end

  def emit_qvariant
    lines << "  const QVariant value = #{invocation};"
    lines << '  thread_local QByteArray utf8;'
    lines << '  utf8 = value.toString().toUtf8();'
    lines << '  return utf8.constData();'
  end

  def emit_pointer
    lines << "  return const_cast<void*>(static_cast<const void*>(#{invocation}));"
  end

  def emit_value
    lines << "  return #{invocation};"
  end
end

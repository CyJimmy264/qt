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
    return emit_qobject_list if qobject_list_return?
    return emit_qdatetime if qdatetime_return?
    return emit_qdate if qdate_return?
    return emit_qtime if qtime_return?
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

  def qobject_list_return?
    method[:ffi_return] == :string && method[:return_cast] == :qobject_list_to_wrapped_array
  end

  def qdatetime_return?
    method[:ffi_return] == :string && method[:return_cast] == :qdatetime_to_utf8
  end

  def qdate_return?
    method[:ffi_return] == :string && method[:return_cast] == :qdate_to_utf8
  end

  def qtime_return?
    method[:ffi_return] == :string && method[:return_cast] == :qtime_to_utf8
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
    lines << '  utf8 = qvariant_to_bridge_string(value).toUtf8();'
    lines << '  return utf8.constData();'
  end

  def emit_qobject_list
    lines << "  const QObjectList value = #{invocation};"
    lines << '  thread_local QByteArray utf8;'
    lines << '  utf8 = qobject_list_to_bridge_string(value).toUtf8();'
    lines << '  return utf8.constData();'
  end

  def emit_qdatetime
    lines << "  const QDateTime value = #{invocation};"
    lines << '  thread_local QByteArray utf8;'
    lines << '  utf8 = qdatetime_to_bridge_string(value).toUtf8();'
    lines << '  return utf8.constData();'
  end

  def emit_qdate
    lines << "  const QDate value = #{invocation};"
    lines << '  thread_local QByteArray utf8;'
    lines << '  utf8 = qdate_to_bridge_string(value).toUtf8();'
    lines << '  return utf8.constData();'
  end

  def emit_qtime
    lines << "  const QTime value = #{invocation};"
    lines << '  thread_local QByteArray utf8;'
    lines << '  utf8 = qtime_to_bridge_string(value).toUtf8();'
    lines << '  return utf8.constData();'
  end

  def emit_pointer
    lines << "  return const_cast<void*>(static_cast<const void*>(#{invocation}));"
  end

  def emit_value
    lines << "  return #{invocation};"
  end
end

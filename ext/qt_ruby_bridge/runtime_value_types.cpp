#include "qt_ruby_runtime.hpp"

namespace QtRubyRuntime {
QList<int> qint_list_from_variant(const QVariant& value) {
  QList<int> result;
  const QVariantList values = value.toList();
  result.reserve(values.size());
  for (const QVariant& entry : values) {
    result.append(entry.toInt());
  }
  return result;
}

QVariant qvariant_from_qint_list(const QList<int>& value) {
  QVariantList result;
  result.reserve(value.size());
  for (int entry : value) {
    result.append(entry);
  }
  return result;
}
}  // namespace QtRubyRuntime

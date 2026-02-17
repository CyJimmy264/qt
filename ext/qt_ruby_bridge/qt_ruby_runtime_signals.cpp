#include "qt_ruby_runtime.hpp"

#include <QMetaMethod>
#include <QObject>
#include <QSignalMapper>
#include <QString>
#include <unordered_map>
#include <vector>

namespace QtRubyRuntime {
SignalCallback& signal_callback_ref() {
  static SignalCallback callback = nullptr;
  return callback;
}

struct SignalHandler {
  int signal_index = -1;
  QMetaObject::Connection signal_connection;
  QMetaObject::Connection mapped_connection;
  QSignalMapper* mapper = nullptr;
};

using SignalHandlersByIndex = std::unordered_map<int, std::vector<SignalHandler>>;

std::unordered_map<QObject*, SignalHandlersByIndex>& signal_handlers() {
  static std::unordered_map<QObject*, SignalHandlersByIndex> handlers;
  return handlers;
}

int resolve_signal_index(QObject* obj, const char* signal_name) {
  if (!obj || !signal_name) {
    return -1;
  }

  const QMetaObject* mo = obj->metaObject();
  QString requested = QString::fromUtf8(signal_name).trimmed();
  if (requested.isEmpty()) {
    return -1;
  }

  if (!requested.contains('(')) {
    requested += "()";
  }

  QByteArray normalized = QMetaObject::normalizedSignature(requested.toUtf8().constData());
  int index = mo->indexOfSignal(normalized.constData());
  if (index >= 0) {
    return index;
  }

  const int left = requested.indexOf('(');
  const QByteArray signal_name_only = requested.left(left).toUtf8();
  int fallback_index = -1;
  int fallback_count = 0;
  for (int i = mo->methodOffset(); i < mo->methodCount(); ++i) {
    QMetaMethod method = mo->method(i);
    if (method.methodType() != QMetaMethod::Signal) {
      continue;
    }
    if (method.name() == signal_name_only) {
      fallback_index = i;
      fallback_count += 1;
    }
  }

  if (fallback_count == 1) {
    return fallback_index;
  }

  return -1;
}
}  // namespace QtRubyRuntime

void QtRubyRuntime::set_signal_callback(void* callback_ptr) {
  signal_callback_ref() = reinterpret_cast<SignalCallback>(callback_ptr);
}

int QtRubyRuntime::qobject_connect_signal(void* object_handle, const char* signal_name) {
  if (!object_handle || !signal_name) {
    return -1;
  }

  auto* obj = static_cast<QObject*>(object_handle);
  int signal_index = resolve_signal_index(obj, signal_name);
  if (signal_index < 0) {
    return -2;
  }

  const QMetaMethod signal_method = obj->metaObject()->method(signal_index);
  auto* mapper = new QSignalMapper(obj);
  mapper->setMapping(obj, signal_index);

  const int map_slot_index = mapper->metaObject()->indexOfSlot("map()");
  if (map_slot_index < 0) {
    mapper->deleteLater();
    return -3;
  }

  const QMetaMethod map_slot = mapper->metaObject()->method(map_slot_index);
  QMetaObject::Connection signal_connection = QObject::connect(obj, signal_method, mapper, map_slot);
  if (!signal_connection) {
    mapper->deleteLater();
    return -4;
  }

  QMetaObject::Connection mapped_connection =
      QObject::connect(mapper, &QSignalMapper::mappedInt, mapper, [obj](int mapped_signal_index) {
        if (!signal_callback_ref()) {
          return;
        }
        signal_callback_ref()(obj, mapped_signal_index, nullptr);
      });

  if (!mapped_connection) {
    QObject::disconnect(signal_connection);
    mapper->deleteLater();
    return -5;
  }

  auto& by_index = signal_handlers()[obj];
  by_index[signal_index].push_back(
      SignalHandler{signal_index, signal_connection, mapped_connection, mapper});
  return signal_index;
}

int QtRubyRuntime::qobject_disconnect_signal(void* object_handle, const char* signal_name) {
  if (!object_handle) {
    return -1;
  }

  auto* obj = static_cast<QObject*>(object_handle);
  auto it = signal_handlers().find(obj);
  if (it == signal_handlers().end()) {
    return 0;
  }

  if (!signal_name) {
    int disconnected = 0;
    for (auto& [_, handlers] : it->second) {
      for (const auto& handler : handlers) {
        QObject::disconnect(handler.signal_connection);
        QObject::disconnect(handler.mapped_connection);
        if (handler.mapper) {
          handler.mapper->deleteLater();
        }
        disconnected += 1;
      }
    }
    signal_handlers().erase(it);
    return disconnected;
  }

  int signal_index = resolve_signal_index(obj, signal_name);
  if (signal_index < 0) {
    return -2;
  }

  auto by_index_it = it->second.find(signal_index);
  if (by_index_it == it->second.end()) {
    return 0;
  }

  int disconnected = 0;
  for (const auto& handler : by_index_it->second) {
    QObject::disconnect(handler.signal_connection);
    QObject::disconnect(handler.mapped_connection);
    if (handler.mapper) {
      handler.mapper->deleteLater();
    }
    disconnected += 1;
  }
  it->second.erase(by_index_it);
  if (it->second.empty()) {
    signal_handlers().erase(it);
  }
  return disconnected;
}

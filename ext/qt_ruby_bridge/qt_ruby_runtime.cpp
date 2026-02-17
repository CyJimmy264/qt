#include "qt_ruby_runtime.hpp"

#include <QApplication>
#include <QCoreApplication>
#include <QCursor>
#include <QEvent>
#include <QGuiApplication>
#include <QKeyEvent>
#include <QMetaMethod>
#include <QObject>
#include <QPoint>
#include <QResizeEvent>
#include <QSignalMapper>
#include <QString>
#include <QWidget>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace QtRubyRuntime {
EventCallback& event_callback_ref() {
  static EventCallback callback = nullptr;
  return callback;
}

SignalCallback& signal_callback_ref() {
  static SignalCallback callback = nullptr;
  return callback;
}

class KeyStateFilter : public QObject {
 protected:
  bool eventFilter(QObject* watched, QEvent* event) override {
    switch (event->type()) {
      case QEvent::KeyPress: {
        auto* key_event = static_cast<QKeyEvent*>(event);
        pressed_keys().insert(key_event->key());
        break;
      }
      case QEvent::KeyRelease: {
        auto* key_event = static_cast<QKeyEvent*>(event);
        pressed_keys().erase(key_event->key());
        break;
      }
      case QEvent::ApplicationDeactivate:
        pressed_keys().clear();
        break;
      default:
        break;
    }

    return QObject::eventFilter(watched, event);
  }

 private:
  static std::unordered_set<int>& pressed_keys() {
    static std::unordered_set<int> keys;
    return keys;
  }

 public:
  static std::unordered_set<int>& keys_ref() { return pressed_keys(); }
};

KeyStateFilter* key_filter_instance() {
  static KeyStateFilter filter;
  return &filter;
}

void ensure_key_filter_installed() {
  static bool installed = false;
  if (!installed && qApp) {
    qApp->installEventFilter(key_filter_instance());
    installed = true;
  }
}

std::unordered_map<QObject*, std::unordered_set<int>>& watched_events() {
  static std::unordered_map<QObject*, std::unordered_set<int>> events;
  return events;
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

class EventFilter : public QObject {
 protected:
  bool eventFilter(QObject* watched, QEvent* event) override {
    auto it = watched_events().find(watched);
    if (it == watched_events().end()) {
      return QObject::eventFilter(watched, event);
    }
    const int et = static_cast<int>(event->type());
    if (it->second.count(et) == 0) {
      return QObject::eventFilter(watched, event);
    }
    if (!event_callback_ref()) {
      return QObject::eventFilter(watched, event);
    }

    int a = 0;
    int b = 0;
    int c = 0;
    int d = 0;

    switch (event->type()) {
      case QEvent::MouseButtonPress:
      case QEvent::MouseButtonRelease:
      case QEvent::MouseMove: {
        auto* mouse_event = static_cast<QMouseEvent*>(event);
        const QPoint p = mouse_event->position().toPoint();
        a = p.x();
        b = p.y();
        c = static_cast<int>(mouse_event->button());
        d = static_cast<int>(mouse_event->buttons());
        break;
      }
      case QEvent::KeyPress:
      case QEvent::KeyRelease: {
        auto* key_event = static_cast<QKeyEvent*>(event);
        a = key_event->key();
        b = static_cast<int>(key_event->modifiers());
        c = key_event->isAutoRepeat() ? 1 : 0;
        d = key_event->count();
        break;
      }
      case QEvent::Resize: {
        auto* resize_event = static_cast<QResizeEvent*>(event);
        a = resize_event->size().width();
        b = resize_event->size().height();
        c = resize_event->oldSize().width();
        d = resize_event->oldSize().height();
        break;
      }
      default:
        break;
    }

    event_callback_ref()(watched, et, a, b, c, d);
    return QObject::eventFilter(watched, event);
  }
};

EventFilter* event_filter_instance() {
  static EventFilter filter;
  return &filter;
}

void ensure_event_filter_installed() {
  static bool installed = false;
  if (!installed && qApp) {
    qApp->installEventFilter(event_filter_instance());
    installed = true;
  }
}
}  // namespace QtRubyRuntime

void QtRubyRuntime::qapplication_process_events() { QCoreApplication::processEvents(); }

int QtRubyRuntime::qapplication_top_level_widgets_count() {
  return QApplication::topLevelWidgets().size();
}

int QtRubyRuntime::qapplication_mouse_x() { return QCursor::pos().x(); }
int QtRubyRuntime::qapplication_mouse_y() { return QCursor::pos().y(); }
int QtRubyRuntime::qapplication_mouse_buttons() { return static_cast<int>(QGuiApplication::mouseButtons()); }

int QtRubyRuntime::qapplication_key_down(int key) {
  ensure_key_filter_installed();
  if (!qApp) {
    return 0;
  }

  const auto& keys = KeyStateFilter::keys_ref();
  return keys.count(key) > 0 ? 1 : 0;
}

void QtRubyRuntime::set_event_callback(void* callback_ptr) {
  event_callback_ref() = reinterpret_cast<EventCallback>(callback_ptr);
  ensure_event_filter_installed();
}

void QtRubyRuntime::watch_qobject_event(void* object_handle, int event_type) {
  if (!object_handle) {
    return;
  }
  auto* obj = static_cast<QObject*>(object_handle);
  watched_events()[obj].insert(event_type);
  ensure_event_filter_installed();
}

void QtRubyRuntime::unwatch_qobject_event(void* object_handle, int event_type) {
  if (!object_handle) {
    return;
  }
  auto* obj = static_cast<QObject*>(object_handle);
  auto it = watched_events().find(obj);
  if (it == watched_events().end()) {
    return;
  }
  it->second.erase(event_type);
  if (it->second.empty()) {
    watched_events().erase(it);
  }
}

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

int QtRubyRuntime::qwidget_map_from_global_x(void* handle, int gx, int gy) {
  if (!handle) {
    return 0;
  }
  auto* widget = static_cast<QWidget*>(handle);
  return widget->mapFromGlobal(QPoint(gx, gy)).x();
}

int QtRubyRuntime::qwidget_map_from_global_y(void* handle, int gx, int gy) {
  if (!handle) {
    return 0;
  }
  auto* widget = static_cast<QWidget*>(handle);
  return widget->mapFromGlobal(QPoint(gx, gy)).y();
}

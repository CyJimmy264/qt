#include "qt_ruby_runtime.hpp"

#include <QApplication>
#include <QEvent>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QObject>
#include <QPoint>
#include <QResizeEvent>
#include <QByteArray>
#include <cstdio>
#include <cstdlib>
#include <unordered_map>
#include <unordered_set>

namespace QtRubyRuntime {
EventCallback& event_callback_ref() {
  static EventCallback callback = nullptr;
  return callback;
}

std::unordered_map<QObject*, std::unordered_set<int>>& watched_events() {
  static std::unordered_map<QObject*, std::unordered_set<int>> events;
  return events;
}

std::unordered_set<QObject*>& watched_cleanup_hooks() {
  static std::unordered_set<QObject*> hooks;
  return hooks;
}

bool event_debug_enabled() {
  static const bool enabled = [] {
    const char* raw = std::getenv("QT_RUBY_EVENT_DEBUG");
    if (!raw) {
      return false;
    }
    return raw[0] != '\0' && raw[0] != '0';
  }();
  return enabled;
}

bool ancestor_mouse_move_enabled() {
  static const bool enabled = [] {
    const char* raw = std::getenv("QT_RUBY_EVENT_ANCESTOR_MOUSE_MOVE");
    if (!raw) {
      return false;
    }
    return raw[0] != '\0' && raw[0] != '0';
  }();
  return enabled;
}

const char* event_name(int et) {
  switch (static_cast<QEvent::Type>(et)) {
    case QEvent::MouseButtonPress:
      return "MouseButtonPress";
    case QEvent::MouseButtonRelease:
      return "MouseButtonRelease";
    case QEvent::MouseMove:
      return "MouseMove";
    case QEvent::KeyPress:
      return "KeyPress";
    case QEvent::KeyRelease:
      return "KeyRelease";
    case QEvent::FocusIn:
      return "FocusIn";
    case QEvent::FocusOut:
      return "FocusOut";
    case QEvent::Enter:
      return "Enter";
    case QEvent::Leave:
      return "Leave";
    case QEvent::Resize:
      return "Resize";
    default:
      return "Other";
  }
}

const char* class_name(QObject* obj) {
  return (obj && obj->metaObject()) ? obj->metaObject()->className() : "null";
}

void log_event_dispatch(QObject* target, QObject* dispatch_target, int event_type, bool accepted, const char* stage) {
  if (!event_debug_enabled()) {
    return;
  }

  const QByteArray target_name = target ? target->objectName().toUtf8() : QByteArray();
  const QByteArray dispatch_name = dispatch_target ? dispatch_target->objectName().toUtf8() : QByteArray();
  std::fprintf(stderr,
               "[qt-ruby-event] stage=%s type=%d(%s) target=%p target_class=%s target_name=%s dispatch=%p "
               "dispatch_class=%s dispatch_name=%s accepted=%d\n",
               stage,
               event_type,
               event_name(event_type),
               static_cast<void*>(target),
               class_name(target),
               target_name.constData(),
               static_cast<void*>(dispatch_target),
               class_name(dispatch_target),
               dispatch_name.constData(),
               accepted ? 1 : 0);
}

bool supports_ancestor_dispatch(int event_type) {
  switch (static_cast<QEvent::Type>(event_type)) {
    case QEvent::MouseButtonPress:
    case QEvent::MouseButtonRelease:
      return true;
    case QEvent::MouseMove:
      return ancestor_mouse_move_enabled();
    case QEvent::KeyPress:
    case QEvent::KeyRelease:
    case QEvent::FocusIn:
    case QEvent::FocusOut:
    case QEvent::Enter:
    case QEvent::Leave:
      return true;
    default:
      return false;
  }
}

QObject* resolve_dispatch_target(QObject* target, int event_type) {
  auto& watched = watched_events();
  auto exact = watched.find(target);
  if (exact != watched.end() && exact->second.count(event_type) > 0) {
    return target;
  }

  if (!supports_ancestor_dispatch(event_type)) {
    return nullptr;
  }

  for (QObject* cur = target ? target->parent() : nullptr; cur; cur = cur->parent()) {
    auto it = watched.find(cur);
    if (it != watched.end() && it->second.count(event_type) > 0) {
      return cur;
    }
  }

  return nullptr;
}

void ensure_cleanup_hook(QObject* obj) {
  if (!obj || watched_cleanup_hooks().count(obj) > 0) {
    return;
  }
  watched_cleanup_hooks().insert(obj);

  QObject::connect(obj, &QObject::destroyed, [obj]() {
    watched_events().erase(obj);
    watched_cleanup_hooks().erase(obj);
  });
}

class EventFilter : public QObject {
 protected:
  bool eventFilter(QObject* watched, QEvent* event) override {
    if (watched_events().empty()) {
      return QObject::eventFilter(watched, event);
    }

    const int et = static_cast<int>(event->type());
    QObject* dispatch_target = resolve_dispatch_target(watched, et);
    if (!dispatch_target) {
      log_event_dispatch(watched, nullptr, et, event->isAccepted(), "skip");
      return QObject::eventFilter(watched, event);
    }

    if (!event_callback_ref()) {
      log_event_dispatch(watched, dispatch_target, et, event->isAccepted(), "no_callback");
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

    log_event_dispatch(watched, dispatch_target, et, event->isAccepted(), "dispatch");
    event_callback_ref()(dispatch_target, et, a, b, c, d);
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
  ensure_cleanup_hook(obj);
  log_event_dispatch(obj, obj, event_type, false, "watch");
  ensure_event_filter_installed();
}

void QtRubyRuntime::unwatch_qobject_event(void* object_handle, int event_type) {
  if (!object_handle) {
    return;
  }
  auto* obj = static_cast<QObject*>(object_handle);
  auto it = watched_events().find(obj);
  if (it == watched_events().end()) {
    log_event_dispatch(obj, nullptr, event_type, false, "unwatch_miss");
    return;
  }
  it->second.erase(event_type);
  if (it->second.empty()) {
    watched_events().erase(it);
  }
  log_event_dispatch(obj, obj, event_type, false, "unwatch");
}

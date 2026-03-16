#include "qt_ruby_runtime.hpp"

#include <QApplication>
#include <QByteArray>
#include <QCoreApplication>
#include <QEvent>
#include <QEventLoop>
#include <QObject>
#include <QWidget>
#include <cstdio>
#include <cstdlib>
#include <thread>
#include <unordered_map>
#include <unordered_set>

#include "../../build/generated/event_payloads.inc"

namespace QtRubyRuntime {
constexpr int kEventCallbackIgnore = 0;
constexpr int kEventCallbackContinue = 1;
constexpr int kEventCallbackConsume = 2;

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

QApplication*& tracked_qapplication_ref() {
  static QApplication* app = nullptr;
  return app;
}

std::thread::id& gui_thread_id_ref() {
  static std::thread::id id;
  return id;
}

bool& qapplication_disposed_ref() {
  static bool disposed = true;
  return disposed;
}

bool strict_thread_contract_enabled() {
  static const bool enabled = [] {
    const char* raw = std::getenv("QT_RUBY_STRICT_THREAD_CONTRACT");
    if (!raw) {
      return false;
    }
    return raw[0] != '\0' && raw[0] != '0';
  }();
  return enabled;
}

bool on_gui_thread() {
  return gui_thread_id_ref() == std::this_thread::get_id();
}

void runtime_warn(const char* message) {
  std::fprintf(stderr, "[qt-ruby-runtime] %s\n", message);
  std::fflush(stderr);
}

[[noreturn]] void strict_thread_contract_abort(const char* message) {
  runtime_warn(message);
  std::abort();
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
    case QEvent::Wheel:
      return "Wheel";
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
    case QEvent::Wheel:
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

    const QByteArray payload_json = QtRubyGeneratedEventPayloads::serialize_event_payload(et, event);
    log_event_dispatch(watched, dispatch_target, et, event->isAccepted(), "dispatch");
    const int callback_result = event_callback_ref()(dispatch_target, et, payload_json.constData());
    if (callback_result == kEventCallbackIgnore) {
      event->ignore();
    }
    if (callback_result == kEventCallbackConsume) {
      event->accept();
      return true;
    }
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

void close_top_level_windows_for_shutdown() {
  // Explicit close first: this lets widgets enqueue their own teardown work
  // before we start draining posted events.
  const auto windows = QApplication::topLevelWidgets();
  for (QWidget* window : windows) {
    if (!window) {
      continue;
    }
    window->close();
  }
}

void drain_qt_events_for_shutdown() {
  // Bounded drain loop:
  // - flush posted events
  // - process pending loop work
  // - repeat with a small cap to avoid hanging on continuously posted tasks
  // This is intentionally finite and deterministic for tests and CI.
  constexpr int kDrainIterations = 12;
  QCoreApplication::sendPostedEvents(nullptr, 0);
  for (int i = 0; i < kDrainIterations; ++i) {
    QCoreApplication::processEvents(QEventLoop::AllEvents, 5);
    QCoreApplication::sendPostedEvents(nullptr, 0);
  }
  QCoreApplication::sendPostedEvents(nullptr, 0);
  QCoreApplication::processEvents(QEventLoop::AllEvents, 5);
}
}  // namespace QtRubyRuntime

QApplication* QtRubyRuntime::qapplication_new(const char* argv0) {
  if (tracked_qapplication_ref() && !qapplication_disposed_ref()) {
    // Runtime owns a single QApplication instance. Reuse if still active.
    runtime_warn("qapplication_new called while QApplication is still active; reusing current instance");
    return tracked_qapplication_ref();
  }

  static int argc = 1;
  static QByteArray argv0_storage;
  static char* argv[] = {nullptr, nullptr};
  argv0_storage = QByteArray(argv0 ? argv0 : "ruby");
  if (argv0_storage.isEmpty()) {
    argv0_storage = QByteArray("ruby");
  }
  argv[0] = argv0_storage.data();

  auto* app = new QApplication(argc, argv);
  // GUI-thread contract: new/delete must happen on the same thread.
  tracked_qapplication_ref() = app;
  gui_thread_id_ref() = std::this_thread::get_id();
  qapplication_disposed_ref() = false;
  return app;
}

bool QtRubyRuntime::qapplication_delete(void* app_handle) {
  // Idempotent no-op for null handles.
  if (!app_handle) {
    return true;
  }

  auto* app = static_cast<QApplication*>(app_handle);
  auto* tracked = tracked_qapplication_ref();
  // Already disposed (or never tracked): treat as idempotent success.
  if (!tracked || qapplication_disposed_ref()) {
    return true;
  }

  if (app != tracked) {
    // Defensive guard against deleting foreign or stale QApplication pointers.
    if (strict_thread_contract_enabled()) {
      strict_thread_contract_abort("qapplication_delete received non-tracked QApplication handle");
    }
    runtime_warn("qapplication_delete received non-tracked QApplication handle");
    return false;
  }

  if (!on_gui_thread()) {
    // Teardown from non-GUI thread is unsafe for Qt internals/thread storage.
    if (strict_thread_contract_enabled()) {
      strict_thread_contract_abort("qapplication_delete called from non-GUI thread");
    }
    runtime_warn("qapplication_delete called from non-GUI thread");
    return false;
  }

  // Safe shutdown order for bridge-owned lifecycle:
  // 1) close top-level windows
  // 2) drain posted/pending events
  // 3) delete QApplication
  close_top_level_windows_for_shutdown();
  drain_qt_events_for_shutdown();

  delete app;
  tracked_qapplication_ref() = nullptr;
  gui_thread_id_ref() = std::thread::id{};
  qapplication_disposed_ref() = true;
  return true;
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

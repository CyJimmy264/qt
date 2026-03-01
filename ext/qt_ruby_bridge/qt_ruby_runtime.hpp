#pragma once

#include <QApplication>

namespace QtRubyRuntime {
using EventCallback = void (*)(void*, int, int, int, int, int);
using SignalCallback = void (*)(void*, int, const char*);

// Creates/owns the singleton QApplication used by the Ruby runtime bridge.
// The implementation records the creating thread as GUI thread for shutdown checks.
QApplication* qapplication_new(const char* argv0);
// Performs guarded QApplication teardown.
// Returns false when teardown is rejected by runtime safety checks.
bool qapplication_delete(void* app_handle);

void set_event_callback(void* callback_ptr);
void watch_qobject_event(void* object_handle, int event_type);
void unwatch_qobject_event(void* object_handle, int event_type);

void set_signal_callback(void* callback_ptr);
int qobject_connect_signal(void* object_handle, const char* signal_name);
int qobject_disconnect_signal(void* object_handle, const char* signal_name);
}  // namespace QtRubyRuntime

#pragma once

namespace QtRubyRuntime {
using EventCallback = void (*)(void*, int, int, int, int, int);
using SignalCallback = void (*)(void*, int, const char*);

void qapplication_process_events();
int qapplication_top_level_widgets_count();
int qapplication_mouse_x();
int qapplication_mouse_y();
int qapplication_mouse_buttons();
int qapplication_key_down(int key);

void set_event_callback(void* callback_ptr);
void watch_qobject_event(void* object_handle, int event_type);
void unwatch_qobject_event(void* object_handle, int event_type);

void set_signal_callback(void* callback_ptr);
int qobject_connect_signal(void* object_handle, const char* signal_name);
int qobject_disconnect_signal(void* object_handle, const char* signal_name);

int qwidget_map_from_global_x(void* handle, int gx, int gy);
int qwidget_map_from_global_y(void* handle, int gx, int gy);
}  // namespace QtRubyRuntime

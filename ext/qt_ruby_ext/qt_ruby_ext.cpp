#include <ruby.h>

#include <QApplication>
#include <QLabel>
#include <QString>
#include <QWidget>

static VALUE rb_mQt;
static VALUE rb_mNativeBridge;

static VALUE rb_qt_version(VALUE) {
  return rb_str_new2(qVersion());
}

static VALUE rb_show_window(VALUE, VALUE rb_title, VALUE rb_width, VALUE rb_height) {
  Check_Type(rb_title, T_STRING);

  int argc = 0;
  char** argv = nullptr;
  QApplication app(argc, argv);

  QString title = QString::fromUtf8(StringValueCStr(rb_title));
  int width = NUM2INT(rb_width);
  int height = NUM2INT(rb_height);

  QWidget window;
  window.setWindowTitle(title);
  window.resize(width, height);

  QLabel label(&window);
  label.setText(QString::fromUtf8("Hello from Ruby + Qt 6"));
  label.setAlignment(Qt::AlignCenter);
  label.setGeometry(0, 0, width, height);

  window.show();

  int result = app.exec();
  return INT2NUM(result);
}

extern "C" void Init_qt_ruby_ext() {
  rb_mQt = rb_define_module("Qt");
  rb_mNativeBridge = rb_define_module_under(rb_mQt, "NativeBridge");

  rb_define_singleton_method(rb_mNativeBridge, "qt_version", RUBY_METHOD_FUNC(rb_qt_version), 0);
  rb_define_singleton_method(rb_mNativeBridge, "show_window", RUBY_METHOD_FUNC(rb_show_window), 3);
}

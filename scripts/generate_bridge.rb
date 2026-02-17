#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tempfile'
require_relative 'specs/qt_widgets'

ROOT = File.expand_path('..', __dir__)
BUILD_DIR = File.join(ROOT, 'build')
GENERATED_DIR = File.join(BUILD_DIR, 'generated')
CPP_PATH = File.join(GENERATED_DIR, 'qt_ruby_bridge.cpp')
API_PATH = File.join(GENERATED_DIR, 'bridge_api.rb')
RUBY_WIDGETS_PATH = File.join(GENERATED_DIR, 'widgets.rb')

CLASS_SPECS = QtRubyGenerator::Specs::CLASS_SPECS

def required_includes
  CLASS_SPECS.map { |spec| spec.fetch(:include) }.uniq
end

def ffi_to_cpp_type(ffi)
  case ffi
  when :pointer then 'void*'
  when :string then 'const char*'
  when :int then 'int'
  else
    raise "Unsupported ffi type: #{ffi.inspect}"
  end
end

def ffi_return_to_cpp(ffi)
  case ffi
  when :void then 'void'
  when :pointer then 'void*'
  when :int then 'int'
  when :string then 'const char*'
  else
    raise "Unsupported ffi return: #{ffi.inspect}"
  end
end

def to_snake(name)
  name.gsub(/([a-z\d])([A-Z])/, '\\1_\\2').downcase
end

def lower_camel(name)
  return name if name.empty?

  name[0].downcase + name[1..]
end

def property_name_from_setter(qt_name)
  return nil unless qt_name.start_with?('set')
  return nil if qt_name.length <= 3

  lower_camel(qt_name.delete_prefix('set'))
end

def ctor_function_name(spec)
  "qt_ruby_#{spec[:prefix]}_new"
end

def method_function_name(spec, method)
  "qt_ruby_#{spec[:prefix]}_#{to_snake(method[:qt_name])}"
end

def free_functions
  [
    { name: 'qt_ruby_qt_version', ffi_return: :string, args: [] },
    { name: 'qt_ruby_qapplication_process_events', ffi_return: :void, args: [] },
    { name: 'qt_ruby_qapplication_top_level_widgets_count', ffi_return: :int, args: [] },
    { name: 'qt_ruby_qapplication_mouse_x', ffi_return: :int, args: [] },
    { name: 'qt_ruby_qapplication_mouse_y', ffi_return: :int, args: [] },
    { name: 'qt_ruby_qapplication_mouse_buttons', ffi_return: :int, args: [] },
    { name: 'qt_ruby_qapplication_key_down', ffi_return: :int, args: [:int] },
    { name: 'qt_ruby_set_event_callback', ffi_return: :void, args: [:pointer] },
    { name: 'qt_ruby_watch_qobject_event', ffi_return: :void, args: [:pointer, :int] },
    { name: 'qt_ruby_unwatch_qobject_event', ffi_return: :void, args: [:pointer, :int] },
    { name: 'qt_ruby_set_signal_callback', ffi_return: :void, args: [:pointer] },
    { name: 'qt_ruby_qobject_connect_signal', ffi_return: :int, args: [:pointer, :string] },
    { name: 'qt_ruby_qobject_disconnect_signal', ffi_return: :int, args: [:pointer, :string] },
    { name: 'qt_ruby_qwidget_map_from_global_x', ffi_return: :int, args: [:pointer, :int, :int] },
    { name: 'qt_ruby_qwidget_map_from_global_y', ffi_return: :int, args: [:pointer, :int, :int] }
  ]
end

def all_ffi_functions(specs)
  fns = free_functions.dup

  specs.each do |spec|
    ctor_args = spec[:constructor][:parent] ? [:pointer] : []
    fns << { name: ctor_function_name(spec), ffi_return: :pointer, args: ctor_args }

    if spec[:prefix] == 'qapplication'
      fns << { name: 'qt_ruby_qapplication_delete', ffi_return: :void, args: [:pointer] }
    end

    spec[:methods].each do |method|
      args = [:pointer] + method[:args].map { |arg| arg[:ffi] }
      fns << { name: method_function_name(spec, method), ffi_return: method[:ffi_return], args: args }
    end
  end

  fns
end

def pkg_config_cflags
  cflags = `pkg-config --cflags Qt6Widgets 2>/dev/null`.strip
  raise 'pkg-config Qt6Widgets is required' if cflags.empty?

  cflags
end

def ast_dump
  cflags = pkg_config_cflags

  Tempfile.create(['qt_ruby_probe', '.cpp']) do |file|
    required_includes.each { |inc| file.write("#include <#{inc}>\n") }
    file.flush

    cmd = "clang++ -std=c++17 -x c++ -Xclang -ast-dump=json -fsyntax-only #{cflags} #{file.path}"
    out = `#{cmd}`
    raise "clang AST dump failed: #{cmd}" unless $?.success?

    JSON.parse(out)
  end
end

def walk_ast(node, &block)
  return unless node.is_a?(Hash)

  yield node
  Array(node['inner']).each { |child| walk_ast(child, &block) }
end

def collect_class_api(ast, class_name)
  methods = []
  ctors = []

  walk_ast(ast) do |node|
    next unless node['kind'] == 'CXXRecordDecl'
    next unless node['name'] == class_name

    Array(node['inner']).each do |inner|
      case inner['kind']
      when 'CXXMethodDecl' then methods << inner['name'] if inner['name']
      when 'CXXConstructorDecl' then ctors << inner['name'] if inner['name']
      end
    end
  end

  { methods: methods.uniq, constructors: ctors.uniq }
end

def normalize_cpp_type_name(raw)
  return nil if raw.nil? || raw.empty?

  name = raw.dup
  name = name.sub(/\A(class|struct)\s+/, '')
  name = name.split('<').first
  name = name.split(/\s+/).first
  name = name.split('::').last
  name&.strip
end

def collect_class_bases(ast, class_name)
  bases = []

  walk_ast(ast) do |node|
    next unless node['kind'] == 'CXXRecordDecl'
    next unless node['name'] == class_name

    Array(node['bases']).each do |inner|
      type_info = inner['type'] || {}
      raw = type_info['desugaredQualType'] || type_info['qualType']
      base = normalize_cpp_type_name(raw)
      bases << base if base && !base.empty?
    end
  end

  bases.uniq
end

def class_has_method?(ast, class_name, method_name)
  collect_class_api(ast, class_name)[:methods].include?(method_name)
end

def build_generated_inheritance(ast, specs)
  known_qt = specs.map { |s| s[:qt_class] }
  base_cache = {}
  fetch_bases = lambda do |qt_class|
    base_cache[qt_class] ||= collect_class_bases(ast, qt_class)
  end

  super_qt_by_qt = {}

  known_qt.each do |qt_class|
    next if qt_class == 'QApplication'

    visited = {}
    prev = qt_class
    cur = qt_class

    loop do
      bases = Array(fetch_bases.call(cur))
      break if bases.empty?

      base = bases.first
      break if base.nil? || base.empty? || visited[base]

      visited[base] = true
      super_qt_by_qt[prev] ||= base

      break if known_qt.include?(base)

      prev = base
      cur = base
    end
  end

  wrapper_qt_classes = (super_qt_by_qt.keys + super_qt_by_qt.values - known_qt).uniq
  [super_qt_by_qt, wrapper_qt_classes]
end

def widget_based_qt_class?(qt_class, super_qt_by_qt)
  cur = qt_class
  while (sup = super_qt_by_qt[cur])
    return true if sup == 'QWidget'

    cur = sup
  end
  false
end

def inherited_methods_for_spec(spec, specs_by_qt, super_qt_by_qt)
  inherited = []
  cur = spec[:qt_class]

  while (sup = super_qt_by_qt[cur])
    parent_spec = specs_by_qt[sup]
    inherited.concat(parent_spec[:methods]) if parent_spec
    cur = sup
  end

  inherited
end

def generate_ruby_wrapper_class(lines, qt_class, super_ruby)
  class_decl = if super_ruby
                 "  class #{qt_class} < #{super_ruby}"
               else
                 "  class #{qt_class}"
               end
  lines << class_decl
  lines << "    QT_CLASS = '#{qt_class}'.freeze"
  lines << '    QT_API_QT_METHODS = [].freeze'
  lines << '    QT_API_RUBY_METHODS = [].freeze'
  lines << '    QT_API_PROPERTIES = [].freeze'
  lines << '  end'
  lines << ''
end

def enrich_specs_with_properties(specs, ast)
  specs.map do |spec|
    methods = spec[:methods].dup

    spec[:methods].each do |method|
      next unless method[:args].length == 1

      property = property_name_from_setter(method[:qt_name])
      next unless property
      next unless class_has_method?(ast, spec[:qt_class], property)
      next if methods.any? { |m| m[:qt_name] == property }

      arg = method[:args].first
      getter = {
        qt_name: property,
        ruby_name: property,
        ffi_return: arg[:ffi],
        args: [],
        property: property
      }
      getter[:return_cast] = :qstring_to_utf8 if arg[:ffi] == :string && arg[:cast] == :qstring
      methods << getter
    end

    spec.merge(methods: methods)
  end
end

def validate_qt_api!(ast, specs)
  errors = []

  specs.each do |spec|
    req = spec[:validate]
    api = collect_class_api(ast, spec[:qt_class])

    req[:constructors].each do |ctor|
      errors << "#{spec[:qt_class]}: constructor #{ctor} not found" unless api[:constructors].include?(ctor)
    end

    req[:methods].each do |method|
      errors << "#{spec[:qt_class]}: method #{method} not found" unless api[:methods].include?(method)
    end
  end

  return if errors.empty?

  raise "Qt AST validation failed:\n- #{errors.join("\n- ")}"
end

def arg_expr(arg)
  case arg[:cast]
  when :qstring then "as_qstring(#{arg[:name]})"
  when :alignment then "static_cast<Qt::Alignment>(#{arg[:name]})"
  when String then "static_cast<#{arg[:cast]}>(#{arg[:name]})"
  else
    arg[:name]
  end
end

def generate_cpp_constructor(lines, spec)
  name = ctor_function_name(spec)

  if spec[:constructor][:mode] == :qapplication
    lines << "extern \"C\" void* #{name}() {"
    lines << '  static int argc = 1;'
    lines << '  static char arg0[] = "qt-ruby";'
    lines << '  static char* argv[] = {arg0, nullptr};'
    lines << '  return new QApplication(argc, argv);'
    lines << '}'
    return
  end

  lines << "extern \"C\" void* #{name}(void* parent_handle) {"
  lines << "  #{spec[:constructor][:parent_type].delete('*')}* parent = static_cast<#{spec[:constructor][:parent_type]}>(parent_handle);"
  lines << "  return new #{spec[:qt_class]}(parent);"
  lines << '}'
end

def generate_cpp_delete(lines)
  lines << 'extern "C" void qt_ruby_qapplication_delete(void* app_handle) {'
  lines << '  if (!app_handle) {'
  lines << '    return;'
  lines << '  }'
  lines << ''
  lines << '  auto* app = static_cast<QApplication*>(app_handle);'
  lines << '  delete app;'
  lines << '}'
end

def generate_cpp_method(lines, spec, method)
  fn = method_function_name(spec, method)
  ret = ffi_return_to_cpp(method[:ffi_return])
  sig = ['void* handle'] + method[:args].map { |arg| "#{ffi_to_cpp_type(arg[:ffi])} #{arg[:name]}" }

  lines << "extern \"C\" #{ret} #{fn}(#{sig.join(', ')}) {"
  lines << '  if (!handle) {'
  lines << case method[:ffi_return]
           when :void
             '    return;'
           when :int
             '    return -1;'
           when :pointer
             '    return nullptr;'
           when :string
             '    return nullptr;'
           else
             '    return;'
           end
  lines << '  }'
  lines << ''
  lines << "  auto* obj = static_cast<#{spec[:qt_class]}*>(handle);"

  call_args = method[:args].map { |arg| arg_expr(arg) }.join(', ')
  invocation = "obj->#{method[:qt_name]}(#{call_args})"

  if method[:ffi_return] == :void
    lines << "  #{invocation};"
  elsif method[:ffi_return] == :string && method[:return_cast] == :qstring_to_utf8
    lines << "  const QString value = #{invocation};"
    lines << '  thread_local QByteArray utf8;'
    lines << '  utf8 = value.toUtf8();'
    lines << '  return utf8.constData();'
  else
    lines << "  return #{invocation};"
  end
  lines << '}'
end

def generate_cpp_bridge(specs)
  lines = []
  required_includes.each { |inc| lines << "#include <#{inc}>" }
  lines << '#include <QCoreApplication>'
  lines << '#include <QCursor>'
  lines << '#include <QEvent>'
  lines << '#include <QGuiApplication>'
  lines << '#include <QKeyEvent>'
  lines << '#include <QMouseEvent>'
  lines << '#include <QMetaMethod>'
  lines << '#include <QObject>'
  lines << '#include <QResizeEvent>'
  lines << '#include <QSignalMapper>'
  lines << '#include <QByteArray>'
  lines << '#include <QPoint>'
  lines << '#include <QString>'
  lines << '#include <unordered_map>'
  lines << '#include <unordered_set>'
  lines << '#include <vector>'
  lines << '#include <memory>'
  lines << '#include <string>'
  lines << ''
  lines << 'namespace {'
  lines << 'class QtRubyKeyStateFilter : public QObject {'
  lines << ' protected:'
  lines << '  bool eventFilter(QObject* watched, QEvent* event) override {'
  lines << '    switch (event->type()) {'
  lines << '    case QEvent::KeyPress: {'
  lines << '      auto* key_event = static_cast<QKeyEvent*>(event);'
  lines << '      pressed_keys().insert(key_event->key());'
  lines << '      break;'
  lines << '    }'
  lines << '    case QEvent::KeyRelease: {'
  lines << '      auto* key_event = static_cast<QKeyEvent*>(event);'
  lines << '      pressed_keys().erase(key_event->key());'
  lines << '      break;'
  lines << '    }'
  lines << '    case QEvent::ApplicationDeactivate:'
  lines << '      pressed_keys().clear();'
  lines << '      break;'
  lines << '    default:'
  lines << '      break;'
  lines << '    }'
  lines << ''
  lines << '    return QObject::eventFilter(watched, event);'
  lines << '  }'
  lines << ''
  lines << ' private:'
  lines << '  static std::unordered_set<int>& pressed_keys() {'
  lines << '    static std::unordered_set<int> keys;'
  lines << '    return keys;'
  lines << '  }'
  lines << ''
  lines << ' public:'
  lines << '  static std::unordered_set<int>& keys_ref() {'
  lines << '    return pressed_keys();'
  lines << '  }'
  lines << '};'
  lines << ''
  lines << 'QtRubyKeyStateFilter* key_filter_instance() {'
  lines << '  static QtRubyKeyStateFilter filter;'
  lines << '  return &filter;'
  lines << '}'
  lines << ''
  lines << 'void ensure_key_filter_installed() {'
  lines << '  static bool installed = false;'
  lines << '  if (!installed && qApp) {'
  lines << '    qApp->installEventFilter(key_filter_instance());'
  lines << '    installed = true;'
  lines << '  }'
  lines << '}'
  lines << ''
  lines << 'using QtRubyEventCallback = void (*)(void*, int, int, int, int, int);'
  lines << 'using QtRubySignalCallback = void (*)(void*, int, const char*);'
  lines << ''
  lines << 'QtRubyEventCallback& event_callback_ref() {'
  lines << '  static QtRubyEventCallback callback = nullptr;'
  lines << '  return callback;'
  lines << '}'
  lines << ''
  lines << 'QtRubySignalCallback& signal_callback_ref() {'
  lines << '  static QtRubySignalCallback callback = nullptr;'
  lines << '  return callback;'
  lines << '}'
  lines << ''
  lines << 'std::unordered_map<QObject*, std::unordered_set<int>>& watched_events() {'
  lines << '  static std::unordered_map<QObject*, std::unordered_set<int>> events;'
  lines << '  return events;'
  lines << '}'
  lines << ''
  lines << 'struct QtRubySignalHandler {'
  lines << '  int signal_index = -1;'
  lines << '  QMetaObject::Connection signal_connection;'
  lines << '  QMetaObject::Connection mapped_connection;'
  lines << '  QSignalMapper* mapper = nullptr;'
  lines << '};'
  lines << ''
  lines << 'using QtRubySignalHandlersByIndex = std::unordered_map<int, std::vector<QtRubySignalHandler>>;'
  lines << ''
  lines << 'std::unordered_map<QObject*, QtRubySignalHandlersByIndex>& signal_handlers() {'
  lines << '  static std::unordered_map<QObject*, QtRubySignalHandlersByIndex> handlers;'
  lines << '  return handlers;'
  lines << '}'
  lines << ''
  lines << 'int resolve_signal_index(QObject* obj, const char* signal_name) {'
  lines << '  if (!obj || !signal_name) {'
  lines << '    return -1;'
  lines << '  }'
  lines << ''
  lines << '  const QMetaObject* mo = obj->metaObject();'
  lines << '  QString requested = QString::fromUtf8(signal_name).trimmed();'
  lines << '  if (requested.isEmpty()) {'
  lines << '    return -1;'
  lines << '  }'
  lines << ''
  lines << '  if (!requested.contains(\'(\')) {'
  lines << '    requested += "()";'
  lines << '  }'
  lines << ''
  lines << '  QByteArray normalized = QMetaObject::normalizedSignature(requested.toUtf8().constData());'
  lines << '  int index = mo->indexOfSignal(normalized.constData());'
  lines << '  if (index >= 0) {'
  lines << '    return index;'
  lines << '  }'
  lines << ''
  lines << '  const int left = requested.indexOf(\'(\');'
  lines << '  const QByteArray signal_name_only = requested.left(left).toUtf8();'
  lines << '  int fallback_index = -1;'
  lines << '  int fallback_count = 0;'
  lines << '  for (int i = mo->methodOffset(); i < mo->methodCount(); ++i) {'
  lines << '    QMetaMethod method = mo->method(i);'
  lines << '    if (method.methodType() != QMetaMethod::Signal) {'
  lines << '      continue;'
  lines << '    }'
  lines << '    if (method.name() == signal_name_only) {'
  lines << '      fallback_index = i;'
  lines << '      fallback_count += 1;'
  lines << '    }'
  lines << '  }'
  lines << ''
  lines << '  if (fallback_count == 1) {'
  lines << '    return fallback_index;'
  lines << '  }'
  lines << ''
  lines << '  return -1;'
  lines << '}'
  lines << ''
  lines << 'class QtRubyEventFilter : public QObject {'
  lines << ' protected:'
  lines << '  bool eventFilter(QObject* watched, QEvent* event) override {'
  lines << '    auto it = watched_events().find(watched);'
  lines << '    if (it == watched_events().end()) {'
  lines << '      return QObject::eventFilter(watched, event);'
  lines << '    }'
  lines << '    const int et = static_cast<int>(event->type());'
  lines << '    if (it->second.count(et) == 0) {'
  lines << '      return QObject::eventFilter(watched, event);'
  lines << '    }'
  lines << '    if (!event_callback_ref()) {'
  lines << '      return QObject::eventFilter(watched, event);'
  lines << '    }'
  lines << ''
  lines << '    int a = 0;'
  lines << '    int b = 0;'
  lines << '    int c = 0;'
  lines << '    int d = 0;'
  lines << ''
  lines << '    switch (event->type()) {'
  lines << '    case QEvent::MouseButtonPress:'
  lines << '    case QEvent::MouseButtonRelease:'
  lines << '    case QEvent::MouseMove: {'
  lines << '      auto* mouse_event = static_cast<QMouseEvent*>(event);'
  lines << '      const QPoint p = mouse_event->position().toPoint();'
  lines << '      a = p.x();'
  lines << '      b = p.y();'
  lines << '      c = static_cast<int>(mouse_event->button());'
  lines << '      d = static_cast<int>(mouse_event->buttons());'
  lines << '      break;'
  lines << '    }'
  lines << '    case QEvent::KeyPress:'
  lines << '    case QEvent::KeyRelease: {'
  lines << '      auto* key_event = static_cast<QKeyEvent*>(event);'
  lines << '      a = key_event->key();'
  lines << '      b = static_cast<int>(key_event->modifiers());'
  lines << '      c = key_event->isAutoRepeat() ? 1 : 0;'
  lines << '      d = key_event->count();'
  lines << '      break;'
  lines << '    }'
  lines << '    case QEvent::Resize: {'
  lines << '      auto* resize_event = static_cast<QResizeEvent*>(event);'
  lines << '      a = resize_event->size().width();'
  lines << '      b = resize_event->size().height();'
  lines << '      c = resize_event->oldSize().width();'
  lines << '      d = resize_event->oldSize().height();'
  lines << '      break;'
  lines << '    }'
  lines << '    default:'
  lines << '      break;'
  lines << '    }'
  lines << ''
  lines << '    event_callback_ref()(watched, et, a, b, c, d);'
  lines << '    return QObject::eventFilter(watched, event);'
  lines << '  }'
  lines << '};'
  lines << ''
  lines << 'QtRubyEventFilter* event_filter_instance() {'
  lines << '  static QtRubyEventFilter filter;'
  lines << '  return &filter;'
  lines << '}'
  lines << ''
  lines << 'void ensure_event_filter_installed() {'
  lines << '  static bool installed = false;'
  lines << '  if (!installed && qApp) {'
  lines << '    qApp->installEventFilter(event_filter_instance());'
  lines << '    installed = true;'
  lines << '  }'
  lines << '}'
  lines << ''
  lines << 'QString as_qstring(const char* value, const char* fallback = "") {'
  lines << '  if (!value) {'
  lines << '    return QString::fromUtf8(fallback);'
  lines << '  }'
  lines << ''
  lines << '  return QString::fromUtf8(value);'
  lines << '}'
  lines << '}  // namespace'
  lines << ''
  lines << 'extern "C" const char* qt_ruby_qt_version() {'
  lines << '  return qVersion();'
  lines << '}'
  lines << ''
  lines << 'extern "C" void qt_ruby_qapplication_process_events() {'
  lines << '  QCoreApplication::processEvents();'
  lines << '}'
  lines << ''
  lines << 'extern "C" int qt_ruby_qapplication_top_level_widgets_count() {'
  lines << '  return QApplication::topLevelWidgets().size();'
  lines << '}'
  lines << ''
  lines << 'extern "C" int qt_ruby_qapplication_mouse_x() {'
  lines << '  return QCursor::pos().x();'
  lines << '}'
  lines << ''
  lines << 'extern "C" int qt_ruby_qapplication_mouse_y() {'
  lines << '  return QCursor::pos().y();'
  lines << '}'
  lines << ''
  lines << 'extern "C" int qt_ruby_qapplication_mouse_buttons() {'
  lines << '  return static_cast<int>(QGuiApplication::mouseButtons());'
  lines << '}'
  lines << ''
  lines << 'extern "C" int qt_ruby_qapplication_key_down(int key) {'
  lines << '  ensure_key_filter_installed();'
  lines << '  if (!qApp) {'
  lines << '    return 0;'
  lines << '  }'
  lines << ''
  lines << '  const auto& keys = QtRubyKeyStateFilter::keys_ref();'
  lines << '  return keys.count(key) > 0 ? 1 : 0;'
  lines << '}'
  lines << ''
  lines << 'extern "C" void qt_ruby_set_event_callback(void* callback_ptr) {'
  lines << '  event_callback_ref() = reinterpret_cast<QtRubyEventCallback>(callback_ptr);'
  lines << '  ensure_event_filter_installed();'
  lines << '}'
  lines << ''
  lines << 'extern "C" void qt_ruby_watch_qobject_event(void* object_handle, int event_type) {'
  lines << '  if (!object_handle) {'
  lines << '    return;'
  lines << '  }'
  lines << '  auto* obj = static_cast<QObject*>(object_handle);'
  lines << '  watched_events()[obj].insert(event_type);'
  lines << '  ensure_event_filter_installed();'
  lines << '}'
  lines << ''
  lines << 'extern "C" void qt_ruby_unwatch_qobject_event(void* object_handle, int event_type) {'
  lines << '  if (!object_handle) {'
  lines << '    return;'
  lines << '  }'
  lines << '  auto* obj = static_cast<QObject*>(object_handle);'
  lines << '  auto it = watched_events().find(obj);'
  lines << '  if (it == watched_events().end()) {'
  lines << '    return;'
  lines << '  }'
  lines << '  it->second.erase(event_type);'
  lines << '  if (it->second.empty()) {'
  lines << '    watched_events().erase(it);'
  lines << '  }'
  lines << '}'
  lines << ''
  lines << 'extern "C" void qt_ruby_set_signal_callback(void* callback_ptr) {'
  lines << '  signal_callback_ref() = reinterpret_cast<QtRubySignalCallback>(callback_ptr);'
  lines << '}'
  lines << ''
  lines << 'extern "C" int qt_ruby_qobject_connect_signal(void* object_handle, const char* signal_name) {'
  lines << '  if (!object_handle || !signal_name) {'
  lines << '    return -1;'
  lines << '  }'
  lines << ''
  lines << '  auto* obj = static_cast<QObject*>(object_handle);'
  lines << '  int signal_index = resolve_signal_index(obj, signal_name);'
  lines << '  if (signal_index < 0) {'
  lines << '    return -2;'
  lines << '  }'
  lines << ''
  lines << '  const QMetaMethod signal_method = obj->metaObject()->method(signal_index);'
  lines << '  auto* mapper = new QSignalMapper(obj);'
  lines << '  mapper->setMapping(obj, signal_index);'
  lines << ''
  lines << '  const int map_slot_index = mapper->metaObject()->indexOfSlot("map()");'
  lines << '  if (map_slot_index < 0) {'
  lines << '    mapper->deleteLater();'
  lines << '    return -3;'
  lines << '  }'
  lines << ''
  lines << '  const QMetaMethod map_slot = mapper->metaObject()->method(map_slot_index);'
  lines << '  QMetaObject::Connection signal_connection = QObject::connect(obj, signal_method, mapper, map_slot);'
  lines << '  if (!signal_connection) {'
  lines << '    mapper->deleteLater();'
  lines << '    return -4;'
  lines << '  }'
  lines << ''
  lines << '  QMetaObject::Connection mapped_connection = QObject::connect(mapper, &QSignalMapper::mappedInt, mapper, [obj](int mapped_signal_index) {'
  lines << '    if (!signal_callback_ref()) {'
  lines << '      return;'
  lines << '    }'
  lines << '    signal_callback_ref()(obj, mapped_signal_index, nullptr);'
  lines << '  });'
  lines << ''
  lines << '  if (!mapped_connection) {'
  lines << '    QObject::disconnect(signal_connection);'
  lines << '    mapper->deleteLater();'
  lines << '    return -5;'
  lines << '  }'
  lines << ''
  lines << '  auto& by_index = signal_handlers()[obj];'
  lines << '  by_index[signal_index].push_back(QtRubySignalHandler{signal_index, signal_connection, mapped_connection, mapper});'
  lines << '  return signal_index;'
  lines << '}'
  lines << ''
  lines << 'extern "C" int qt_ruby_qobject_disconnect_signal(void* object_handle, const char* signal_name) {'
  lines << '  if (!object_handle) {'
  lines << '    return -1;'
  lines << '  }'
  lines << ''
  lines << '  auto* obj = static_cast<QObject*>(object_handle);'
  lines << '  auto it = signal_handlers().find(obj);'
  lines << '  if (it == signal_handlers().end()) {'
  lines << '    return 0;'
  lines << '  }'
  lines << ''
  lines << '  if (!signal_name) {'
  lines << '    int disconnected = 0;'
  lines << '    for (auto& [_, handlers] : it->second) {'
  lines << '      for (const auto& handler : handlers) {'
  lines << '        QObject::disconnect(handler.signal_connection);'
  lines << '        QObject::disconnect(handler.mapped_connection);'
  lines << '        if (handler.mapper) {'
  lines << '          handler.mapper->deleteLater();'
  lines << '        }'
  lines << '        disconnected += 1;'
  lines << '      }'
  lines << '    }'
  lines << '    signal_handlers().erase(it);'
  lines << '    return disconnected;'
  lines << '  }'
  lines << ''
  lines << '  int signal_index = resolve_signal_index(obj, signal_name);'
  lines << '  if (signal_index < 0) {'
  lines << '    return -2;'
  lines << '  }'
  lines << ''
  lines << '  auto by_index_it = it->second.find(signal_index);'
  lines << '  if (by_index_it == it->second.end()) {'
  lines << '    return 0;'
  lines << '  }'
  lines << ''
  lines << '  int disconnected = 0;'
  lines << '  for (const auto& handler : by_index_it->second) {'
  lines << '    QObject::disconnect(handler.signal_connection);'
  lines << '    QObject::disconnect(handler.mapped_connection);'
  lines << '    if (handler.mapper) {'
  lines << '      handler.mapper->deleteLater();'
  lines << '    }'
  lines << '    disconnected += 1;'
  lines << '  }'
  lines << '  it->second.erase(by_index_it);'
  lines << '  if (it->second.empty()) {'
  lines << '    signal_handlers().erase(it);'
  lines << '  }'
  lines << '  return disconnected;'
  lines << '}'
  lines << ''
  lines << 'extern "C" int qt_ruby_qwidget_map_from_global_x(void* handle, int gx, int gy) {'
  lines << '  if (!handle) {'
  lines << '    return 0;'
  lines << '  }'
  lines << ''
  lines << '  auto* widget = static_cast<QWidget*>(handle);'
  lines << '  return widget->mapFromGlobal(QPoint(gx, gy)).x();'
  lines << '}'
  lines << ''
  lines << 'extern "C" int qt_ruby_qwidget_map_from_global_y(void* handle, int gx, int gy) {'
  lines << '  if (!handle) {'
  lines << '    return 0;'
  lines << '  }'
  lines << ''
  lines << '  auto* widget = static_cast<QWidget*>(handle);'
  lines << '  return widget->mapFromGlobal(QPoint(gx, gy)).y();'
  lines << '}'
  lines << ''

  specs.each do |spec|
    generate_cpp_constructor(lines, spec)
    lines << ''

    spec[:methods].each do |method|
      generate_cpp_method(lines, spec, method)
      lines << ''
    end
  end

  generate_cpp_delete(lines)
  lines.join("\n") + "\n"
end

def generate_bridge_api(specs)
  lines = []
  lines << '# frozen_string_literal: true'
  lines << ''
  lines << 'module Qt'
  lines << '  module BridgeAPI'
  lines << '    FUNCTIONS = ['
  all_ffi_functions(specs).each do |fn|
    args = fn[:args].map { |arg| ":#{arg}" }.join(', ')
    lines << "      { name: :#{fn[:name]}, args: [#{args}], return: :#{fn[:ffi_return]} },"
  end
  lines << '    ].freeze'
  lines << '  end'
  lines << 'end'
  lines.join("\n") + "\n"
end

def generate_ruby_qapplication(lines, spec)
  qt_method_names = spec[:methods].map { |method| method[:qt_name] }.uniq
  ruby_method_names = spec[:methods].flat_map do |method|
    ruby_name = method[:ruby_name]
    snake = to_snake(ruby_name)
    snake == ruby_name ? [ruby_name] : [ruby_name, snake]
  end.uniq
  properties = spec[:methods].filter_map { |method| method[:property] }.uniq

  lines << '  class QApplication'
  lines << "    QT_CLASS = '#{spec[:qt_class]}'.freeze"
  lines << "    QT_API_QT_METHODS = #{qt_method_names.inspect}.freeze"
  lines << "    QT_API_RUBY_METHODS = #{ruby_method_names.map(&:to_sym).inspect}.freeze"
  lines << "    QT_API_PROPERTIES = #{properties.map(&:to_sym).inspect}.freeze"
  lines << ''
  lines << '    attr_reader :handle'
  lines << ''
  lines << '    class << self'
  lines << '      def current'
  lines << '        Thread.current[:qt_ruby_current_app]'
  lines << '      end'
  lines << ''
  lines << '      def current=(app)'
  lines << '        Thread.current[:qt_ruby_current_app] = app'
  lines << '      end'

  Array(spec[:class_methods]).each do |method|
    ruby_name = method[:ruby_name]
    snake_alias = to_snake(ruby_name)
    args = Array(method[:args]).join(', ')

    lines << ''
    lines << "      def #{ruby_name}(#{args})"
    if method[:native]
      native_args = Array(method[:args]).join(', ')
      call_suffix = native_args.empty? ? '' : "(#{native_args})"
      lines << "        Native.#{method[:native]}#{call_suffix}"
    else
      lines << '        nil'
    end
    lines << '      end'
    lines << "      alias_method :#{snake_alias}, :#{ruby_name}" if snake_alias != ruby_name
  end

  lines << '    end'
  lines << ''
  lines << '    def initialize(_argc = 0, _argv = [])'
  lines << '      @windows = []'
  lines << '      @handle = Native.qapplication_new'
  lines << '      self.class.current = self'
  lines << '    end'
  lines << ''
  lines << '    def register_window(window)'
  lines << '      @windows << window unless @windows.include?(window)'
  lines << '    end'
  lines << ''
  lines << '    def exec'
  lines << '      @windows.each(&:show)'
  lines << '      Native.qapplication_exec(@handle)'
  lines << '    ensure'
  lines << '      dispose'
  lines << '    end'
  lines << ''
  lines << '    def q_inspect'
  lines << '      property_values = {}'
  lines << '      self.class::QT_API_PROPERTIES.each do |property|'
  lines << '        begin'
  lines << '          property_values[property] = public_send(property)'
  lines << '        rescue StandardError => e'
  lines << '          property_values[property] = { error: e.class.name, message: e.message }'
  lines << '        end'
  lines << '      end'
  lines << ''
  lines << '      {'
  lines << '        qt_class: self.class::QT_CLASS,'
  lines << '        ruby_class: self.class.name,'
  lines << '        handle: @handle,'
  lines << '        qt_methods: self.class::QT_API_QT_METHODS,'
  lines << '        ruby_methods: self.class::QT_API_RUBY_METHODS,'
  lines << '        properties: property_values'
  lines << '      }'
  lines << '    end'
  lines << '    alias_method :qt_inspect, :q_inspect'
  lines << '    alias_method :to_h, :q_inspect'
  lines << ''
  lines << '    def dispose'
  lines << '      return if @handle.nil? || (@handle.respond_to?(:null?) && @handle.null?)'
  lines << ''
  lines << '      Native.qapplication_delete(@handle)'
  lines << '      @handle = nil'
  lines << '    end'
  lines << '  end'
  lines << ''
end

def generate_ruby_widget_class(lines, spec, specs_by_qt, super_qt_by_qt, qt_to_ruby)
  inherited_methods = inherited_methods_for_spec(spec, specs_by_qt, super_qt_by_qt)
  all_methods = (inherited_methods + spec[:methods]).uniq { |m| m[:qt_name] }

  qt_method_names = all_methods.map { |method| method[:qt_name] }.uniq
  ruby_method_names = all_methods.flat_map do |method|
    ruby_name = method[:ruby_name]
    snake = to_snake(ruby_name)
    snake == ruby_name ? [ruby_name] : [ruby_name, snake]
  end.uniq
  properties = all_methods.filter_map { |method| method[:property] }.uniq

  super_qt = super_qt_by_qt[spec[:qt_class]]
  super_ruby = super_qt ? qt_to_ruby[super_qt] : nil
  widget_based = spec[:qt_class] != 'QWidget' && widget_based_qt_class?(spec[:qt_class], super_qt_by_qt)

  class_decl = if super_ruby
                 "  class #{spec[:ruby_class]} < #{super_ruby}"
               else
                 "  class #{spec[:ruby_class]}"
               end
  lines << class_decl
  lines << "    QT_CLASS = '#{spec[:qt_class]}'.freeze"
  lines << "    QT_API_QT_METHODS = #{qt_method_names.inspect}.freeze"
  lines << "    QT_API_RUBY_METHODS = #{ruby_method_names.map(&:to_sym).inspect}.freeze"
  lines << "    QT_API_PROPERTIES = #{properties.map(&:to_sym).inspect}.freeze"
  lines << ''
  lines << '    attr_reader :handle'
  lines << '    attr_reader :children' if spec[:ruby_class] == 'QWidget' || widget_based
  lines << '    include EventRuntime::WidgetMethods'
  lines << ''

  if spec[:constructor][:parent]
    lines << '    def initialize(parent = nil)'
    lines << "      @handle = Native.#{spec[:prefix]}_new(parent&.handle)"
    lines << '      @children = []' if spec[:ruby_class] == 'QWidget' || widget_based
    if spec[:ruby_class] == 'QWidget'
      lines << '      if parent'
      lines << '        parent.add_child(self)'
      lines << '      else'
      lines << '        app = QApplication.current'
      lines << '        app&.register_window(self)'
      lines << '      end'
    elsif spec[:constructor][:register_in_parent]
      lines << '      parent.add_child(self) if parent&.respond_to?(:add_child)'
    end
  else
    lines << '    def initialize(_argc = 0, _argv = [])'
    lines << "      @handle = Native.#{spec[:prefix]}_new"
  end

  lines << '      yield self if block_given?'
  lines << '    end'
  lines << ''

  if spec[:ruby_class] == 'QWidget' || widget_based
    lines << '    def add_child(child)'
    lines << '      @children ||= []'
    lines << '      @children << child'
    lines << '    end'
    lines << ''
  end

  lines << '    def q_inspect'
  lines << '      property_values = {}'
  lines << '      self.class::QT_API_PROPERTIES.each do |property|'
  lines << '        begin'
  lines << '          property_values[property] = public_send(property)'
  lines << '        rescue StandardError => e'
  lines << '          property_values[property] = { error: e.class.name, message: e.message }'
  lines << '        end'
  lines << '      end'
  lines << ''
  lines << '      {'
  lines << '        qt_class: self.class::QT_CLASS,'
  lines << '        ruby_class: self.class.name,'
  lines << '        handle: @handle,'
  lines << '        qt_methods: self.class::QT_API_QT_METHODS,'
  lines << '        ruby_methods: self.class::QT_API_RUBY_METHODS,'
  lines << '        properties: property_values'
  lines << '      }'
  lines << '    end'
  lines << '    alias_method :qt_inspect, :q_inspect'
  lines << '    alias_method :to_h, :q_inspect'
  lines << ''
  spec[:methods].each do |method|
    ruby_name = method[:ruby_name]
    snake_alias = to_snake(ruby_name)
    ruby_args = method[:args].map { |arg| arg[:name] }.join(', ')
    lines << "    def #{ruby_name}(#{ruby_args})"
    call_args = ['@handle'] + method[:args].map { |arg| arg[:name] }
    lines << "      Native.#{spec[:prefix]}_#{to_snake(method[:qt_name])}(#{call_args.join(', ')})"
    lines << '    end'
    lines << "    alias_method :#{snake_alias}, :#{ruby_name}" if snake_alias != ruby_name
    if method[:property]
      snake_property = to_snake(method[:property])
      lines << "    def #{method[:property]}=(value)"
      lines << "      set#{method[:property][0].upcase}#{method[:property][1..]}(value)"
      lines << '    end'
      if snake_property != method[:property]
        lines << "    alias_method :#{snake_property}=, :#{method[:property]}="
      end
      lines << ''
    end
    lines << ''
  end

  lines << '  end'
  lines << ''
end

def generate_ruby_widgets(specs, super_qt_by_qt, wrapper_qt_classes)
  lines = []
  lines << '# frozen_string_literal: true'
  lines << ''
  lines << 'module Qt'

  qapplication_spec = specs.find { |spec| spec[:ruby_class] == 'QApplication' }
  generate_ruby_qapplication(lines, qapplication_spec)

  specs_by_qt = specs.each_with_object({}) { |s, map| map[s[:qt_class]] = s }
  qt_to_ruby = specs.each_with_object({}) { |s, map| map[s[:qt_class]] = s[:ruby_class] }
  wrapper_qt_classes.each { |qt_class| qt_to_ruby[qt_class] = qt_class }
  qts_to_emit = (wrapper_qt_classes + specs.map { |s| s[:qt_class] }.reject { |q| q == 'QApplication' }).uniq

  emitted = {}
  emit_qt = lambda do |qt_class|
    return if emitted[qt_class]

    super_qt = super_qt_by_qt[qt_class]
    emit_qt.call(super_qt) if super_qt && qts_to_emit.include?(super_qt)

    spec = specs_by_qt[qt_class]
    if spec
      generate_ruby_widget_class(lines, spec, specs_by_qt, super_qt_by_qt, qt_to_ruby)
    else
      generate_ruby_wrapper_class(lines, qt_class, super_qt ? qt_to_ruby[super_qt] : nil)
    end

    emitted[qt_class] = true
  end

  qts_to_emit.sort.each { |qt_class| emit_qt.call(qt_class) }

  lines << 'end'
  lines.join("\n") + "\n"
end

ast = ast_dump
validate_qt_api!(ast, CLASS_SPECS)
effective_specs = enrich_specs_with_properties(CLASS_SPECS, ast)
super_qt_by_qt, wrapper_qt_classes = build_generated_inheritance(ast, effective_specs)

FileUtils.mkdir_p(File.dirname(CPP_PATH))
File.write(CPP_PATH, generate_cpp_bridge(effective_specs))
FileUtils.mkdir_p(File.dirname(API_PATH))
File.write(API_PATH, generate_bridge_api(effective_specs))
FileUtils.mkdir_p(File.dirname(RUBY_WIDGETS_PATH))
File.write(RUBY_WIDGETS_PATH, generate_ruby_widgets(effective_specs, super_qt_by_qt, wrapper_qt_classes))

puts "Generated #{CPP_PATH}"
puts "Generated #{API_PATH}"
puts "Generated #{RUBY_WIDGETS_PATH}"

# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../../../../lib', __dir__))
require 'qt'

WINDOW_W = 980
WINDOW_H = 640
SIDEBAR_W = 300

THEMES = {
  light: {
    root: 'background-color: #f5f7fb; border: 1px solid #dbe1ec;',
    card: 'background-color: #ffffff; border: 1px solid #d5dce8; color: #0f172a;',
    title: 'background-color: #ffffff; border: 1px solid #cbd5e1; color: #0f172a; font-size: 17px; font-weight: 800;',
    button: 'background-color: #ffffff; border: 1px solid #94a3b8; color: #0f172a; font-size: 12px; font-weight: 700;',
    button_active: 'background-color: #dbeafe; border: 2px solid #2563eb; color: #0f172a; font-size: 12px; font-weight: 800;',
    input: 'background-color: #ffffff; border: 1px solid #a8b3c6; color: #0f172a; font-size: 12px;'
  },
  dark: {
    root: 'background-color: #0b1220; border: 1px solid #1f2a44;',
    card: 'background-color: #101a2d; border: 1px solid #334155; color: #e2e8f0;',
    title: 'background-color: #0f172a; border: 1px solid #334155; color: #f8fafc; font-size: 17px; font-weight: 800;',
    button: 'background-color: #111827; border: 1px solid #475569; color: #e2e8f0; font-size: 12px; font-weight: 700;',
    button_active: 'background-color: #1d4ed8; border: 2px solid #60a5fa; color: #f8fafc; font-size: 12px; font-weight: 800;',
    input: 'background-color: #0b1220; border: 1px solid #475569; color: #e2e8f0; font-size: 12px;'
  }
}.freeze

app = QApplication.new(0, [])
window = QWidget.new do |w|
  w.set_window_title('Qt Ruby Widget Gallery Lite (inspired by PySide widgetsgallery)')
  w.set_geometry(70, 60, WINDOW_W, WINDOW_H)
end

root = QLabel.new(window)
left = QLabel.new(window)
right = QLabel.new(window)

headline = QLabel.new(window)
headline.set_alignment(Qt::AlignCenter)
headline.set_text('Widget Gallery Lite')

subtitle = QLabel.new(window)
subtitle.set_alignment(Qt::AlignCenter)
subtitle.set_text('Inspired by PySide widgetsgallery: theme toggle, interactive controls, status area')

name_label = QLabel.new(window)
name_label.set_alignment(Qt::AlignCenter)
name_label.set_text('Name input')

name_input = QLineEdit.new(window)
name_input.set_placeholder_text('Type your name...')

name_echo = QLabel.new(window)
name_echo.set_alignment(Qt::AlignCenter)
name_echo.set_text('Hello, stranger')

counter_label = QLabel.new(window)
counter_label.set_alignment(Qt::AlignCenter)
counter_label.set_text('Counter: 0')

counter = 0

actions = [
  { key: :plus, text: 'INCREMENT' },
  { key: :minus, text: 'DECREMENT' },
  { key: :reset, text: 'RESET' },
  { key: :theme, text: 'TOGGLE THEME' }
]

actions.each { |a| a[:view] = QPushButton.new(window) }
actions.each { |a| a[:view].set_text(a[:text]) }

status = QLabel.new(window)
status.set_alignment(Qt::AlignCenter)
status.set_text('Ready')

current_theme = :light

layout_ui = lambda do
  ww = window.width
  wh = window.height
  sidebar_x = ww - SIDEBAR_W

  root.set_geometry(0, 0, ww, wh)

  left.set_geometry(16, 16, ww - SIDEBAR_W - 32, wh - 32)
  headline.set_geometry(34, 34, ww - SIDEBAR_W - 68, 40)
  subtitle.set_geometry(34, 82, ww - SIDEBAR_W - 68, 34)

  name_label.set_geometry(34, 142, ww - SIDEBAR_W - 68, 30)
  name_input.set_geometry(34, 178, ww - SIDEBAR_W - 68, 38)
  name_echo.set_geometry(34, 224, ww - SIDEBAR_W - 68, 38)
  counter_label.set_geometry(34, 272, ww - SIDEBAR_W - 68, 38)

  right.set_geometry(sidebar_x, 0, SIDEBAR_W, wh)
  actions.each_with_index do |action, idx|
    action[:view].set_geometry(sidebar_x + 18, 28 + idx * 52, SIDEBAR_W - 36, 40)
  end
  status.set_geometry(sidebar_x + 18, wh - 84, SIDEBAR_W - 36, 56)
end

apply_theme = lambda do
  theme = THEMES.fetch(current_theme)
  root.set_style_sheet(theme[:root])
  left.set_style_sheet(theme[:card])
  right.set_style_sheet(theme[:card])
  headline.set_style_sheet(theme[:title])
  subtitle.set_style_sheet(theme[:card])
  name_label.set_style_sheet(theme[:card])
  name_input.set_style_sheet(theme[:input])
  name_echo.set_style_sheet(theme[:card])
  counter_label.set_style_sheet(theme[:card])
  status.set_style_sheet(theme[:card])
  actions.each { |a| a[:view].set_style_sheet(theme[:button]) }
end

flash = lambda do |button|
  theme = THEMES.fetch(current_theme)
  button.set_style_sheet(theme[:button_active])
  QApplication.process_events
  sleep(0.03)
  button.set_style_sheet(theme[:button])
end

set_name_echo = lambda do
  text = name_input.text.to_s.strip
  name_echo.set_text(text.empty? ? 'Hello, stranger' : "Hello, #{text}")
end

set_counter = lambda do
  counter_label.set_text("Counter: #{counter}")
end

perform = lambda do |key, view|
  flash.call(view)

  case key
  when :plus
    counter += 1
    set_counter.call
    status.set_text('Incremented')
  when :minus
    counter -= 1
    set_counter.call
    status.set_text('Decremented')
  when :reset
    counter = 0
    set_counter.call
    name_input.set_text('')
    set_name_echo.call
    status.set_text('Reset all')
  when :theme
    current_theme = (current_theme == :light ? :dark : :light)
    apply_theme.call
    status.set_text("Theme: #{current_theme}")
  end
end

actions.each do |action|
  action[:view].connect('clicked') do
    perform.call(action[:key], action[:view])
  end
end

name_input.connect('textChanged') { set_name_echo.call }
window.on(:resize) { layout_ui.call }

layout_ui.call
apply_theme.call
window.show
QApplication.process_events

while window.is_visible != 0
  QApplication.process_events
  sleep(0.01)
end

app.dispose

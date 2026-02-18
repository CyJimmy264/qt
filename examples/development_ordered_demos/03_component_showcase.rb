# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'qt'

WINDOW_W = 980
WINDOW_H = 620
PANEL_W = 280

BASE_BG = 'background-color: #f4f4f5; border: 1px solid #d4d4d8;'
CARD_LIGHT = 'background-color: #ffffff; border: 1px solid #d4d4d8; color: #111827; font-size: 12px;'
CARD_DARK = 'background-color: #1f2937; border: 1px solid #374151; color: #f3f4f6; font-size: 12px;'
TITLE_LIGHT = 'background-color: #ffffff; border: 1px solid #d4d4d8; color: #111827; font-size: 16px; font-weight: 800;'
TITLE_DARK = 'background-color: #111827; border: 1px solid #374151; color: #f9fafb; font-size: 16px; font-weight: 800;'
BTN_LIGHT = 'background-color: #ffffff; border: 1px solid #a1a1aa; color: #111827; font-size: 12px; font-weight: 700;'
BTN_DARK = 'background-color: #111827; border: 1px solid #6b7280; color: #f9fafb; font-size: 12px; font-weight: 700;'
BTN_ACTIVE_LIGHT = 'background-color: #dbeafe; border: 2px solid #3b82f6; color: #111827; font-size: 12px; font-weight: 800;'
BTN_ACTIVE_DARK = 'background-color: #1e3a8a; border: 2px solid #60a5fa; color: #f9fafb; font-size: 12px; font-weight: 800;'

app = QApplication.new(0, [])
window = QWidget.new do |w|
  w.set_window_title('Qt Ruby Component Showcase')
  w.set_geometry(90, 70, WINDOW_W, WINDOW_H)
end

root_bg = QLabel.new(window)
root_bg.set_geometry(0, 0, WINDOW_W, WINDOW_H)
root_bg.set_style_sheet(BASE_BG)

preview_panel = QLabel.new(window)
preview_panel.set_geometry(16, 16, WINDOW_W - PANEL_W - 28, WINDOW_H - 32)

preview_title = QLabel.new(window)
preview_title.set_geometry(32, 32, WINDOW_W - PANEL_W - 60, 36)
preview_title.set_alignment(Qt::AlignCenter)
preview_title.set_text('Preview Area (QVBoxLayout + Dynamic Widgets)')

preview_host = QWidget.new(window)
preview_host.set_geometry(32, 80, WINDOW_W - PANEL_W - 60, WINDOW_H - 112)
layout = QVBoxLayout.new(preview_host)
preview_host.set_layout(layout)

side_panel = QLabel.new(window)
side_panel.set_geometry(WINDOW_W - PANEL_W, 0, PANEL_W, WINDOW_H)

status = QLabel.new(window)
status.set_geometry(WINDOW_W - PANEL_W + 16, 16, PANEL_W - 32, 64)
status.set_alignment(Qt::AlignCenter)
status.set_text("Ready\nitems: 0")

api_box = QLabel.new(window)
api_box.set_geometry(WINDOW_W - PANEL_W + 16, 88, PANEL_W - 32, 70)
api_box.set_alignment(Qt::AlignCenter)
api_box.set_text('Classes:\nQWidget QLabel QPushButton QVBoxLayout')

buttons = [
  { key: :add_label, text: 'ADD LABEL', y_offset: 176 },
  { key: :add_button, text: 'ADD PUSHBUTTON', y_offset: 222 },
  { key: :theme, text: 'TOGGLE THEME', y_offset: 268 },
  { key: :inspect, text: 'INSPECT LAST', y_offset: 314 },
  { key: :remove, text: 'REMOVE LAST', y_offset: 360 },
  { key: :clear, text: 'CLEAR ALL', y_offset: 406 }
]

buttons.each do |btn|
  view = QPushButton.new(window)
  view.set_geometry(WINDOW_W - PANEL_W + 16, btn[:y_offset], PANEL_W - 32, 36)
  view.set_text(btn[:text])
  btn[:view] = view
end

hint = QLabel.new(window)
hint.set_geometry(WINDOW_W - PANEL_W + 16, WINDOW_H - 116, PANEL_W - 32, 96)
hint.set_alignment(Qt::AlignCenter)
hint.set_text("Mouse controls:\n- Click side buttons\n- Resize window and see layout adapt")

items = []
counter = 1
dark = false

layout_ui = lambda do
  ww = window.width
  wh = window.height
  side_x = ww - PANEL_W

  root_bg.set_geometry(0, 0, ww, wh)
  preview_panel.set_geometry(16, 16, ww - PANEL_W - 28, wh - 32)
  preview_title.set_geometry(32, 32, ww - PANEL_W - 60, 36)
  preview_host.set_geometry(32, 80, ww - PANEL_W - 60, wh - 112)

  side_panel.set_geometry(side_x, 0, PANEL_W, wh)
  status.set_geometry(side_x + 16, 16, PANEL_W - 32, 64)
  api_box.set_geometry(side_x + 16, 88, PANEL_W - 32, 70)
  hint.set_geometry(side_x + 16, wh - 116, PANEL_W - 32, 96)

  buttons.each do |btn|
    btn[:view].set_geometry(side_x + 16, btn[:y_offset], PANEL_W - 32, 36)
  end
end

apply_theme = lambda do
  if dark
    root_bg.set_style_sheet('background-color: #0b1220; border: 1px solid #1f2937;')
    preview_panel.set_style_sheet(CARD_DARK)
    preview_title.set_style_sheet(TITLE_DARK)
    side_panel.set_style_sheet('background-color: #0f172a; border-left: 1px solid #334155;')
    status.set_style_sheet(CARD_DARK)
    api_box.set_style_sheet(CARD_DARK)
    hint.set_style_sheet(CARD_DARK)
    buttons.each { |b| b[:view].set_style_sheet(BTN_DARK) }
  else
    root_bg.set_style_sheet(BASE_BG)
    preview_panel.set_style_sheet(CARD_LIGHT)
    preview_title.set_style_sheet(TITLE_LIGHT)
    side_panel.set_style_sheet('background-color: #f4f4f5; border-left: 1px solid #d4d4d8;')
    status.set_style_sheet(CARD_LIGHT)
    api_box.set_style_sheet(CARD_LIGHT)
    hint.set_style_sheet(CARD_LIGHT)
    buttons.each { |b| b[:view].set_style_sheet(BTN_LIGHT) }
  end
end

flash_button = lambda do |key|
  btn = buttons.find { |b| b[:key] == key }
  return unless btn

  btn[:view].set_style_sheet(dark ? BTN_ACTIVE_DARK : BTN_ACTIVE_LIGHT)
  QApplication.process_events
  sleep(0.04)
  btn[:view].set_style_sheet(dark ? BTN_DARK : BTN_LIGHT)
end

add_label = lambda do
  label = QLabel.new(preview_host)
  label.set_text("Dynamic QLabel ##{counter}")
  label.set_alignment(Qt::AlignCenter)
  label.set_style_sheet(dark ? CARD_DARK : CARD_LIGHT)
  layout.add_widget(label)
  items << label
end

add_push_button = lambda do
  button = QPushButton.new(preview_host)
  button.set_text("QPushButton ##{counter}")
  layout.add_widget(button)
  items << button
end

refresh_status = lambda do
  status.set_text("Ready\nitems: #{items.length}")
end

perform_action = lambda do |key|
  case key
  when :add_label
    add_label.call
    counter += 1
  when :add_button
    add_push_button.call
    counter += 1
  when :theme
    dark = !dark
    apply_theme.call
    items.each do |item|
      next unless item.is_a?(QLabel)

      item.set_style_sheet(dark ? CARD_DARK : CARD_LIGHT)
    end
  when :inspect
    last = items.last
    if last
      data = last.q_inspect
      puts "[inspect] #{data}"
      status.set_text("Inspect OK\n#{data[:ruby_class]}")
    else
      status.set_text('Inspect: no items')
    end
  when :remove
    last = items.pop
    if last
      layout.remove_widget(last)
      last.hide
    end
  when :clear
    until items.empty?
      item = items.pop
      layout.remove_widget(item)
      item.hide
    end
  end

  refresh_status.call unless key == :inspect
end

buttons.each do |btn|
  btn[:view].connect('clicked') do |_checked|
    flash_button.call(btn[:key])
    perform_action.call(btn[:key])
  end
end

apply_theme.call
refresh_status.call
layout_ui.call
window.on(:resize) { |_ev| layout_ui.call }
window.show
QApplication.process_events

# TODO: Replace manual process_events loop with app.exec + QTimer.
loop do
  QApplication.process_events
  break if window.is_visible.zero?

  sleep(0.01)
end

app.dispose

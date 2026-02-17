# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'qt'

WINDOW_W = 1100
WINDOW_H = 700
ROWS = 12
COLS = 5

HEADERS = ['Month', 'Planned', 'Actual', 'Delta', 'Status'].freeze
MONTHS = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec].freeze
COLUMN_WIDTHS = [120, 170, 170, 150, 150].freeze

BASE_BG = 'background-color: #f4f6fb; border: 1px solid #d8deea;'
PANEL = 'background-color: #ffffff; border: 1px solid #cfd8e6; color: #0f172a;'
TITLE = 'background-color: #ffffff; border: 1px solid #bfcde0; color: #0f172a; font-size: 17px; font-weight: 800;'
BTN = 'background-color: #ffffff; border: 1px solid #9fb1cc; color: #0f172a; font-size: 12px; font-weight: 700;'
BTN_ACTIVE = 'background-color: #dbeafe; border: 2px solid #2563eb; color: #0f172a; font-size: 12px; font-weight: 800;'
GOOD = 'background-color: #ecfdf5; border: 1px solid #86efac; color: #166534; font-weight: 700;'
BAD = 'background-color: #fff1f2; border: 1px solid #fda4af; color: #9f1239; font-weight: 700;'
NEUTRAL = 'background-color: #f8fafc; border: 1px solid #cbd5e1; color: #334155; font-weight: 700;'
INPUT = 'background-color: #ffffff; border: 1px solid #b6c3d8; color: #0f172a; font-size: 12px;'

app = QApplication.new(0, [])
window = QWidget.new do |w|
  w.set_window_title('Qt Ruby Spreadsheet Lite (inspired by PySide spreadsheet)')
  w.set_geometry(60, 50, WINDOW_W, WINDOW_H)
end

bg = QLabel.new(window)
panel = QLabel.new(window)
title = QLabel.new(window)
title.set_alignment(Qt::AlignCenter)
title.set_text('Budget Spreadsheet Lite')

summary = QLabel.new(window)
summary.set_alignment(Qt::AlignCenter)
summary.set_text('Fill planned/actual values and click RECOMPUTE')

sheet = QTableWidget.new(window)
sheet.set_row_count(ROWS)
sheet.set_column_count(COLS)
sheet.set_vertical_scroll_mode(Qt::ScrollPerPixel)
sheet.set_horizontal_scroll_bar_policy(Qt::ScrollBarAlwaysOff)

COLUMN_WIDTHS.each_with_index { |width, idx| sheet.set_column_width(idx, width) }

header_labels = []
HEADERS.each_with_index do |name, idx|
  label = QLabel.new(window)
  label.set_alignment(Qt::AlignCenter)
  label.set_text(name)
  header_labels << { view: label, col: idx }
end

planned_inputs = []
actual_inputs = []
delta_labels = []
status_labels = []

ROWS.times do |row|
  month = QLabel.new(window)
  month.set_alignment(Qt::AlignCenter)
  month.set_text(MONTHS[row])
  month.set_style_sheet(PANEL)
  sheet.set_cell_widget(row, 0, month)

  planned = QLineEdit.new(window)
  planned.set_placeholder_text('0')
  planned.set_text(((row + 1) * 100).to_s)
  planned.set_style_sheet(INPUT)
  sheet.set_cell_widget(row, 1, planned)

  actual = QLineEdit.new(window)
  actual.set_placeholder_text('0')
  actual.set_text(((row + 1) * 95).to_s)
  actual.set_style_sheet(INPUT)
  sheet.set_cell_widget(row, 2, actual)

  delta = QLabel.new(window)
  delta.set_alignment(Qt::AlignCenter)
  delta.set_text('0')
  delta.set_style_sheet(NEUTRAL)
  sheet.set_cell_widget(row, 3, delta)

  status = QLabel.new(window)
  status.set_alignment(Qt::AlignCenter)
  status.set_text('OK')
  status.set_style_sheet(NEUTRAL)
  sheet.set_cell_widget(row, 4, status)

  planned_inputs << planned
  actual_inputs << actual
  delta_labels << delta
  status_labels << status
end

recompute_btn = QPushButton.new(window)
recompute_btn.set_text('RECOMPUTE')

randomize_btn = QPushButton.new(window)
randomize_btn.set_text('RANDOMIZE ACTUAL')

reset_btn = QPushButton.new(window)
reset_btn.set_text('RESET')

flash = lambda do |btn|
  btn.set_style_sheet(BTN_ACTIVE)
  QApplication.process_events
  sleep(0.03)
  btn.set_style_sheet(BTN)
end

as_int = lambda do |text|
  s = text.to_s.strip
  return 0 if s.empty?

  Integer(s)
rescue ArgumentError
  0
end

recompute = lambda do
  total_plan = 0
  total_actual = 0

  ROWS.times do |row|
    plan = as_int.call(planned_inputs[row].text)
    actual = as_int.call(actual_inputs[row].text)
    delta = actual - plan

    total_plan += plan
    total_actual += actual

    delta_labels[row].set_text(delta.to_s)

    if delta > 0
      delta_labels[row].set_style_sheet(BAD)
      status_labels[row].set_text('OVER')
      status_labels[row].set_style_sheet(BAD)
    elsif delta < 0
      delta_labels[row].set_style_sheet(GOOD)
      status_labels[row].set_text('UNDER')
      status_labels[row].set_style_sheet(GOOD)
    else
      delta_labels[row].set_style_sheet(NEUTRAL)
      status_labels[row].set_text('ON PLAN')
      status_labels[row].set_style_sheet(NEUTRAL)
    end
  end

  summary.set_text("Planned: #{total_plan} | Actual: #{total_actual} | Delta: #{total_actual - total_plan}")
end

randomize_actual = lambda do
  srand(Time.now.to_i)
  ROWS.times do |row|
    plan = as_int.call(planned_inputs[row].text)
    jitter = rand(-35..45)
    actual_inputs[row].set_text((plan + plan * jitter / 100).to_s)
  end
end

reset_all = lambda do
  ROWS.times do |row|
    planned_inputs[row].set_text(((row + 1) * 100).to_s)
    actual_inputs[row].set_text(((row + 1) * 95).to_s)
  end
end

layout_ui = lambda do
  ww = window.width
  wh = window.height

  bg.set_geometry(0, 0, ww, wh)
  panel.set_geometry(16, 16, ww - 32, wh - 32)
  title.set_geometry(32, 32, ww - 64, 42)

  left = 32
  top = 86
  available_w = ww - 64

  header_labels.each do |h|
    x = left
    h[:col].times { |col| x += COLUMN_WIDTHS[col] }
    h[:view].set_geometry(x, top, COLUMN_WIDTHS[h[:col]], 30)
  end

  sheet.set_geometry(left, top + 34, available_w, wh - 220)

  recompute_btn.set_geometry(32, wh - 120, 190, 38)
  randomize_btn.set_geometry(232, wh - 120, 250, 38)
  reset_btn.set_geometry(492, wh - 120, 140, 38)
  summary.set_geometry(32, wh - 74, ww - 64, 42)
end

apply_styles = lambda do
  bg.set_style_sheet(BASE_BG)
  panel.set_style_sheet(PANEL)
  title.set_style_sheet(TITLE)
  summary.set_style_sheet(PANEL)
  header_labels.each { |h| h[:view].set_style_sheet(TITLE) }
  recompute_btn.set_style_sheet(BTN)
  randomize_btn.set_style_sheet(BTN)
  reset_btn.set_style_sheet(BTN)
end

recompute_btn.connect('clicked') do
  flash.call(recompute_btn)
  recompute.call
end

randomize_btn.connect('clicked') do
  flash.call(randomize_btn)
  randomize_actual.call
  recompute.call
end

reset_btn.connect('clicked') do
  flash.call(reset_btn)
  reset_all.call
  recompute.call
end

window.on(:resize) { layout_ui.call }

apply_styles.call
layout_ui.call
recompute.call
window.show
QApplication.process_events

while window.is_visible != 0
  QApplication.process_events
  sleep(0.01)
end

app.dispose

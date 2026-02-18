# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../../../../../lib', __dir__))
require 'qt'

WINDOW_W = 980
WINDOW_H = 660
COLS = 6

HEADERS = ['Item', 'Date', 'Price', 'Currency', 'Ex. Rate', 'NOK'].freeze
ROWS_DATA = [
  ['AirportBus', '15/6/2006', 150, 'NOK', 1],
  ['Flight (Munich)', '15/6/2006', 2350, 'NOK', 1],
  ['Lunch', '15/6/2006', -14, 'EUR', 8],
  ['Flight (LA)', '21/5/2006', 980, 'EUR', 8],
  ['Taxi', '16/6/2006', 5, 'USD', 7],
  ['Dinner', '16/6/2006', 120, 'USD', 7],
  ['Hotel', '16/6/2006', 300, 'USD', 7],
  ['Flight (Oslo)', '18/6/2006', 1240, 'NOK', 1]
].freeze

ROWS = ROWS_DATA.length + 1
TOTAL_ROW = ROWS - 1

BG = 'background-color: #0b111b; border: 1px solid #1f2937;'
PANEL = 'background-color: #0f172a; border: 1px solid #334155; color: #e2e8f0;'
TITLE = 'background-color: #111827; border: 1px solid #374151; color: #f8fafc; font-size: 16px; font-weight: 800;'
INPUT = 'background-color: #0b1220; border: 1px solid #334155; color: #f8fafc; font-size: 12px;'
BTN = 'background-color: #111827; border: 1px solid #64748b; color: #e2e8f0; font-size: 12px; font-weight: 700;'
BTN_ACTIVE = 'background-color: #1d4ed8; border: 2px solid #60a5fa; color: #f8fafc; font-size: 12px; font-weight: 800;'

TABLE_QSS = [
  'QTableWidget {',
  '  background-color: #0b1220;',
  '  color: #f8fafc;',
  '  border: 1px solid #334155;',
  '  gridline-color: #1f2937;',
  '}',
  'QHeaderView::section {',
  '  background-color: #3f3f46;',
  '  color: #f8fafc;',
  '  border: 1px solid #4b5563;',
  '  font-weight: 700;',
  '}',
  'QTableCornerButton::section {',
  '  background-color: #3f3f46;',
  '  border: 1px solid #4b5563;',
  '}'
].join("\n").freeze

app = QApplication.new(0, [])
window = QWidget.new do |w|
  w.set_window_title('Spreadsheet')
  w.set_geometry(70, 60, WINDOW_W, WINDOW_H)
end

bg = QLabel.new(window)
panel = QLabel.new(window)

title = QLabel.new(window)
title.set_alignment(Qt::AlignCenter)
title.set_text('Spreadsheet')

cell_label = QLabel.new(window)
cell_label.set_alignment(Qt::AlignCenter)
cell_label.set_text('Cell: (A1)')

formula = QLineEdit.new(window)
formula.set_placeholder_text('Cell value')

apply_btn = QPushButton.new(window)
apply_btn.set_text('APPLY')

recalc_btn = QPushButton.new(window)
recalc_btn.set_text('RECALCULATE')

sheet = QTableWidget.new(window)
sheet.set_row_count(ROWS)
sheet.set_column_count(COLS)
sheet.set_vertical_scroll_mode(Qt::ScrollPerPixel)

[180, 160, 120, 140, 120, 120].each_with_index do |width, col|
  sheet.set_column_width(col, width)
end

headers = []
HEADERS.each_with_index do |text, col|
  item = QTableWidgetItem.new
  item.set_text(text)
  item.set_text_alignment(Qt::AlignCenter)
  sheet.set_horizontal_header_item(col, item)
  headers << item
end

matrix = Array.new(ROWS) { Array.new(COLS) }

ROWS_DATA.each_with_index do |row_data, row|
  COLS.times do |col|
    item = QTableWidgetItem.new
    value = case col
            when 0 then row_data[0]
            when 1 then row_data[1]
            when 2 then row_data[2]
            when 3 then row_data[3]
            when 4 then row_data[4]
            else 0
            end
    item.set_text(value.to_s)
    item.set_text_alignment(Qt::AlignCenter)
    sheet.set_item(row, col, item)
    matrix[row][col] = item
  end
end

COLS.times do |col|
  item = QTableWidgetItem.new
  value = if col.zero?
            'Total:'
          elsif col == 5
            '0'
          else
            'None'
          end
  item.set_text(value)
  item.set_text_alignment(Qt::AlignCenter)
  sheet.set_item(TOTAL_ROW, col, item)
  matrix[TOTAL_ROW][col] = item
end

int_value = lambda do |text|
  Integer(text.to_s.strip)
rescue StandardError
  0
end

recompute = lambda do
  total = 0
  ROWS_DATA.length.times do |row|
    price = int_value.call(matrix[row][2].text)
    rate = int_value.call(matrix[row][4].text)
    nok = price * rate
    matrix[row][5].set_text(nok.to_s)
    total += nok
  end

  matrix[TOTAL_ROW][5].set_text(total.to_s)
end

col_label = lambda do |col|
  letters = +''
  n = col + 1
  while n.positive?
    n -= 1
    letters.prepend((65 + (n % 26)).chr)
    n /= 26
  end
  letters
end

sync_formula_with_current = lambda do
  row = sheet.current_row
  col = sheet.current_column
  return if row.negative? || col.negative?

  item = matrix[row][col]
  return unless item

  cell_label.set_text("Cell: (#{col_label.call(col)}#{row + 1})")
  formula.set_text(item.text.to_s)
end

flash = lambda do |button|
  button.set_style_sheet(BTN_ACTIVE)
  QApplication.process_events
  sleep(0.03)
  button.set_style_sheet(BTN)
end

apply_current_cell = lambda do
  row = sheet.current_row
  col = sheet.current_column
  return if row.negative? || col.negative?

  item = matrix[row][col]
  return unless item

  item.set_text(formula.text.to_s)
  recompute.call
  sync_formula_with_current.call
end

apply_btn.connect('clicked') do
  flash.call(apply_btn)
  apply_current_cell.call
end

formula.connect('returnPressed') { apply_current_cell.call }

recalc_btn.connect('clicked') do
  flash.call(recalc_btn)
  recompute.call
  sync_formula_with_current.call
end

sheet.on(:mouse_button_release) { sync_formula_with_current.call }
sheet.on(:key_release) { sync_formula_with_current.call }

layout_ui = lambda do
  ww = window.width
  wh = window.height

  bg.set_geometry(0, 0, ww, wh)
  panel.set_geometry(16, 16, ww - 32, wh - 32)

  title.set_geometry(32, 24, ww - 64, 36)

  cell_label.set_geometry(32, 68, 130, 32)
  formula.set_geometry(170, 68, ww - 372, 32)
  apply_btn.set_geometry(ww - 194, 68, 74, 32)
  recalc_btn.set_geometry(ww - 112, 68, 80, 32)

  sheet.set_geometry(32, 112, ww - 64, wh - 144)
end

apply_styles = lambda do
  bg.set_style_sheet(BG)
  panel.set_style_sheet(PANEL)
  title.set_style_sheet(TITLE)
  cell_label.set_style_sheet(PANEL)
  formula.set_style_sheet(INPUT)
  apply_btn.set_style_sheet(BTN)
  recalc_btn.set_style_sheet(BTN)
  sheet.set_style_sheet(TABLE_QSS)
end

window.on(:resize) { layout_ui.call }

recompute.call
apply_styles.call
layout_ui.call
sheet.set_current_cell(0, 0)
sync_formula_with_current.call
window.show
QApplication.process_events

# TODO: Replace manual process_events loop with app.exec + QTimer.
while window.is_visible != 0
  QApplication.process_events
  sleep(0.01)
end

app.dispose

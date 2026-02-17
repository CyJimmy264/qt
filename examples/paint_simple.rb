# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'qt'

CELL = 12
COLS = 64
ROWS = 40
TOOLBAR_HEIGHT = 44
CANVAS_WIDTH = COLS * CELL
CANVAS_HEIGHT = ROWS * CELL
WINDOW_WIDTH = CANVAS_WIDTH
WINDOW_HEIGHT = TOOLBAR_HEIGHT + CANVAS_HEIGHT

LEFT_BUTTON = 1
RIGHT_BUTTON = 2

ERASE_STYLE = 'background-color: #ffffff; border: 1px solid #f1f1f1;'
PALETTE = [
  { name: 'Black', style: 'background-color: #111111; border: 1px solid #111111;' },
  { name: 'Blue', style: 'background-color: #1e66f5; border: 1px solid #1e66f5;' },
  { name: 'Green', style: 'background-color: #40a02b; border: 1px solid #40a02b;' },
  { name: 'Red', style: 'background-color: #d20f39; border: 1px solid #d20f39;' },
  { name: 'Orange', style: 'background-color: #fe640b; border: 1px solid #fe640b;' }
].freeze

app = QApplication.new(0, [])
window = QWidget.new do |w|
  w.set_window_title('Qt Ruby Paint: LMB draw, RMB erase')
  w.set_geometry(80, 80, WINDOW_WIDTH, WINDOW_HEIGHT)
end

toolbar_bg = QLabel.new(window)
toolbar_bg.set_geometry(0, 0, WINDOW_WIDTH, TOOLBAR_HEIGHT)
toolbar_bg.set_style_sheet('background-color: #f7f7f7; border: 1px solid #d8d8d8;')

status = QLabel.new(window)
status.set_geometry(10, 8, 260, 28)
status.set_alignment(Qt::AlignCenter)
status.set_style_sheet('background-color: #ffffff; border: 1px solid #d8d8d8;')

swatches = []
PALETTE.each_with_index do |entry, i|
  swatch = QLabel.new(window)
  swatch.set_geometry(285 + i * 34, 7, 28, 28)
  swatch.set_style_sheet(entry[:style])
  swatches << swatch
end

clear_button = QLabel.new(window)
clear_button.set_geometry(285 + PALETTE.length * 34 + 12, 7, 100, 28)
clear_button.set_text('CLEAR')
clear_button.set_alignment(Qt::AlignCenter)
clear_button.set_style_sheet('background-color: #ffffff; border: 1px solid #c7c7c7;')

cells = Array.new(ROWS) { Array.new(COLS) }
ROWS.times do |row|
  COLS.times do |col|
    pixel = QLabel.new(window)
    pixel.set_geometry(col * CELL, TOOLBAR_HEIGHT + row * CELL, CELL, CELL)
    pixel.set_style_sheet(ERASE_STYLE)
    cells[row][col] = pixel
  end
end

selected_index = 0
selected_style = PALETTE[selected_index][:style]
prev_left_down = false

refresh_palette = lambda do
  swatches.each_with_index do |swatch, idx|
    border = idx == selected_index ? '3px solid #000000' : '1px solid #999999'
    swatch.set_style_sheet("#{PALETTE[idx][:style]} border: #{border};")
  end

  status.set_text("Color: #{PALETTE[selected_index][:name]}")
end

clear_canvas = lambda do
  ROWS.times do |row|
    COLS.times do |col|
      cells[row][col].set_style_sheet(ERASE_STYLE)
    end
  end
end

inside = lambda do |x, y, gx, gy, w, h|
  x >= gx && x < gx + w && y >= gy && y < gy + h
end

window.show
QApplication.process_events
refresh_palette.call

loop do
  QApplication.process_events
  break if window.is_visible.zero?

  mx = QApplication.mouse_x
  my = QApplication.mouse_y
  buttons = QApplication.mouse_buttons

  local_x = Qt::Native.qwidget_map_from_global_x(window.handle, mx, my)
  local_y = Qt::Native.qwidget_map_from_global_y(window.handle, mx, my)

  left_down = (buttons & LEFT_BUTTON) != 0
  right_down = (buttons & RIGHT_BUTTON) != 0

  if left_down && !prev_left_down
    swatches.each_with_index do |_swatch, idx|
      sx = 285 + idx * 34
      if inside.call(local_x, local_y, sx, 7, 28, 28)
        selected_index = idx
        selected_style = PALETTE[selected_index][:style]
        refresh_palette.call
      end
    end

    if inside.call(local_x, local_y, 285 + PALETTE.length * 34 + 12, 7, 100, 28)
      clear_canvas.call
      status.set_text("Color: #{PALETTE[selected_index][:name]} (canvas cleared)")
    end
  end

  if inside.call(local_x, local_y, 0, TOOLBAR_HEIGHT, CANVAS_WIDTH, CANVAS_HEIGHT)
    col = local_x / CELL
    row = (local_y - TOOLBAR_HEIGHT) / CELL
    pixel = cells[row][col]

    if left_down
      pixel.set_style_sheet(selected_style)
    elsif right_down
      pixel.set_style_sheet(ERASE_STYLE)
    end
  end

  prev_left_down = left_down
  sleep(0.005)
end

app.dispose

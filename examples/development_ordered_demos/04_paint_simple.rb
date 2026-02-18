# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
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
TOOLBAR_STYLE = 'background-color: #f7f7f7; border: 1px solid #d8d8d8;'
STATUS_STYLE = 'background-color: #ffffff; border: 1px solid #c7c7c7; color: #111111; font-weight: 700; font-size: 12px;'
CLEAR_STYLE = 'background-color: #ffffff; border: 1px solid #c7c7c7; color: #111111; font-weight: 800; font-size: 12px;'
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
toolbar_bg.set_style_sheet(TOOLBAR_STYLE)

status = QLabel.new(window)
status.set_geometry(10, 8, 260, 28)
status.set_alignment(Qt::AlignCenter)
status.set_style_sheet(STATUS_STYLE)

swatches = []
PALETTE.each_with_index do |entry, i|
  swatch = QLabel.new(window)
  swatch.set_geometry(285 + (i * 34), 7, 28, 28)
  swatch.set_style_sheet(entry[:style])
  swatches << swatch
end

clear_button = QLabel.new(window)
clear_button.set_geometry(285 + (PALETTE.length * 34) + 12, 7, 100, 28)
clear_button.set_text('CLEAR')
clear_button.set_alignment(Qt::AlignCenter)
clear_button.set_style_sheet(CLEAR_STYLE)

cells = Array.new(ROWS) { Array.new(COLS) }
ROWS.times do |row|
  COLS.times do |col|
    pixel = QLabel.new(window)
    pixel.set_geometry(col * CELL, TOOLBAR_HEIGHT + (row * CELL), CELL, CELL)
    pixel.set_style_sheet(ERASE_STYLE)
    cells[row][col] = pixel
  end
end

selected_index = 0
selected_style = PALETTE[selected_index][:style]

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

inside = ->(x, y, gx, gy, w, h) { x >= gx && x < gx + w && y >= gy && y < gy + h }

paint_at = lambda do |x, y, erase|
  return unless inside.call(x, y, 0, TOOLBAR_HEIGHT, CANVAS_WIDTH, CANVAS_HEIGHT)

  col = x / CELL
  row = (y - TOOLBAR_HEIGHT) / CELL
  pixel = cells[row][col]
  pixel.set_style_sheet(erase ? ERASE_STYLE : selected_style)
end

window.show
QApplication.process_events
refresh_palette.call

window.on(:mouse_button_press) do |evt|
  x = evt[:a]
  y = evt[:b]
  button = evt[:c]

  if button == LEFT_BUTTON
    swatches.each_with_index do |_swatch, idx|
      sx = 285 + (idx * 34)
      next unless inside.call(x, y, sx, 7, 28, 28)

      selected_index = idx
      selected_style = PALETTE[selected_index][:style]
      refresh_palette.call
    end

    if inside.call(x, y, 285 + (PALETTE.length * 34) + 12, 7, 100, 28)
      clear_canvas.call
      status.set_text("Color: #{PALETTE[selected_index][:name]} (canvas cleared)")
    end
  end

  paint_at.call(x, y, button == RIGHT_BUTTON)
end

window.on(:mouse_move) do |evt|
  x = evt[:a]
  y = evt[:b]
  buttons = evt[:d]

  if buttons.anybits?(LEFT_BUTTON)
    paint_at.call(x, y, false)
  elsif buttons.anybits?(RIGHT_BUTTON)
    paint_at.call(x, y, true)
  end
end

# TODO: Replace manual process_events loop with app.exec + QTimer.
while window.is_visible != 0
  QApplication.process_events
  sleep(0.005)
end

app.dispose

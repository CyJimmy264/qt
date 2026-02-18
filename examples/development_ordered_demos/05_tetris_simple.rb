# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'qt'

COLS = 10
ROWS = 20
CELL = 24
PANEL_WIDTH = 180
WINDOW_WIDTH = (COLS * CELL) + PANEL_WIDTH
WINDOW_HEIGHT = ROWS * CELL

EMPTY_STYLE = 'background-color: #fafafa; border: 1px solid #e6e6e6;'
BORDER_STYLE = 'background-color: #f3f3f3; border: 1px solid #d5d5d5;'
TEXT_STYLE = 'background-color: #ffffff; border: 1px solid #cccccc;'
BUTTON_STYLE = 'background-color: #ffffff; border: 1px solid #bdbdbd;'
BUTTON_ACTIVE_STYLE = 'background-color: #dbeafe; border: 1px solid #60a5fa;'
TITLE_STYLE = 'background-color: #ffffff; border: 1px solid #cccccc; color: #111111; font-weight: 800; font-size: 15px;'
INFO_STYLE = 'background-color: #ffffff; border: 1px solid #cccccc; color: #111111; font-weight: 700; font-size: 12px;'
BTN_STYLE = 'background-color: #ffffff; border: 1px solid #bdbdbd; color: #111111; font-weight: 700; font-size: 12px;'
BTN_ACTIVE_STYLE = 'background-color: #dbeafe; border: 2px solid #2563eb; color: #111111; font-weight: 800; font-size: 12px;'

PIECE_STYLES = [
  'background-color: #16a34a; border: 1px solid #15803d;',
  'background-color: #1d4ed8; border: 1px solid #1e40af;',
  'background-color: #dc2626; border: 1px solid #b91c1c;',
  'background-color: #ea580c; border: 1px solid #c2410c;',
  'background-color: #7c3aed; border: 1px solid #6d28d9;',
  'background-color: #0891b2; border: 1px solid #0e7490;',
  'background-color: #ca8a04; border: 1px solid #a16207;'
].freeze

SHAPES = [
  [[0, 1], [1, 1], [2, 1], [3, 1]],
  [[0, 0], [0, 1], [1, 1], [2, 1]],
  [[2, 0], [0, 1], [1, 1], [2, 1]],
  [[1, 0], [2, 0], [0, 1], [1, 1]],
  [[1, 0], [0, 1], [1, 1], [2, 1]],
  [[0, 0], [1, 0], [1, 1], [2, 1]],
  [[1, 0], [2, 0], [1, 1], [2, 1]]
].freeze

# Rotate shape 90 degrees clockwise around local 4x4 grid.
def rotate_shape(points)
  points.map { |x, y| [y, 3 - x] }
end

# Normalize points to keep top-left origin after rotation.
def normalize_shape(points)
  min_x = points.map(&:first).min
  min_y = points.map(&:last).min
  points.map { |x, y| [x - min_x, y - min_y] }
end

app = QApplication.new(0, [])
window = QWidget.new do |w|
  w.set_window_title('Qt Ruby Tetris')
  w.set_geometry(80, 80, WINDOW_WIDTH, WINDOW_HEIGHT)
end

board_cells = Array.new(ROWS) { Array.new(COLS) }
board = Array.new(ROWS) { Array.new(COLS, -1) }

ROWS.times do |r|
  COLS.times do |c|
    cell = QLabel.new(window)
    cell.set_geometry(c * CELL, r * CELL, CELL, CELL)
    cell.set_style_sheet(EMPTY_STYLE)
    board_cells[r][c] = cell
  end
end

side = QLabel.new(window)
side.set_geometry(COLS * CELL, 0, PANEL_WIDTH, WINDOW_HEIGHT)
side.set_style_sheet(BORDER_STYLE)

title = QLabel.new(window)
title.set_geometry((COLS * CELL) + 16, 16, PANEL_WIDTH - 32, 30)
title.set_alignment(Qt::AlignCenter)
title.set_text('TETRIS')
title.set_style_sheet(TITLE_STYLE)

score_label = QLabel.new(window)
score_label.set_geometry((COLS * CELL) + 16, 56, PANEL_WIDTH - 32, 30)
score_label.set_alignment(Qt::AlignCenter)
score_label.set_style_sheet(INFO_STYLE)

status_label = QLabel.new(window)
status_label.set_geometry((COLS * CELL) + 16, 96, PANEL_WIDTH - 32, 30)
status_label.set_alignment(Qt::AlignCenter)
status_label.set_style_sheet(INFO_STYLE)

buttons = [
  { key: :left, text: 'LEFT', x: (COLS * CELL) + 16, y: 150, w: 70, h: 34 },
  { key: :right, text: 'RIGHT', x: (COLS * CELL) + 94, y: 150, w: 70, h: 34 },
  { key: :rotate, text: 'ROTATE', x: (COLS * CELL) + 16, y: 192, w: 148, h: 34 },
  { key: :drop, text: 'DROP', x: (COLS * CELL) + 16, y: 234, w: 148, h: 34 },
  { key: :new, text: 'NEW GAME', x: (COLS * CELL) + 16, y: 276, w: 148, h: 34 }
]

buttons.each do |btn|
  view = QPushButton.new(window)
  view.set_geometry(btn[:x], btn[:y], btn[:w], btn[:h])
  view.set_text(btn[:text])
  view.set_focus_policy(Qt::NoFocus)
  view.set_style_sheet(BTN_STYLE)
  btn[:view] = view
end

current = nil
score = 0
lines = 0
fall_interval = 0.45
last_fall = Time.now

valid_position = lambda do |piece, dx, dy, shape = nil|
  test = shape || piece[:shape]
  test.all? do |x, y|
    nx = piece[:x] + x + dx
    ny = piece[:y] + y + dy
    next false if nx.negative? || nx >= COLS || ny >= ROWS
    next true if ny.negative?

    board[ny][nx] == -1
  end
end

spawn_piece = lambda do
  shape_idx = rand(SHAPES.length)
  {
    x: 3,
    y: -1,
    color: shape_idx,
    shape: SHAPES[shape_idx].map(&:dup)
  }
end

lock_piece = lambda do |piece|
  piece[:shape].each do |x, y|
    bx = piece[:x] + x
    by = piece[:y] + y
    next if by.negative?

    board[by][bx] = piece[:color]
  end
end

clear_lines = lambda do
  kept = board.reject { |row| row.all? { |cell| cell >= 0 } }
  removed = ROWS - kept.length
  removed.times { kept.unshift(Array.new(COLS, -1)) }

  ROWS.times { |r| board[r] = kept[r] }

  if removed.positive?
    lines += removed
    score += case removed
             when 1 then 100
             when 2 then 250
             when 3 then 450
             else 700
             end
  end
end

restart = lambda do
  ROWS.times do |r|
    COLS.times do |c|
      board[r][c] = -1
    end
  end

  score = 0
  lines = 0
  fall_interval = 0.45
  current = spawn_piece.call
  status_label.set_text('RUNNING')
  last_fall = Time.now
end

paint = lambda do
  ROWS.times do |r|
    COLS.times do |c|
      v = board[r][c]
      board_cells[r][c].set_style_sheet(v >= 0 ? PIECE_STYLES[v] : EMPTY_STYLE)
    end
  end

  if current
    current[:shape].each do |x, y|
      bx = current[:x] + x
      by = current[:y] + y
      next if by.negative? || bx.negative? || bx >= COLS || by >= ROWS

      board_cells[by][bx].set_style_sheet(PIECE_STYLES[current[:color]])
    end
  end

  score_label.set_text("Score: #{score}  Lines: #{lines}")
end

press_button = lambda do |name|
  button = buttons.find { |b| b[:key] == name }
  return unless button

  button[:view].set_style_sheet(BTN_ACTIVE_STYLE)
  QApplication.process_events
  sleep(0.03)
  button[:view].set_style_sheet(BTN_STYLE)
end

perform_action = lambda do |action|
  return restart.call if action == :new
  return if current.nil?

  case action
  when :left
    current[:x] -= 1 if valid_position.call(current, -1, 0)
  when :right
    current[:x] += 1 if valid_position.call(current, 1, 0)
  when :rotate
    rotated = normalize_shape(rotate_shape(current[:shape]))
    current[:shape] = rotated if valid_position.call(current, 0, 0, rotated)
  when :drop
    current[:y] += 1 while valid_position.call(current, 0, 1)
    lock_piece.call(current)
    clear_lines.call
    current = spawn_piece.call
    unless valid_position.call(current, 0, 0)
      status_label.set_text('GAME OVER')
      current = nil
    end
  end
end

trigger_action = lambda do |action|
  press_button.call(action) if %i[left right rotate drop new].include?(action)
  perform_action.call(action)
end

action_for_key = lambda do |key_code|
  case key_code
  when Qt::KeyLeft then :left
  when Qt::KeyRight then :right
  when Qt::KeyUp then :rotate
  when Qt::KeyDown, Qt::KeySpace then :drop
  when Qt::KeyN then :new
  end
end

handle_key_event = lambda do |ev|
  action = action_for_key.call(ev[:a])
  trigger_action.call(action) if action
end

buttons.each do |btn|
  btn[:view].connect('clicked') do |_checked|
    trigger_action.call(btn[:key])
  end
end

window.on(:key_press) { |ev| handle_key_event.call(ev) }

restart.call
window.show

# TODO: Replace manual game loop polling with app.exec + QTimer tick/update.
loop do
  QApplication.process_events
  break if window.is_visible.zero?

  if current && Time.now - last_fall >= fall_interval
    if valid_position.call(current, 0, 1)
      current[:y] += 1
    else
      lock_piece.call(current)
      clear_lines.call
      current = spawn_piece.call
      unless valid_position.call(current, 0, 0)
        status_label.set_text('GAME OVER')
        current = nil
      end

      fall_interval = [0.12, 0.45 - (lines * 0.01)].max
    end

    last_fall = Time.now
  end

  paint.call
  sleep(0.01)
end

app.dispose

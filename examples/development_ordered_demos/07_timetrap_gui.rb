# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'open3'
require 'qt'

WINDOW_W = 1020
WINDOW_H = 700
LINE_H = 22
OUTPUT_LINES = 24

BG_STYLE = 'background-color: #f3f4f6; border: 1px solid #d1d5db;'
CARD_STYLE = 'background-color: #ffffff; border: 1px solid #d1d5db; color: #111827; font-size: 12px;'
TITLE_STYLE = 'background-color: #ffffff; border: 1px solid #d1d5db; color: #111827; font-size: 16px; font-weight: 800;'
BTN_STYLE = 'background-color: #ffffff; border: 1px solid #9ca3af; color: #111827; font-size: 12px; font-weight: 700;'
BTN_ACTIVE = 'background-color: #dbeafe; border: 2px solid #3b82f6; color: #111827; font-size: 12px; font-weight: 800;'
OUT_STYLE = 'background-color: #0f172a; border: 1px solid #334155; color: #e2e8f0; font-size: 12px;'

TIMETRAP_BIN = ENV.fetch('TIMETRAP_BIN', 't')

app = QApplication.new(0, [])
window = QWidget.new do |w|
  w.set_window_title('Timetrap GUI (Qt Ruby)')
  w.set_geometry(90, 70, WINDOW_W, WINDOW_H)
end

bg = QLabel.new(window)
bg.set_geometry(0, 0, WINDOW_W, WINDOW_H)
bg.set_style_sheet(BG_STYLE)

header = QLabel.new(window)
header.set_geometry(16, 16, WINDOW_W - 32, 42)
header.set_alignment(Qt::AlignCenter)
header.set_style_sheet(TITLE_STYLE)
header.set_text("Timetrap GUI  |  bin: #{TIMETRAP_BIN}")

status = QLabel.new(window)
status.set_geometry(16, 66, WINDOW_W - 32, 56)
status.set_alignment(Qt::AlignCenter)
status.set_style_sheet(CARD_STYLE)
status.set_text('Ready')

panel = QLabel.new(window)
panel.set_geometry(16, 130, 220, WINDOW_H - 146)
panel.set_style_sheet(CARD_STYLE)

button_specs = [
  { key: :in, text: 'IN (note: gui)' },
  { key: :out, text: 'OUT' },
  { key: :now, text: 'NOW' },
  { key: :today, text: 'TODAY' },
  { key: :display, text: 'DISPLAY' },
  { key: :sheets, text: 'SHEETS' },
  { key: :refresh, text: 'REFRESH' }
]

buttons = button_specs.each_with_index.map do |spec, i|
  y = 148 + i * 48
  view = QLabel.new(window)
  view.set_geometry(32, y, 188, 36)
  view.set_alignment(Qt::AlignCenter)
  view.set_style_sheet(BTN_STYLE)
  view.set_text(spec[:text])
  spec.merge(view: view)
end

out_box = QLabel.new(window)
out_box.set_geometry(252, 130, WINDOW_W - 268, WINDOW_H - 146)
out_box.set_style_sheet(OUT_STYLE)

lines = Array.new(OUTPUT_LINES) do |i|
  line = QLabel.new(window)
  line.set_geometry(266, 142 + i * LINE_H, WINDOW_W - 296, LINE_H - 2)
  line.set_style_sheet('background-color: #0f172a; color: #e2e8f0; border: 0px; font-size: 12px;')
  line.set_text('')
  line
end

set_output = lambda do |text|
  prepared = text.to_s.lines.map(&:chomp)
  prepared = ['(no output)'] if prepared.empty?
  prepared = prepared.first(OUTPUT_LINES)

  lines.each_with_index do |line, i|
    line.set_text(prepared[i] || '')
  end
end

run_timetrap = lambda do |*args|
  cmd = [TIMETRAP_BIN, *args]
  begin
    output, status_obj = Open3.capture2e(*cmd)
    [status_obj.success?, output]
  rescue Errno::ENOENT
    [false, "Command not found: #{TIMETRAP_BIN}\nSet TIMETRAP_BIN=/path/to/t or install timetrap in PATH"]
  rescue StandardError => e
    [false, "#{e.class}: #{e.message}"]
  end
end

flash_button = lambda do |btn|
  btn[:view].set_style_sheet(BTN_ACTIVE)
  QApplication.process_events
  sleep(0.04)
  btn[:view].set_style_sheet(BTN_STYLE)
end

act = lambda do |key|
  case key
  when :in
    ok, out = run_timetrap.call('in', 'gui')
    status.set_text(ok ? 'Checked in' : 'Failed to check in')
    set_output.call(out)
  when :out
    ok, out = run_timetrap.call('out')
    status.set_text(ok ? 'Checked out' : 'Failed to check out')
    set_output.call(out)
  when :now
    ok, out = run_timetrap.call('now')
    status.set_text(ok ? 'Current entry' : 'No current entry / error')
    set_output.call(out)
  when :today
    ok, out = run_timetrap.call('today')
    status.set_text(ok ? 'Today report' : 'Today failed')
    set_output.call(out)
  when :display
    ok, out = run_timetrap.call('display')
    status.set_text(ok ? 'Display report' : 'Display failed')
    set_output.call(out)
  when :sheets
    ok, out = run_timetrap.call('sheet')
    status.set_text(ok ? 'Sheets list' : 'Sheets failed')
    set_output.call(out)
  when :refresh
    ok_now, out_now = run_timetrap.call('now')
    ok_today, out_today = run_timetrap.call('today')
    status.set_text(ok_now || ok_today ? 'Refreshed' : 'Refresh failed')
    set_output.call("$ t now\n#{out_now}\n\n$ t today\n#{out_today}")
  end
end

boot_ok, boot_out = run_timetrap.call('now')
status.set_text(boot_ok ? 'Ready (now loaded)' : 'Ready (timetrap not available?)')
set_output.call(boot_out)

window.show
QApplication.process_events

buttons.each do |btn|
  btn[:view].on(:mouse_button_release) do
    flash_button.call(btn)
    act.call(btn[:key])
  end
end

while window.is_visible != 0
  QApplication.process_events
  sleep(0.01)
end

app.dispose

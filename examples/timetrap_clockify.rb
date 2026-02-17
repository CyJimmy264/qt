# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'date'
require 'json'
require 'open3'
require 'time'
require 'qt'
begin
  require 'timetrap'
rescue LoadError
  # CLI fallback is used when timetrap gem is unavailable.
end

WINDOW_W = 1380
WINDOW_H = 860
SIDEBAR_W = 220
TOPBAR_H = 56
CONTENT_X = SIDEBAR_W + 14
CONTENT_W = WINDOW_W - CONTENT_X - 14
LEFT_BUTTON = 1
PROJECT_SLOT_COUNT = 14

TIMETRAP_BIN = ENV.fetch('TIMETRAP_BIN', 't')
TIMETRAP_API = defined?(Timetrap::Entry) && defined?(Timetrap::Timer)

BG_APP = 'background-color: #eef2f5; border: 1px solid #d6dde5;'
BG_SIDEBAR = 'background-color: #f7f9fb; border-right: 1px solid #d9e0e7;'
BG_TOPBAR = 'background-color: #ffffff; border: 1px solid #d9e0e7;'
CARD = 'background-color: #ffffff; border: 1px solid #d9e0e7; color: #111827;'
TITLE = 'background-color: #ffffff; border: 0px; color: #111827; font-size: 18px; font-weight: 800;'
MUTED = 'background-color: #ffffff; border: 0px; color: #6b7280; font-size: 12px;'
SIDE_ITEM = 'background-color: #f7f9fb; border: 0px; color: #334155; font-size: 14px; font-weight: 700;'
SIDE_ACTIVE = 'background-color: #eaf3ff; border: 1px solid #bfdbfe; color: #0f172a; font-size: 14px; font-weight: 800;'
PROJ_ITEM = 'background-color: #f7f9fb; border: 1px solid #e2e8f0; color: #334155; font-size: 12px; font-weight: 700;'
PROJ_ACTIVE = 'background-color: #dbeafe; border: 2px solid #60a5fa; color: #0f172a; font-size: 12px; font-weight: 800;'
INPUT_LIKE = 'background-color: #ffffff; border: 1px solid #cfd8e3; color: #111827; font-size: 14px;'
BTN_PRIMARY = 'background-color: #0ea5e9; border: 1px solid #0284c7; color: #ffffff; font-size: 14px; font-weight: 800;'
BTN_DANGER = 'background-color: #ef4444; border: 1px solid #dc2626; color: #ffffff; font-size: 14px; font-weight: 800;'
BTN_GHOST = 'background-color: #ffffff; border: 1px solid #cfd8e3; color: #0f172a; font-size: 13px; font-weight: 700;'
BTN_ACTIVE = 'background-color: #dbeafe; border: 2px solid #3b82f6; color: #0f172a; font-size: 13px; font-weight: 800;'
TABLE_WRAP = 'background-color: #f3f6fa; border: 1px solid #d9e0e7;'
TABLE_STYLE = 'background-color: #ffffff; border: 1px solid #d9e0e7; color: #111827; font-size: 13px;'
CELL_HEAD = 'background-color: #edf2f7; border: 1px solid #dbe3eb; color: #475569; font-size: 12px; font-weight: 700;'
CELL_TEXT = 'background-color: #ffffff; border: 1px solid #e2e8f0; color: #111827; font-size: 13px;'
CELL_DUR = 'background-color: #ffffff; border: 1px solid #e2e8f0; color: #0f172a; font-size: 13px; font-weight: 800;'
CELL_GROUP = 'background-color: #eaf3ff; border: 1px solid #bfdbfe; color: #1e3a8a; font-size: 13px; font-weight: 800;'

app = QApplication.new(0, [])
window = QWidget.new do |w|
  w.set_window_title('Timetrap UI (Clockify-like)')
  w.set_geometry(40, 40, WINDOW_W, WINDOW_H)
end

root = QLabel.new(window)
root.set_geometry(0, 0, WINDOW_W, WINDOW_H)
root.set_style_sheet(BG_APP)

sidebar = QLabel.new(window)
sidebar.set_geometry(0, 0, SIDEBAR_W, WINDOW_H)
sidebar.set_style_sheet(BG_SIDEBAR)

logo = QLabel.new(window)
logo.set_geometry(18, 12, SIDEBAR_W - 36, 34)
logo.set_alignment(Qt::AlignCenter)
logo.set_style_sheet(TITLE)
logo.set_text('clockify-ish / timetrap')

side_items = [
  { key: :tracker, text: 'TIME TRACKER', y: 66 },
  { key: :calendar, text: 'CALENDAR', y: 112 },
  { key: :dashboard, text: 'DASHBOARD', y: 186 },
  { key: :reports, text: 'REPORTS', y: 232 }
]

side_items.each do |item|
  view = QLabel.new(window)
  view.set_geometry(12, item[:y], SIDEBAR_W - 24, 36)
  view.set_alignment(Qt::AlignCenter)
  view.set_text(item[:text])
  view.set_style_sheet(item[:key] == :tracker ? SIDE_ACTIVE : SIDE_ITEM)
  item[:view] = view
end

project_title = QLabel.new(window)
project_title.set_geometry(16, 286, SIDEBAR_W - 32, 26)
project_title.set_alignment(Qt::AlignCenter)
project_title.set_style_sheet(MUTED)
project_title.set_text('PROJECTS')

project_slots = Array.new(PROJECT_SLOT_COUNT) do |i|
  y = 316 + i * 34
  view = QLabel.new(window)
  view.set_geometry(12, y, SIDEBAR_W - 24, 30)
  view.set_alignment(Qt::AlignCenter)
  view.set_style_sheet(PROJ_ITEM)
  view.set_text('')
  { view: view, x: 12, y: y, w: SIDEBAR_W - 24, h: 30, project: nil }
end

topbar = QLabel.new(window)
topbar.set_geometry(CONTENT_X, 8, CONTENT_W, TOPBAR_H)
topbar.set_style_sheet(BG_TOPBAR)

title = QLabel.new(window)
title.set_geometry(CONTENT_X + 16, 16, 400, 36)
title.set_alignment(Qt::AlignCenter)
title.set_style_sheet(TITLE)
title.set_text('TIME TRACKER')

clock = QLabel.new(window)
clock.set_geometry(CONTENT_X + CONTENT_W - 240, 16, 220, 36)
clock.set_alignment(Qt::AlignCenter)
clock.set_style_sheet(MUTED)

quick_row = QLabel.new(window)
quick_row.set_geometry(CONTENT_X, TOPBAR_H + 22, CONTENT_W, 74)
quick_row.set_style_sheet(CARD)

task_input = QLineEdit.new(window)
task_input.set_geometry(CONTENT_X + 14, TOPBAR_H + 35, CONTENT_W - 470, 48)
task_input.set_style_sheet(INPUT_LIKE)
task_input.set_placeholder_text('What are you working on?')
task_input.text = 'gui-clockify'

project_pill = QLabel.new(window)
project_pill.set_geometry(CONTENT_X + CONTENT_W - 440, TOPBAR_H + 35, 150, 48)
project_pill.set_alignment(Qt::AlignCenter)
project_pill.set_style_sheet(BTN_GHOST)
project_pill.set_text('Project filter: ALL')

live_timer = QLabel.new(window)
live_timer.set_geometry(CONTENT_X + CONTENT_W - 280, TOPBAR_H + 35, 120, 48)
live_timer.set_alignment(Qt::AlignCenter)
live_timer.set_style_sheet(CARD)
live_timer.set_text('00:00:00')

start_btn = QPushButton.new(window)
start_btn.set_geometry(CONTENT_X + CONTENT_W - 152, TOPBAR_H + 35, 64, 48)
start_btn.set_style_sheet(BTN_PRIMARY)
start_btn.set_text('START')

stop_btn = QPushButton.new(window)
stop_btn.set_geometry(CONTENT_X + CONTENT_W - 80, TOPBAR_H + 35, 64, 48)
stop_btn.set_style_sheet(BTN_DANGER)
stop_btn.set_text('STOP')

summary = QLabel.new(window)
summary.set_geometry(CONTENT_X, TOPBAR_H + 108, CONTENT_W, 42)
summary.set_alignment(Qt::AlignCenter)
summary.set_style_sheet(CARD)
summary.set_text('Week total: 00:00:00 | Total: 00:00:00')

scroll = QScrollArea.new(window)
scroll.set_geometry(CONTENT_X, TOPBAR_H + 156, CONTENT_W, WINDOW_H - (TOPBAR_H + 170))
scroll.set_widget_resizable(1)
scroll.set_style_sheet(TABLE_WRAP)

scroll_host = QWidget.new(window)
scroll_host.set_geometry(0, 0, CONTENT_W - 20, WINDOW_H - (TOPBAR_H + 180))
scroll_host.set_style_sheet(TABLE_WRAP)

entries_table = QTableWidget.new(scroll_host)
entries_table.set_geometry(8, 8, CONTENT_W - 40, WINDOW_H - (TOPBAR_H + 196))
entries_table.set_style_sheet(TABLE_STYLE)
entries_table.set_column_count(6)
entries_table.set_column_width(0, 180)
entries_table.set_column_width(1, 230)
entries_table.set_column_width(2, 230)
entries_table.set_column_width(3, 300)
entries_table.set_column_width(4, 180)
entries_table.set_column_width(5, 120)

scroll.set_widget(scroll_host)

refresh_btn = QPushButton.new(window)
refresh_btn.set_geometry(CONTENT_X + CONTENT_W - 124, TOPBAR_H + 112, 110, 34)
refresh_btn.set_style_sheet(BTN_GHOST)
refresh_btn.set_text('REFRESH')

clickables = [
  { key: :start, view: start_btn, x: CONTENT_X + CONTENT_W - 152, y: TOPBAR_H + 35, w: 64, h: 48 },
  { key: :stop, view: stop_btn, x: CONTENT_X + CONTENT_W - 80, y: TOPBAR_H + 35, w: 64, h: 48 },
  { key: :refresh, view: refresh_btn, x: CONTENT_X + CONTENT_W - 124, y: TOPBAR_H + 112, w: 110, h: 34 }
]

inside = lambda do |x, y, rect|
  x >= rect[:x] && x < rect[:x] + rect[:w] && y >= rect[:y] && y < rect[:y] + rect[:h]
end

run_t = lambda do |*args|
  begin
    out, st = Open3.capture2e(TIMETRAP_BIN, *args)
    [st.success?, out]
  rescue Errno::ENOENT
    [false, "Command not found: #{TIMETRAP_BIN}"]
  rescue StandardError => e
    [false, "#{e.class}: #{e.message}"]
  end
end

fetch_entries = lambda do
  if TIMETRAP_API
    Timetrap::Entry.order(:start).all.map do |e|
      {
        'id' => e.id,
        'note' => e.note.to_s,
        'start' => e[:start]&.strftime('%Y-%m-%d %H:%M:%S %z'),
        'end' => e[:end]&.strftime('%Y-%m-%d %H:%M:%S %z'),
        'sheet' => e.sheet.to_s
      }
    end
  else
    ok_all, out_all = run_t.call('display', '--format', 'json')
    return [] unless ok_all

    begin
      parsed = JSON.parse(out_all)
      parsed.is_a?(Array) ? parsed : []
    rescue JSON::ParserError
      []
    end
  end
end

fetch_active = lambda do
  if TIMETRAP_API
    active = Timetrap::Timer.active_entry
    if active
      [true, active.note.to_s, active[:start]]
    else
      [true, 'No running entry', nil]
    end
  else
    ok_now, out_now = run_t.call('now')
    started_at = nil
    if ok_now && out_now =~ /(\d{4}-\d{2}-\d{2} [0-9:]+ [+-]\d{4})/
      begin
        started_at = Time.parse(Regexp.last_match(1))
      rescue ArgumentError
        started_at = nil
      end
    end
    [ok_now, out_now.to_s.strip, started_at]
  end
end

seconds_to_hms = lambda do |seconds|
  seconds = [seconds.to_i, 0].max
  h = seconds / 3600
  m = (seconds % 3600) / 60
  s = seconds % 60
  format('%02d:%02d:%02d', h, m, s)
end

entry_seconds = lambda do |entry|
  start_s = entry['start']
  finish_s = entry['end']
  return 0 if start_s.nil? || start_s.empty?

  begin
    t0 = Time.parse(start_s)
    t1 = finish_s && !finish_s.empty? ? Time.parse(finish_s) : Time.now
    [t1 - t0, 0].max.to_i
  rescue StandardError
    0
  end
end

fmt_entry_day = lambda do |entry|
  return '-' unless entry['start']

  begin
    Time.parse(entry['start']).strftime('%a, %b %d')
  rescue StandardError
    '-'
  end
end

fmt_entry_range = lambda do |entry|
  begin
    s = entry['start'] ? Time.parse(entry['start']).strftime('%H:%M') : '--:--'
    e = entry['end'] ? Time.parse(entry['end']).strftime('%H:%M') : 'running'
    "#{s} - #{e}"
  rescue StandardError
    '--:-- - --:--'
  end
end

week_start_for = lambda do |entry|
  begin
    dt = Time.parse(entry['start']).to_date
    dt - ((dt.wday + 6) % 7)
  rescue StandardError
    Date.today
  end
end

split_sheet = lambda do |sheet|
  raw = sheet.to_s
  return ['(default)', '(default task)'] if raw.strip.empty?

  parts = raw.split('|', 2)
  if parts.length == 2
    project = parts[0].strip
    task = parts[1].strip
    project = '(default)' if project.empty?
    task = '(default task)' if task.empty?
    [project, task]
  else
    [raw.strip, '(default task)']
  end
end

current_started_at = nil
selected_project = '* ALL'
entries_cache = []

refresh_project_sidebar = lambda do
  projects = entries_cache.map { |e| split_sheet.call(e['sheet']).first }.uniq.sort
  values = ['* ALL', *projects].first(PROJECT_SLOT_COUNT)

  project_slots.each_with_index do |slot, i|
    project = values[i]
    slot[:project] = project

    if project
      slot[:view].set_text(project[0, 24])
      slot[:view].set_style_sheet(project == selected_project ? PROJ_ACTIVE : PROJ_ITEM)
    else
      slot[:view].set_text('')
      slot[:view].set_style_sheet(PROJ_ITEM)
    end
  end
end

render_table = lambda do
  filtered = if selected_project == '* ALL'
               entries_cache.dup
             else
               entries_cache.select { |e| split_sheet.call(e['sheet']).first == selected_project }
             end

  recent = filtered.last(220).reverse

  # Group by week start (descending by week)
  by_week = {}
  recent.each do |entry|
    ws = week_start_for.call(entry)
    by_week[ws] ||= []
    by_week[ws] << entry
  end

  weeks = by_week.keys.sort.reverse
  total_rows = 1 + weeks.sum { |wk| 1 + by_week[wk].length }

  entries_table.clear_contents
  entries_table.set_row_count(total_rows)

  headers = ['Day', 'Project', 'Task', 'Note', 'Range', 'Duration']
  headers.each_with_index do |h, col|
    cell = QLabel.new(entries_table)
    cell.set_alignment(Qt::AlignCenter)
    cell.set_style_sheet(CELL_HEAD)
    cell.set_text(h)
    entries_table.set_cell_widget(0, col, cell)
  end
  entries_table.set_row_height(0, 30)

  total_sec = 0
  row = 1
  weeks.each do |wk|
    week_entries = by_week[wk]
    week_sec = week_entries.sum { |e| entry_seconds.call(e) }
    total_sec += week_sec

    hdr = QLabel.new(entries_table)
    hdr.set_alignment(Qt::AlignCenter)
    hdr.set_style_sheet(CELL_GROUP)
    hdr.set_text("Week #{wk.strftime('%Y-%m-%d')}..#{(wk + 6).strftime('%Y-%m-%d')} | Entries: #{week_entries.length} | Total: #{seconds_to_hms.call(week_sec)}")
    entries_table.set_cell_widget(row, 0, hdr)
    (1..5).each do |c|
      filler = QLabel.new(entries_table)
      filler.set_alignment(Qt::AlignCenter)
      filler.set_style_sheet(CELL_GROUP)
      filler.set_text('')
      entries_table.set_cell_widget(row, c, filler)
    end
    entries_table.set_row_height(row, 30)
    row += 1

    week_entries.each do |entry|
      project, task = split_sheet.call(entry['sheet'])
      note = entry['note'].to_s.strip
      note = '(no note)' if note.empty?
      dur = seconds_to_hms.call(entry_seconds.call(entry))

      c1 = QLabel.new(entries_table)
      c1.set_alignment(Qt::AlignCenter)
      c1.set_style_sheet(CELL_TEXT)
      c1.set_text(fmt_entry_day.call(entry))
      entries_table.set_cell_widget(row, 0, c1)

      c2 = QLabel.new(entries_table)
      c2.set_alignment(Qt::AlignCenter)
      c2.set_style_sheet(CELL_TEXT)
      c2.set_text(project[0, 30])
      entries_table.set_cell_widget(row, 1, c2)

      c3 = QLabel.new(entries_table)
      c3.set_alignment(Qt::AlignCenter)
      c3.set_style_sheet(CELL_TEXT)
      c3.set_text(task[0, 30])
      entries_table.set_cell_widget(row, 2, c3)

      c4 = QLabel.new(entries_table)
      c4.set_alignment(Qt::AlignCenter)
      c4.set_style_sheet(CELL_TEXT)
      c4.set_text(note[0, 48])
      entries_table.set_cell_widget(row, 3, c4)

      c5 = QLabel.new(entries_table)
      c5.set_alignment(Qt::AlignCenter)
      c5.set_style_sheet(CELL_TEXT)
      c5.set_text(fmt_entry_range.call(entry))
      entries_table.set_cell_widget(row, 4, c5)

      c6 = QLabel.new(entries_table)
      c6.set_alignment(Qt::AlignCenter)
      c6.set_style_sheet(CELL_DUR)
      c6.set_text(dur)
      entries_table.set_cell_widget(row, 5, c6)

      entries_table.set_row_height(row, 34)
      row += 1
    end
  end

  summary.set_text("Selected: #{selected_project} | Entries: #{filtered.length} | Total: #{seconds_to_hms.call(total_sec)}")
  project_pill.set_text("Project filter: #{selected_project[0, 18]}")

  table_h = [(total_rows * 36) + 20, 520].max
  scroll_host.set_geometry(0, 0, CONTENT_W - 20, table_h + 20)
  entries_table.set_geometry(8, 8, CONTENT_W - 40, table_h)
end

refresh_data = lambda do
  ok_now, now_text, started_at = fetch_active.call
  current_started_at = started_at
  entries_cache = fetch_entries.call

  projects = entries_cache.map { |e| split_sheet.call(e['sheet']).first }.uniq
  selected_project = '* ALL' if selected_project != '* ALL' && !projects.include?(selected_project)

  title_text = ok_now ? now_text.to_s.lines.first.to_s.strip : now_text.to_s
  task_input.text = title_text.empty? ? 'gui-clockify' : title_text[0, 100]

  refresh_project_sidebar.call
  render_table.call
end

flash = lambda do |label|
  label.set_style_sheet(BTN_ACTIVE)
  QApplication.process_events
  sleep(0.04)

  if label == start_btn
    label.set_style_sheet(BTN_PRIMARY)
  elsif label == stop_btn
    label.set_style_sheet(BTN_DANGER)
  else
    label.set_style_sheet(BTN_GHOST)
  end
end

handle_action = lambda do |key|
  case key
  when :start
    note = task_input.text.to_s.strip
    note = 'gui-clockify' if note.empty?
    if TIMETRAP_API
      begin
        Timetrap::Timer.start(note)
        current_started_at = Time.now
      rescue StandardError
        # fall through to refresh
      end
    else
      ok, _out = run_t.call('in', note)
      current_started_at = Time.now if ok
    end
    refresh_data.call
  when :stop
    if TIMETRAP_API
      begin
        active = Timetrap::Timer.active_entry
        Timetrap::Timer.stop(active) if active
      rescue StandardError
        # fall through to refresh
      end
    else
      run_t.call('out')
    end
    current_started_at = nil
    refresh_data.call
  when :refresh
    refresh_data.call
  end
end

refresh_data.call
window.show
QApplication.process_events

prev_left = false
last_timer_tick = Time.now

loop do
  QApplication.process_events
  break if window.is_visible.zero?

  now = Time.now
  clock.set_text(now.strftime('%a %d %b %Y  %H:%M:%S'))

  if current_started_at
    live_timer.set_text(seconds_to_hms.call(now - current_started_at))
  else
    live_timer.set_text('00:00:00')
  end

  if now - last_timer_tick > 30
    refresh_data.call
    last_timer_tick = now
  end

  mx = QApplication.mouse_x
  my = QApplication.mouse_y
  left = (QApplication.mouse_buttons & LEFT_BUTTON) != 0
  lx = Qt::Native.qwidget_map_from_global_x(window.handle, mx, my)
  ly = Qt::Native.qwidget_map_from_global_y(window.handle, mx, my)

  if left && !prev_left
    clicked = clickables.find { |c| inside.call(lx, ly, c) }
    if clicked
      flash.call(clicked[:view])
      handle_action.call(clicked[:key])
    end

    project_clicked = project_slots.find { |s| s[:project] && inside.call(lx, ly, s) }
    if project_clicked
      selected_project = project_clicked[:project]
      refresh_project_sidebar.call
      render_table.call
    end
  end

  prev_left = left
  sleep(0.01)
end

app.dispose

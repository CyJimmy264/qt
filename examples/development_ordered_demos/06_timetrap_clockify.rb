# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'date'
require 'json'
require 'open3'
require 'time'
require 'qt'

begin
  require 'timetrap'
rescue LoadError
  # CLI fallback when gem is not available.
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
DEBUG_UI = ENV['TIMETRAP_UI_DEBUG'] == '1'
AUTO_REFRESH_SEC = begin
  Integer(ENV.fetch('TIMETRAP_UI_AUTO_REFRESH_SEC', '30'))
rescue ArgumentError, TypeError
  30
end

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
INPUT_LIKE = 'background-color: #ffffff; border: 1px solid #cfd8e3; color: #111827; font-size: 14px; padding-left: 8px;'
BTN_PRIMARY = 'background-color: #0ea5e9; border: 1px solid #0284c7; color: #ffffff; font-size: 14px; font-weight: 800;'
BTN_DANGER = 'background-color: #ef4444; border: 1px solid #dc2626; color: #ffffff; font-size: 14px; font-weight: 800;'
BTN_GHOST = 'background-color: #ffffff; border: 1px solid #cfd8e3; color: #0f172a; font-size: 13px; font-weight: 700;'
BTN_ACTIVE = 'background-color: #dbeafe; border: 2px solid #3b82f6; color: #0f172a; font-size: 13px; font-weight: 800;'
AREA_STYLE = <<~QSS.tr("\n", ' ')
  QScrollArea {
    background-color: #f3f6fa;
    border: 1px solid #d9e0e7;
  }
  QScrollBar:vertical {
    background: #eef2f6;
    width: 12px;
    margin: 2px;
    border: 1px solid #d5dde7;
    border-radius: 6px;
  }
  QScrollBar::handle:vertical {
    background: #9aa8b8;
    min-height: 28px;
    border-radius: 5px;
  }
  QScrollBar::handle:vertical:hover {
    background: #7f90a3;
  }
  QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
    height: 0px;
    background: transparent;
    border: none;
  }
  QScrollBar::add-page:vertical, QScrollBar::sub-page:vertical {
    background: transparent;
  }
QSS
WEEK_STYLE = 'background-color: #dce3ea; border: 1px solid #c8d1db; color: #111827; ' \
             'font-size: 16px; font-weight: 800; padding-left: 12px;'
DAY_STYLE = 'background-color: #ecf1f6; border: 1px solid #d5dee8; color: #5b6776; ' \
            'font-size: 13px; font-weight: 700; padding-left: 12px;'
PROJECT_ROW = 'background-color: #ffffff; border: 1px solid #d8e0ea; color: #0f172a; ' \
              'font-size: 14px; font-weight: 700; padding-left: 12px; text-align: left;'
DETAIL_ROW = 'background-color: #f9fbfd; border: 1px solid #e3e8ef; color: #334155; ' \
             'font-size: 12px; padding-left: 24px;'

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
  y = 316 + (i * 34)
  view = QPushButton.new(window)
  view.set_geometry(12, y, SIDEBAR_W - 24, 30)
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
project_pill.set_text('Project: ALL')

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
scroll.set_widget_resizable(0)
scroll.set_style_sheet(AREA_STYLE)

scroll_host = QWidget.new(window)
scroll_host.set_geometry(0, 0, CONTENT_W - 20, 1200)
scroll_host.set_style_sheet('background-color: #f3f6fa; border: 0px;')
scroll.set_widget(scroll_host)

refresh_btn = QPushButton.new(window)
refresh_btn.set_geometry(CONTENT_X + CONTENT_W - 124, TOPBAR_H + 112, 110, 34)
refresh_btn.set_style_sheet(BTN_GHOST)
refresh_btn.set_text('REFRESH')

expand_all_btn = QPushButton.new(window)
expand_all_btn.set_geometry(CONTENT_X + CONTENT_W - 364, TOPBAR_H + 112, 112, 34)
expand_all_btn.set_style_sheet(BTN_GHOST)
expand_all_btn.set_text('EXPAND ALL')

collapse_all_btn = QPushButton.new(window)
collapse_all_btn.set_geometry(CONTENT_X + CONTENT_W - 244, TOPBAR_H + 112, 112, 34)
collapse_all_btn.set_style_sheet(BTN_GHOST)
collapse_all_btn.set_text('COLLAPSE ALL')

run_t = lambda do |*args|
  out, st = Open3.capture2e(TIMETRAP_BIN, *args)
  [st.success?, out]
rescue Errno::ENOENT
  [false, "Command not found: #{TIMETRAP_BIN}"]
rescue StandardError => e
  [false, "#{e.class}: #{e.message}"]
end

dbg = lambda do |msg|
  puts "[timetrap-ui] #{msg}" if DEBUG_UI
end

ptr = lambda do |obj|
  h = obj&.handle
  h ? format('0x%x', h.address) : 'nil'
rescue StandardError
  'err'
end

geo = lambda do |x, y, w, h|
  "x=#{x} y=#{y} w=#{w} h=#{h}"
end

parse_time_or_nil = lambda do |value|
  Time.parse(value)
rescue ArgumentError, TypeError
  nil
end

fetch_entries = lambda do
  if TIMETRAP_API
    Timetrap::Entry.order(:start).all.map do |e|
      {
        id: e.id,
        note: e.note.to_s,
        sheet: e.sheet.to_s,
        start_time: e[:start],
        end_time: e[:end]
      }
    end
  else
    ok, out = run_t.call('display', '--format', 'json')
    return [] unless ok

    begin
      parsed = JSON.parse(out)
      next [] unless parsed.is_a?(Array)

      parsed.map do |e|
        {
          id: e['id'],
          note: e['note'].to_s,
          sheet: e['sheet'].to_s,
          start_time: parse_time_or_nil.call(e['start']),
          end_time: parse_time_or_nil.call(e['end'])
        }
      end
    rescue JSON::ParserError
      []
    end
  end
end

fetch_active = lambda do
  if TIMETRAP_API
    active = Timetrap::Timer.active_entry
    [active, active ? active[:start] : nil]
  else
    ok, out = run_t.call('now')
    if ok && out =~ /(\d{4}-\d{2}-\d{2} [0-9:]+ [+-]\d{4})/
      [true, parse_time_or_nil.call(Regexp.last_match(1))]
    else
      [nil, nil]
    end
  end
end

seconds_to_hms = lambda do |seconds|
  seconds = [seconds.to_i, 0].max
  h = seconds / 3600
  m = (seconds % 3600) / 60
  s = seconds % 60
  format('%<hours>02d:%<minutes>02d:%<seconds>02d', hours: h, minutes: m, seconds: s)
end

entry_seconds = lambda do |entry|
  st = entry[:start_time]
  en = entry[:end_time] || Time.now
  return 0 unless st

  [en.to_i - st.to_i, 0].max
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

week_start_for = lambda do |entry|
  dt = entry[:start_time]&.to_date || Date.today
  dt - ((dt.wday + 6) % 7)
end

fmt_range = lambda do |entry|
  s = entry[:start_time] ? entry[:start_time].strftime('%H:%M') : '--:--'
  e = entry[:end_time] ? entry[:end_time].strftime('%H:%M') : 'running'
  "#{s} - #{e}"
end

current_started_at = nil
selected_project = '* ALL'
entries_cache = []
expanded_rows = {}
expanded_weeks = {}
render_widgets = []
pending_render = false
pending_refresh = false
last_week_keys = []
last_project_keys = []

refresh_project_sidebar = lambda do
  projects = entries_cache.map { |e| split_sheet.call(e[:sheet]).first }.uniq.sort
  values = ['* ALL', *projects].first(PROJECT_SLOT_COUNT)
  dbg.call("sidebar projects=#{projects.length} selected=#{selected_project.inspect}")

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

add_row_label = lambda do |x, y, w, h, style, text, center: false|
  label = QLabel.new(scroll_host)
  label.set_geometry(x, y, w, h)
  label.set_style_sheet(style)
  label.set_text(text)
  label.set_alignment(Qt::AlignCenter) if center
  label.show
  render_widgets << label
  label
end

filtered_entries_for_selection = lambda do |entries, selected|
  return entries.dup if selected == '* ALL'

  entries.select { |e| split_sheet.call(e[:sheet]).first == selected }
end

render_begin_log_text = lambda do |selected, all_count, filtered_count|
  "render begin selected=#{selected.inspect} entries_cache=#{all_count} filtered=#{filtered_count}"
end

week_title_text = lambda do |week_marker, wk, week_sec|
  "#{week_marker}  #{wk.strftime('%b %-d')} - #{(wk + 6).strftime('%b %-d')}         " \
    "Week total: #{seconds_to_hms.call(week_sec)}"
end

project_row_text = lambda do |marker, group, p_total|
  "#{marker}  #{group[:project]}  |  #{group[:task]}   " \
    "(#{group[:entries].length} entries)   #{seconds_to_hms.call(p_total)}"
end

summary_text = lambda do |selected, filtered_count, total_sec|
  "Selected: #{selected} | Entries: #{filtered_count} | Total: #{seconds_to_hms.call(total_sec)}"
end

render_done_log_text = lambda do |week_count, day_count, project_group_count, content_h,
                                  total_widgets, lbl_count, btn_count, row_count|
  "render done weeks=#{week_count} days=#{day_count} groups=#{project_group_count} " \
    "content_h=#{content_h} widgets_total=#{total_widgets} labels=#{lbl_count} " \
    "buttons=#{btn_count} click_rows=#{row_count}"
end

render_geometry_log_text = lambda do |host_w, content_h|
  "render geometry scroll=#{geo.call(CONTENT_X, TOPBAR_H + 156, CONTENT_W, WINDOW_H - (TOPBAR_H + 170))} " \
    "host=#{geo.call(0, 0, host_w, content_h)}"
end

render_blocks = lambda do
  render_widgets.each(&:hide)
  render_widgets.clear

  filtered = filtered_entries_for_selection.call(entries_cache, selected_project)
  dbg.call(render_begin_log_text.call(selected_project, entries_cache.length, filtered.length))

  recent = filtered.last(260).reverse

  by_week = {}
  recent.each do |entry|
    ws = week_start_for.call(entry)
    by_week[ws] ||= []
    by_week[ws] << entry
  end

  y = 10
  total_sec = 0
  week_count = 0
  day_count = 0
  project_group_count = 0
  week_keys_this_render = []
  project_keys_this_render = []

  by_week.keys.sort.reverse.each do |wk|
    week_count += 1
    week_entries = by_week[wk]
    week_sec = week_entries.sum { |e| entry_seconds.call(e) }
    total_sec += week_sec
    week_key = wk.iso8601
    week_keys_this_render << week_key
    week_expanded = expanded_weeks.fetch(week_key, true)
    week_marker = week_expanded ? '▼' : '▶'
    week_label = QLabel.new(scroll_host)
    week_label.set_geometry(10, y, CONTENT_W - 162, 44)
    week_label.set_style_sheet(WEEK_STYLE)
    week_label.set_text(week_title_text.call(week_marker, wk, week_sec))
    week_label.show
    render_widgets << week_label

    toggle = QLabel.new(scroll_host)
    toggle.set_geometry(CONTENT_W - 144, y + 4, 132, 36)
    toggle.set_style_sheet(PROJECT_ROW)
    toggle.set_alignment(Qt::AlignCenter)
    toggle.set_text(week_expanded ? 'COLLAPSE WEEK' : 'EXPAND WEEK')
    toggle.show
    render_widgets << toggle

    week_click_key = week_key
    toggle.on(:mouse_button_release) do |_ev|
      expanded_weeks[week_click_key] = !expanded_weeks.fetch(week_click_key, true)
      dbg.call("click week-toggle #{week_click_key} expanded=#{expanded_weeks[week_click_key]}")
      pending_render = true
    end
    y += 52
    next unless week_expanded

    by_day = {}
    week_entries.each do |entry|
      day_key = (entry[:start_time] || Time.now).to_date
      by_day[day_key] ||= []
      by_day[day_key] << entry
    end

    by_day.keys.sort.reverse.each do |day|
      day_count += 1
      day_entries = by_day[day]
      day_sec = day_entries.sum { |e| entry_seconds.call(e) }
      add_row_label.call(
        14, y, CONTENT_W - 54, 38, DAY_STYLE,
        "#{day.strftime('%a, %b %-d')}                                      Total: #{seconds_to_hms.call(day_sec)}"
      )
      y += 42

      by_project = {}
      day_entries.each do |entry|
        project, task = split_sheet.call(entry[:sheet])
        key = "#{project}\u0000#{task}"
        by_project[key] ||= { project: project, task: task, entries: [] }
        by_project[key][:entries] << entry
      end

      by_project.values.sort_by { |g| [g[:project].downcase, g[:task].downcase] }.each do |group|
        project_group_count += 1
        p_total = group[:entries].sum { |e| entry_seconds.call(e) }
        exp_key = "#{day}|#{group[:project]}|#{group[:task]}"
        project_keys_this_render << exp_key
        expanded = expanded_rows[exp_key]
        marker = expanded ? '▼' : '▶'
        click_key = exp_key
        row = QLabel.new(scroll_host)
        row.set_geometry(18, y, CONTENT_W - 62, 40)
        row.set_style_sheet(PROJECT_ROW)
        row.set_text(project_row_text.call(marker, group, p_total))
        row.show
        render_widgets << row
        row.on(:mouse_button_release) do |_ev|
          dbg.call("click project-row #{click_key}")
          expanded_rows[click_key] = !expanded_rows[click_key]
          dbg.call("click project-row toggled #{click_key}=#{expanded_rows[click_key]}")
          pending_render = true
        end
        y += 42

        next unless expanded

        group[:entries].sort_by { |e| e[:start_time] || Time.now }.reverse.each do |entry|
          note = entry[:note].to_s.strip
          note = '(no note)' if note.empty?
          detail = "#{fmt_range.call(entry)}   #{seconds_to_hms.call(entry_seconds.call(entry))}   #{note[0, 80]}"
          add_row_label.call(26, y, CONTENT_W - 78, 34, DETAIL_ROW, detail)
          y += 36
        end
      end

      y += 10
    end

    y += 8
  end

  if filtered.empty?
    add_row_label.call(18, y + 8, CONTENT_W - 62, 44, DAY_STYLE, "No entries for filter: #{selected_project}")
    y += 56
    dbg.call("render empty for selected=#{selected_project.inspect}")
  end

  summary.set_text(summary_text.call(selected_project, filtered.length, total_sec))
  project_pill.set_text("Project: #{selected_project[0, 20]}")
  last_week_keys = week_keys_this_render
  last_project_keys = project_keys_this_render
  content_h = [y + 30, 900].max
  host_w = CONTENT_W - 20
  scroll_host.set_geometry(0, 0, host_w, content_h)
  btn_count = render_widgets.count { |w| w.is_a?(QPushButton) }
  row_count = render_widgets.count { |w| w.is_a?(QLabel) && w.respond_to?(:on) }
  lbl_count = render_widgets.count { |w| w.is_a?(QLabel) }
  dbg.call(
    render_done_log_text.call(
      week_count, day_count, project_group_count, content_h, render_widgets.length, lbl_count, btn_count, row_count
    )
  )
  dbg.call(render_geometry_log_text.call(host_w, content_h))
  if DEBUG_UI
    sample = render_widgets.first(3).map do |w|
      t =
        if w.respond_to?(:text)
          w.text.to_s
        elsif w.respond_to?(:window_title)
          w.window_title.to_s
        else
          ''
        end
      "#{w.class}@#{ptr.call(w)}:#{t[0, 48].inspect}"
    end
    dbg.call("render sample #{sample.join(' | ')} | visible window=#{window.is_visible} host=#{scroll_host.is_visible}")
  end
end

refresh_data = lambda do
  active, started_at = fetch_active.call
  current_started_at = started_at

  entries_cache = fetch_entries.call
  dbg.call("refresh_data fetched entries=#{entries_cache.length} api=#{TIMETRAP_API}")
  projects = entries_cache.map { |e| split_sheet.call(e[:sheet]).first }.uniq
  selected_project = '* ALL' if selected_project != '* ALL' && !projects.include?(selected_project)

  if active.respond_to?(:note)
    txt = active.note.to_s.strip
    task_input.text = txt.empty? ? 'gui-clockify' : txt[0, 100]
  elsif task_input.text.to_s.strip.empty?
    task_input.text = 'gui-clockify'
  end

  expanded_weeks.clear
  expanded_rows.clear

  refresh_project_sidebar.call
  render_blocks.call
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
      rescue StandardError
        # ignore and refresh
      end
    else
      run_t.call('in', note)
    end

    pending_refresh = true
  when :stop
    if TIMETRAP_API
      begin
        active = Timetrap::Timer.active_entry
        Timetrap::Timer.stop(active) if active
      rescue StandardError
        # ignore and refresh
      end
    else
      run_t.call('out')
    end

    current_started_at = nil
    pending_refresh = true
  when :refresh
    pending_refresh = true
  end
end

start_btn.connect('clicked') do |_checked|
  dbg.call('click START')
  flash.call(start_btn)
  pending_refresh = true
  handle_action.call(:start)
end

stop_btn.connect('clicked') do |_checked|
  dbg.call('click STOP')
  flash.call(stop_btn)
  pending_refresh = true
  handle_action.call(:stop)
end

refresh_btn.connect('clicked') do |_checked|
  dbg.call('click REFRESH')
  flash.call(refresh_btn)
  pending_refresh = true
  handle_action.call(:refresh)
end

expand_all_btn.connect('clicked') do |_checked|
  dbg.call('click EXPAND ALL')
  flash.call(expand_all_btn)
  last_week_keys.each { |wk| expanded_weeks[wk] = true }
  last_project_keys.each { |pk| expanded_rows[pk] = true }
  pending_render = true
end

collapse_all_btn.connect('clicked') do |_checked|
  dbg.call('click COLLAPSE ALL')
  flash.call(collapse_all_btn)
  last_week_keys.each { |wk| expanded_weeks[wk] = false }
  last_project_keys.each { |pk| expanded_rows[pk] = false }
  pending_render = true
end

project_slots.each do |slot|
  this_slot = slot
  this_slot[:view].connect('clicked') do |_checked|
    next unless this_slot[:project]

    dbg.call("click project #{this_slot[:project].inspect}")
    selected_project = this_slot[:project]
    refresh_project_sidebar.call
    dbg.call("click project selected=#{selected_project.inspect} slot_y=#{this_slot[:y]} slot_h=#{this_slot[:h]}")
    pending_render = true
  end
end

refresh_data.call
window.show
QApplication.process_events

last_tick = Time.now

# TODO: Replace manual process_events loop with app.exec + QTimer updates.
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

  if AUTO_REFRESH_SEC.positive? && now - last_tick > AUTO_REFRESH_SEC
    dbg.call("auto refresh tick interval=#{AUTO_REFRESH_SEC}s")
    pending_refresh = true
    last_tick = now
  end

  if pending_refresh
    refresh_data.call
    pending_refresh = false
    pending_render = false
  elsif pending_render
    render_blocks.call
    pending_render = false
  end
  sleep(0.01)
end

app.dispose

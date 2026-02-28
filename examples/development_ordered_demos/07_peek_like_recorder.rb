# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'qt'
require 'ffi'
require 'fileutils'
require 'securerandom'
require 'tmpdir'
require 'timeout'

CTRL_MODIFIER = 0x04000000
ALT_MODIFIER = 0x08000000
KEY_R = 0x52
KEY_Q = 0x51
LEFT_BUTTON = 1

# Qt::WindowType / Qt::WidgetAttribute values used as plain integers.
WINDOW_FLAG_WINDOW = 0x00000001
WINDOW_FLAG_FRAMELESS = 0x00000800
WINDOW_FLAG_ALWAYS_ON_TOP = 0x00040000
WINDOW_FLAG_TRANSPARENT_FOR_INPUT = 0x00080000
WA_TRANSPARENT_FOR_MOUSE_EVENTS = 51
WA_NO_SYSTEM_BACKGROUND = 9
WA_TRANSLUCENT_BACKGROUND = 120

FRAME_IDLE_STYLE = 'background-color: rgba(16, 185, 129, 0.08); border: 0px;'
FRAME_RECORDING_STYLE = 'background-color: rgba(239, 68, 68, 0.08); border: 0px;'
BORDER_IDLE_STYLE = 'background-color: rgba(0, 0, 0, 0); border: 1px solid #10b981;'
BORDER_RECORDING_STYLE = 'background-color: rgba(0, 0, 0, 0); border: 1px solid #ef4444;'
HANDLE_IDLE_STYLE = 'background-color: rgba(15, 23, 42, 0.88); border: 1px solid #334155; color: #e2e8f0; font-size: 12px; font-weight: 700;'
HANDLE_RECORDING_STYLE = 'background-color: rgba(127, 29, 29, 0.92); border: 1px solid #ef4444; color: #fee2e2; font-size: 12px; font-weight: 700;'
REC_INDICATOR_STYLE = 'background-color: #ef4444; border: 2px solid #fee2e2; border-radius: 9px;'

HANDLE_W = 320
HANDLE_H = 34
HANDLE_PADDING = 12
MIN_FRAME_W = 160
MIN_FRAME_H = 120
RESIZE_EDGE = 8
RESIZE_CORNER = 14
RESIZE_HANDLE_STYLE = 'background-color: rgba(148, 163, 184, 0.20); border: 1px solid rgba(100, 116, 139, 0.55);'

module X11GlobalHotkey
  extend self

  KEYSYM_R = 0x72
  KEY_PRESS = 2

  CONTROL_MASK = 1 << 2
  ALT_MASK = 1 << 3
  LOCK_MASK = 1 << 1
  MOD2_MASK = 1 << 4

  GRAB_MODE_ASYNC = 1

  class XKeyEvent < FFI::Struct
    layout :type, :int,
           :serial, :ulong,
           :send_event, :int,
           :display, :pointer,
           :window, :ulong,
           :root, :ulong,
           :subwindow, :ulong,
           :time, :ulong,
           :x, :int,
           :y, :int,
           :x_root, :int,
           :y_root, :int,
           :state, :uint,
           :keycode, :uint,
           :same_screen, :int
  end

  class XEvent < FFI::Union
    layout :type, :int,
           :xkey, XKeyEvent,
           :pad, [:long, 24]
  end

  module Lib
    extend FFI::Library
    ffi_lib ['X11', 'libX11.so.6']

    attach_function :x_open_display, :XOpenDisplay, [:pointer], :pointer
    attach_function :x_default_root_window, :XDefaultRootWindow, [:pointer], :ulong
    attach_function :x_keysym_to_keycode, :XKeysymToKeycode, %i[pointer ulong], :uint
    attach_function :x_grab_key, :XGrabKey, %i[pointer int uint ulong int int int], :int
    attach_function :x_ungrab_key, :XUngrabKey, %i[pointer int uint ulong], :int
    attach_function :x_pending, :XPending, [:pointer], :int
    attach_function :x_next_event, :XNextEvent, %i[pointer pointer], :int
    attach_function :x_sync, :XSync, %i[pointer int], :int
    attach_function :x_close_display, :XCloseDisplay, [:pointer], :int
  end

  def start_listener
    return nil if ENV['DISPLAY'].to_s.strip.empty?

    display = Lib.x_open_display(nil)
    return nil if display.null?

    root = Lib.x_default_root_window(display)
    keycode = Lib.x_keysym_to_keycode(display, KEYSYM_R)
    return nil if keycode.zero?

    base_mod = CONTROL_MASK | ALT_MASK
    modifier_combinations = [
      base_mod,
      base_mod | LOCK_MASK,
      base_mod | MOD2_MASK,
      base_mod | LOCK_MASK | MOD2_MASK
    ]

    modifier_combinations.each do |mod|
      Lib.x_grab_key(display, keycode, mod, root, 1, GRAB_MODE_ASYNC, GRAB_MODE_ASYNC)
    end
    Lib.x_sync(display, 0)

    {
      display: display,
      root: root,
      keycode: keycode,
      mods: modifier_combinations,
      event: XEvent.new,
      last_trigger_at: 0.0
    }
  rescue LoadError, FFI::NotFoundError => e
    warn "[hotkey-listener] unavailable: #{e.message}"
    nil
  end

  def poll(listener)
    return 0 if listener.nil?

    triggered = 0
    while Lib.x_pending(listener[:display]).positive?
      Lib.x_next_event(listener[:display], listener[:event].pointer)
      next unless listener[:event][:type] == KEY_PRESS

      key_event = XKeyEvent.new(listener[:event].pointer)
      state = key_event[:state]
      next unless (state & (CONTROL_MASK | ALT_MASK)) == (CONTROL_MASK | ALT_MASK)
      next unless key_event[:keycode] == listener[:keycode]

      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      next if (now - listener[:last_trigger_at]) < 0.25

      listener[:last_trigger_at] = now
      triggered += 1
    end

    triggered
  rescue StandardError => e
    warn "[hotkey-listener] poll failed: #{e.class}: #{e.message}"
    0
  end

  def stop_listener(listener)
    return if listener.nil?

    listener[:mods].each do |mod|
      Lib.x_ungrab_key(listener[:display], listener[:keycode], mod, listener[:root])
    end
    Lib.x_sync(listener[:display], 0)
    Lib.x_close_display(listener[:display]) unless listener[:display].null?
  rescue StandardError => e
    warn "[hotkey-listener] stop failed: #{e.class}: #{e.message}"
  end
end

def recordings_dir
  File.join(Dir.home, 'Видео', 'Записи экрана')
end

def position_config_path
  File.join(Dir.home, '.config', 'qpeek', 'position.conf')
end

def load_position(path)
  return nil unless File.exist?(path)

  values = {}
  File.readlines(path, chomp: true).each do |line|
    key, raw = line.split('=', 2)
    next if key.nil? || raw.nil?

    values[key.strip] = Integer(raw.strip, exception: false)
  end

  left = values['left']
  top = values['top']
  width = values['width']
  height = values['height']
  return nil unless left && top && width && height

  { left: left, top: top, width: width, height: height }
end

def save_position(path, window)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(
    path,
    "top=#{window.y}\nleft=#{window.x}\nwidth=#{window.width}\nheight=#{window.height}\n"
  )
end

def ffmpeg_available?
  system('command -v ffmpeg >/dev/null 2>&1')
end

def now_stamp
  Time.now.strftime('%Y-%m-%d_%H-%M-%S')
end

def ensure_even(value)
  value.even? ? value : value - 1
end

def selected_geometry(window)
  x = window.x
  y = window.y
  w = ensure_even(window.width)
  h = ensure_even(window.height)
  [x, y, [w, 2].max, [h, 2].max]
end

def stop_recorder!(pid)
  return unless pid

  begin
    Process.kill('INT', pid)
  rescue Errno::ESRCH
    return
  end

  begin
    Timeout.timeout(5) { Process.wait(pid) }
  rescue Timeout::Error
    Process.kill('TERM', pid) rescue nil
    Process.wait(pid) rescue nil
  rescue Errno::ECHILD
    nil
  end
end

def choose_output_path(parent)
  FileUtils.mkdir_p(recordings_dir)
  suggested = File.join(recordings_dir, "screen-record-#{now_stamp}.mp4")

  dialog = Qt::QFileDialog.new(parent)
  selected = dialog.get_save_file_name(
    parent,
    'Сохранить запись',
    suggested,
    'MP4 video (*.mp4)',
    nil,
    0
  )

  return nil if selected.nil? || selected.strip.empty?

  selected.end_with?('.mp4') ? selected : "#{selected}.mp4"
end

def start_recorder(window)
  x, y, w, h = selected_geometry(window)
  display = ENV.fetch('DISPLAY', ':0')
  temp_file = File.join(Dir.tmpdir, "qt-peek-like-#{now_stamp}-#{SecureRandom.hex(4)}.mp4")

  ffmpeg_args = [
    'ffmpeg',
    '-f', 'x11grab',
    '-show_region', '0',
    '-framerate', '25',
    '-video_size', "#{w}x#{h}",
    '-i', "#{display}+#{x},#{y}",
    '-filter:v', 'scale=iw/1:-1,crop=iw-mod(iw\\,2):ih-mod(ih\\,2)',
    '-codec:v', 'libx264',
    '-preset:v', 'fast',
    '-pix_fmt', 'yuv420p',
    '-r', '25',
    '-y', temp_file
  ]

  log_file = File.join(Dir.tmpdir, "qt-peek-like-ffmpeg-#{now_stamp}.log")
  log_io = File.open(log_file, 'a')
  pid = Process.spawn(*ffmpeg_args, out: log_io, err: log_io)
  log_io.close

  [pid, temp_file, log_file, [x, y, w, h]]
end

def floating_flags
  WINDOW_FLAG_WINDOW | WINDOW_FLAG_FRAMELESS | WINDOW_FLAG_ALWAYS_ON_TOP
end

def apply_handle_state(label, recording)
  if recording
    label.set_style_sheet(HANDLE_RECORDING_STYLE)
    label.set_text('REC | Ctrl+Alt+R stop | Drag here to move')
  else
    label.set_style_sheet(HANDLE_IDLE_STYLE)
    label.set_text('Ctrl+Alt+R start/stop | Drag here to move')
  end
end

def set_edit_mode(frame, handle, resize_handles, enabled)
  if enabled
    frame.set_window_flag(WINDOW_FLAG_TRANSPARENT_FOR_INPUT, 0)
    frame.set_attribute(WA_TRANSPARENT_FOR_MOUSE_EVENTS, 0)
    handle.show
    resize_handles.each_value(&:show)
  else
    frame.set_window_flag(WINDOW_FLAG_TRANSPARENT_FOR_INPUT, 1)
    frame.set_attribute(WA_TRANSPARENT_FOR_MOUSE_EVENTS, 1)
    handle.hide
    resize_handles.each_value(&:hide)
  end

  frame.show
end

app = QApplication.new(0, [])

frame = QWidget.new do |w|
  w.set_window_flags(floating_flags)
  w.set_attribute(WA_NO_SYSTEM_BACKGROUND, 1)
  w.set_attribute(WA_TRANSLUCENT_BACKGROUND, 1)
  w.set_geometry(260, 180, 1024, 576)
  w.set_style_sheet(FRAME_IDLE_STYLE)
end

saved_position = load_position(position_config_path)
if saved_position
  frame.set_geometry(
    saved_position[:left],
    saved_position[:top],
    [saved_position[:width], MIN_FRAME_W].max,
    [saved_position[:height], MIN_FRAME_H].max
  )
end

border_overlay = QLabel.new(frame)
border_overlay.set_attribute(WA_TRANSPARENT_FOR_MOUSE_EVENTS, 1)
border_overlay.set_style_sheet(BORDER_IDLE_STYLE)

handle = QWidget.new(frame)
handle_label = QLabel.new(handle)
handle_label.set_alignment(Qt::AlignCenter)
apply_handle_state(handle_label, false)

record_indicator = QLabel.new(frame)
record_indicator.set_style_sheet(REC_INDICATOR_STYLE)
record_indicator.hide

resize_handles = {
  n: QWidget.new(frame),
  s: QWidget.new(frame),
  e: QWidget.new(frame),
  w: QWidget.new(frame),
  ne: QWidget.new(frame),
  nw: QWidget.new(frame),
  se: QWidget.new(frame),
  sw: QWidget.new(frame)
}
resize_handles.each_value { |grip| grip.set_style_sheet(RESIZE_HANDLE_STYLE) }

recording = false
ffmpeg_pid = nil
temp_output = nil
last_log = nil
last_geometry = nil

dragging = false
drag_local_x = 0
drag_local_y = 0

layout_overlays = lambda do
  fw = frame.width
  fh = frame.height

  handle_w = [[HANDLE_W, fw - (HANDLE_PADDING * 2)].min, 120].max
  border_overlay.set_geometry(0, 0, fw, fh)
  handle.set_geometry(HANDLE_PADDING, HANDLE_PADDING, handle_w, HANDLE_H)
  handle_label.set_geometry(0, 0, handle_w, HANDLE_H)

  record_indicator.set_geometry(fw - 24, 8, 18, 18)

  resize_handles[:n].set_geometry(RESIZE_CORNER, 0, [fw - (RESIZE_CORNER * 2), 16].max, RESIZE_EDGE)
  resize_handles[:s].set_geometry(RESIZE_CORNER, fh - RESIZE_EDGE, [fw - (RESIZE_CORNER * 2), 16].max, RESIZE_EDGE)
  resize_handles[:w].set_geometry(0, RESIZE_CORNER, RESIZE_EDGE, [fh - (RESIZE_CORNER * 2), 16].max)
  resize_handles[:e].set_geometry(fw - RESIZE_EDGE, RESIZE_CORNER, RESIZE_EDGE, [fh - (RESIZE_CORNER * 2), 16].max)
  resize_handles[:nw].set_geometry(0, 0, RESIZE_CORNER, RESIZE_CORNER)
  resize_handles[:ne].set_geometry(fw - RESIZE_CORNER, 0, RESIZE_CORNER, RESIZE_CORNER)
  resize_handles[:sw].set_geometry(0, fh - RESIZE_CORNER, RESIZE_CORNER, RESIZE_CORNER)
  resize_handles[:se].set_geometry(fw - RESIZE_CORNER, fh - RESIZE_CORNER, RESIZE_CORNER, RESIZE_CORNER)
end

set_frame_geometry = lambda do |x, y, w, h|
  frame.set_geometry(x, y, [w, MIN_FRAME_W].max, [h, MIN_FRAME_H].max)
  layout_overlays.call
end

move_overlay_to = lambda do |new_frame_x, new_frame_y|
  set_frame_geometry.call(new_frame_x, new_frame_y, frame.width, frame.height)
end

toggle_recording = lambda do
  next unless ffmpeg_available?

  if recording
    stop_recorder!(ffmpeg_pid)
    ffmpeg_pid = nil
    recording = false
    frame.set_style_sheet(FRAME_IDLE_STYLE)
    border_overlay.set_style_sheet(BORDER_IDLE_STYLE)
    apply_handle_state(handle_label, false)
    record_indicator.hide
    set_edit_mode(frame, handle, resize_handles, true)
    frame.activate_window
    frame.grab_keyboard

    save_to = choose_output_path(frame)
    if save_to
      FileUtils.mkdir_p(File.dirname(save_to))
      FileUtils.mv(temp_output, save_to)
      handle_label.set_text("Saved: #{save_to}")
      puts "[saved] #{save_to}"
    else
      handle_label.set_text('Save canceled. Temp file kept.')
      puts "[cancelled-save] temp file left at: #{temp_output}"
    end

    puts "[ffmpeg-log] #{last_log}" if last_log
  else
    ffmpeg_pid, temp_output, last_log, last_geometry = start_recorder(frame)
    recording = true
    frame.set_style_sheet(FRAME_RECORDING_STYLE)
    border_overlay.set_style_sheet(BORDER_RECORDING_STYLE)
    apply_handle_state(handle_label, true)
    record_indicator.show
    set_edit_mode(frame, handle, resize_handles, false)
    puts "[recording] pid=#{ffmpeg_pid} area=#{last_geometry.inspect} tmp=#{temp_output}"
  end
end

handle.on(:mouse_button_press) do |evt|
  next unless evt[:c] == LEFT_BUTTON

  dragging = true
  drag_local_x = evt[:a]
  drag_local_y = evt[:b]
end

handle.on(:mouse_move) do |evt|
  next unless dragging
  next unless evt[:d].anybits?(LEFT_BUTTON)

  delta_x = evt[:a] - drag_local_x
  delta_y = evt[:b] - drag_local_y
  move_overlay_to.call(frame.x + delta_x, frame.y + delta_y)
end

handle.on(:mouse_button_release) do |_evt|
  dragging = false
end

resize_state = nil
resize_handles.each do |dir, grip|
  grip.on(:mouse_button_press) do |evt|
    next unless evt[:c] == LEFT_BUTTON

    resize_state = {
      dir: dir,
      start_global_x: frame.x + grip.x + evt[:a],
      start_global_y: frame.y + grip.y + evt[:b],
      frame_x: frame.x,
      frame_y: frame.y,
      frame_w: frame.width,
      frame_h: frame.height
    }
  end

  grip.on(:mouse_move) do |evt|
    next unless resize_state
    next unless evt[:d].anybits?(LEFT_BUTTON)

    current_global_x = frame.x + grip.x + evt[:a]
    current_global_y = frame.y + grip.y + evt[:b]
    dx = current_global_x - resize_state[:start_global_x]
    dy = current_global_y - resize_state[:start_global_y]

    new_x = resize_state[:frame_x]
    new_y = resize_state[:frame_y]
    new_w = resize_state[:frame_w]
    new_h = resize_state[:frame_h]

    new_w = resize_state[:frame_w] + dx if %i[e ne se].include?(resize_state[:dir])
    new_h = resize_state[:frame_h] + dy if %i[s se sw].include?(resize_state[:dir])

    if %i[w nw sw].include?(resize_state[:dir])
      new_x = resize_state[:frame_x] + dx
      new_w = resize_state[:frame_w] - dx
      if new_w < MIN_FRAME_W
        new_x -= (MIN_FRAME_W - new_w)
        new_w = MIN_FRAME_W
      end
    end

    if %i[n ne nw].include?(resize_state[:dir])
      new_y = resize_state[:frame_y] + dy
      new_h = resize_state[:frame_h] - dy
      if new_h < MIN_FRAME_H
        new_y -= (MIN_FRAME_H - new_h)
        new_h = MIN_FRAME_H
      end
    end

    set_frame_geometry.call(new_x, new_y, new_w, new_h)
  end

  grip.on(:mouse_button_release) do |_evt|
    resize_state = nil
  end
end

# Fallback hotkey when frame has keyboard focus.
frame.on(:key_press) do |evt|
  key = evt[:a]
  modifiers = evt[:b]
  ctrl_pressed = (modifiers & CTRL_MODIFIER) != 0
  if ctrl_pressed && key == KEY_Q && !recording
    frame.close
    next
  end

  alt_pressed = (modifiers & ALT_MODIFIER) != 0
  next unless key == KEY_R && ctrl_pressed && alt_pressed

  toggle_recording.call
end

hotkey_listener = X11GlobalHotkey.start_listener

unless ffmpeg_available?
  handle_label.set_text('ffmpeg not found in PATH. Install ffmpeg and restart.')
end

frame.show
layout_overlays.call
set_edit_mode(frame, handle, resize_handles, true)
frame.activate_window
frame.grab_keyboard
QApplication.process_events

hotkey_status_printed = false
last_persisted_geometry = [frame.x, frame.y, frame.width, frame.height]
while frame.is_visible != 0
  QApplication.process_events

  unless hotkey_status_printed
    if hotkey_listener.nil?
      puts '[hotkey] global Ctrl+Alt+R unavailable, fallback to focused window hotkey'
      hotkey_status_printed = true
    else
      puts '[hotkey] global Ctrl+Alt+R listener active'
      hotkey_status_printed = true
    end
  end

  toggles = X11GlobalHotkey.poll(hotkey_listener)
  toggles.times { toggle_recording.call }

  geometry_now = [frame.x, frame.y, frame.width, frame.height]
  if geometry_now != last_persisted_geometry
    save_position(position_config_path, frame)
    last_persisted_geometry = geometry_now
  end

  sleep(0.01)
end

if recording
  stop_recorder!(ffmpeg_pid)
  ffmpeg_pid = nil
  save_to = choose_output_path(frame)
  if save_to
    FileUtils.mkdir_p(File.dirname(save_to))
    FileUtils.mv(temp_output, save_to)
    puts "[saved-on-exit] #{save_to}"
  else
    puts "[cancelled-save-on-exit] temp file left at: #{temp_output}"
  end
end

X11GlobalHotkey.stop_listener(hotkey_listener)
save_position(position_config_path, frame)
app.dispose

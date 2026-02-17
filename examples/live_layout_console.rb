# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'qt'
require 'irb'

app = QApplication.new(0, [])
window = QWidget.new do |w|
  w.set_window_title('Qt Live Layout Console')
  w.resize(700, 500)
end

layout = QVBoxLayout.new(window)
window.set_layout(layout)

items = []

banner = QLabel.new(window) do |l|
  l.set_text('Use IRB helpers: add_label, add_button, remove_last')
  l.set_alignment(Qt::AlignCenter)
end
layout.add_widget(banner)
items << banner

jobs = Queue.new
running = true

console = Object.new
console.instance_variable_set(:@app, app)
console.instance_variable_set(:@window, window)
console.instance_variable_set(:@layout, layout)
console.instance_variable_set(:@jobs, jobs)
console.instance_variable_set(:@items, items)

console.define_singleton_method(:app) { @app }
console.define_singleton_method(:window) { @window }
console.define_singleton_method(:layout) { @layout }
console.define_singleton_method(:items) { @items }

console.define_singleton_method(:gui) do |&block|
  raise ArgumentError, 'pass block to gui { ... }' unless block

  reply = Queue.new
  @jobs << [block, reply]
  ok, value = reply.pop
  raise value unless ok

  value
end

console.define_singleton_method(:add_label) do |text = 'new label'|
  gui do
    label = QLabel.new(@window)
    label.set_text(text)
    label.set_alignment(Qt::AlignCenter)
    @layout.add_widget(label)
    @items << label
    label
  end
end

console.define_singleton_method(:add_button) do |text = 'new button'|
  gui do
    button = QPushButton.new(@window)
    button.set_text(text)
    @layout.add_widget(button)
    @items << button
    button
  end
end

console.define_singleton_method(:remove_last) do
  gui do
    widget = @items.pop
    if widget
      @layout.remove_widget(widget)
      widget.hide if widget.respond_to?(:hide)
      widget
    else
      nil
    end
  end
end

console.define_singleton_method(:help) do
  puts 'Examples:'
  puts '  add_label("Header")'
  puts '  add_button("Run")'
  puts '  remove_last'
  puts '  gui { window.resize(900, 600) }'
  puts '  items'
  puts '  exit'
end

window.show
QApplication.process_events

puts 'Starting IRB with live layout editor.'
puts 'Objects: app, window, layout, items'
console.help

irb_thread = Thread.new do
  IRB.setup(nil)
  workspace = IRB::WorkSpace.new(console.instance_eval { binding })
  irb = IRB::Irb.new(workspace)
  IRB.conf[:MAIN_CONTEXT] = irb.context

  catch(:IRB_EXIT) { irb.eval_input }
ensure
  jobs << :__exit__
end

while running
  loop do
    job = jobs.pop(true)

    if job == :__exit__
      running = false
      break
    end

    block, reply = job
    begin
      reply << [true, block.call]
    rescue StandardError => e
      reply << [false, e]
    end
  rescue ThreadError
    break
  end

  QApplication.process_events
  running = false if QApplication.top_level_widgets_count.zero?
  sleep(0.01)
end

irb_thread.kill if irb_thread&.alive?
app.dispose

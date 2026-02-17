# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'qt'
require 'irb'

app = QApplication.new(0, [])
window = QWidget.new do |w|
  w.set_window_title('Qt Live IRB')
  w.resize(700, 300)
end

label = QLabel.new(window) do |l|
  l.set_text('Use gui { ... } in IRB to update widgets')
  l.set_alignment(Qt::AlignCenter)
  l.set_geometry(0, 0, 700, 300)
end

window.show
QApplication.process_events

jobs = Queue.new
running = true

console = Object.new
console.instance_variable_set(:@app, app)
console.instance_variable_set(:@window, window)
console.instance_variable_set(:@label, label)
console.instance_variable_set(:@jobs, jobs)

console.define_singleton_method(:app) { @app }
console.define_singleton_method(:window) { @window }
console.define_singleton_method(:label) { @label }

console.define_singleton_method(:gui) do |&block|
  raise ArgumentError, 'pass block to gui { ... }' unless block

  reply = Queue.new
  @jobs << [block, reply]
  ok, value = reply.pop
  raise value unless ok

  value
end

console.define_singleton_method(:help) do
  puts 'Examples:'
  puts '  gui { label.set_text("Hello from IRB") }'
  puts '  gui { window.resize(900, 420) }'
  puts '  gui { window.set_window_title("Changed") }'
  puts '  exit'
end

puts 'Starting IRB. Use gui { ... } to mutate Qt widgets.'
puts 'Objects available: app, window, label'
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

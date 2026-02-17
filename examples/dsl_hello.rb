# frozen_string_literal: true

# $LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'qt'

width = 640
height = 360

app = QApplication.new(0, [])

window = QWidget.new do |w|
  w.setWindowTitle('Qt Ruby App')
  w.resize(width, height)
end

label = QLabel.new(window) do |l|
  l.setText('Hello from Ruby')
  l.setAlignment(Qt::AlignCenter)
  l.setGeometry(0, 0, width, height)
end

exit(app.exec)

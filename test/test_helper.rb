# frozen_string_literal: true

if ENV['QT_QPA_PLATFORM_FORCE_XCB'] == 'true'
  ENV['QT_QPA_PLATFORM'] = 'xcb'
else
  ENV['QT_QPA_PLATFORM'] = 'offscreen'
end

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'minitest/autorun'
require 'qt'

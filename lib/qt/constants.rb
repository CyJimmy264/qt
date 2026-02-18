# frozen_string_literal: true

module Qt
  # Keep Qt-style constant names for API compatibility with upstream Qt naming.
  # rubocop:disable Naming/ConstantName
  AlignCenter = 0x84
  NoFocus = 0
  EventMouseButtonPress = 2
  EventMouseButtonRelease = 3
  EventMouseMove = 5
  EventKeyPress = 6
  EventKeyRelease = 7
  EventFocusIn = 8
  EventFocusOut = 9
  EventEnter = 10
  EventLeave = 11
  EventResize = 14
  KeyLeft = 0x01000012
  KeyUp = 0x01000013
  KeyRight = 0x01000014
  KeyDown = 0x01000015
  KeySpace = 0x20
  KeyN = 0x4e
  ScrollPerItem = 0
  ScrollPerPixel = 1
  ScrollBarAsNeeded = 0
  ScrollBarAlwaysOff = 1
  ScrollBarAlwaysOn = 2
  # rubocop:enable Naming/ConstantName
end
